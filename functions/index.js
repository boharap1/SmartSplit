/**
 * SmartSplit — OTP Cloud Functions v2
 *
 * Exported functions:
 *   requestEmailVerificationOtp  — (auth required) sends 6-digit OTP for account verification
 *   verifyEmailOtp               — (auth required) validates OTP, marks emailVerified = true
 *   requestPasswordResetOtp      — (no auth) sends 6-digit OTP for password reset
 *   verifyPasswordResetOtp       — (no auth) validates OTP, updates password via Admin SDK
 *
 * ── One-time setup ───────────────────────────────────────────────────────────
 *
 *   Prerequisites
 *     npm install -g firebase-tools
 *     firebase login
 *     cd functions && npm install
 *
 *   Gmail App Password (recommended over your real password):
 *     Google Account → Security → 2-Step Verification (enable) →
 *     Security → App passwords → Other → Generate → copy the 16-char code
 *
 *   Set credentials (edit functions/.env — never commit this file):
 *     EMAIL_USER=yourGmail@gmail.com
 *     EMAIL_PASS=abcd efgh ijkl mnop   ← Gmail App Password (spaces are fine)
 *
 *   Deploy:
 *     firebase deploy --only functions
 *
 * ── Production upgrade ───────────────────────────────────────────────────────
 *   Replace the nodemailer block with SendGrid / Mailgun / AWS SES for
 *   higher deliverability and no spam-folder issues. The rest of the logic
 *   stays identical.
 */

"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { setGlobalOptions }   = require("firebase-functions/v2");
const admin                  = require("firebase-admin");
const nodemailer              = require("nodemailer");
const crypto                 = require("crypto");
const dns                    = require("dns").promises;

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "europe-west2", maxInstances: 10 });

// ── Email transport ──────────────────────────────────────────────────────────
// Credentials are read from functions/.env (local) or Firebase environment
// variables set in the Console (production).

const _transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.EMAIL_USER,
    pass: process.env.EMAIL_PASS,
  },
});

/**
 * Returns false when the email domain has no MX records (unroutable address).
 * Catches fake domains like test@notreal.xyz before we attempt to send.
 * Note: a domain CAN have MX records even if the specific mailbox doesn't
 * exist (e.g. test@gmail.com) — those cases pass through here and SMTP
 * accepts them. This check only eliminates the worst invalid-domain case.
 */
async function domainIsReachable(email) {
  const domain = email.split("@")[1];
  if (!domain) return false;
  try {
    const records = await dns.resolveMx(domain);
    return records && records.length > 0;
  } catch {
    return false;
  }
}

async function sendMail(to, subject, html) {
  try {
    await _transporter.sendMail({
      from: `"SmartSplit" <${process.env.EMAIL_USER}>`,
      to,
      subject,
      html,
    });
  } catch (err) {
    console.error("sendMail failed:", err.message ?? err);
    throw new HttpsError(
      "internal",
      "Failed to send the code. Check your spam folder or try again."
    );
  }
}

// ── OTP helpers ──────────────────────────────────────────────────────────────

/** Cryptographically random 6-digit string (000000–999999). */
function generateOtp() {
  return crypto.randomInt(0, 1_000_000).toString().padStart(6, "0");
}

/**
 * Salted SHA-256 hash.
 * Salt = uid prevents rainbow-table attacks even if the hash field leaks —
 * an attacker without the uid cannot pre-compute the 1M hash space.
 */
function hashOtp(otp, uid) {
  return crypto
    .createHash("sha256")
    .update(`smartsplit:${uid}:${otp}`)
    .digest("hex");
}

/** Constant-time string comparison to prevent timing attacks. */
function safeEqual(a, b) {
  try {
    return crypto.timingSafeEqual(Buffer.from(a, "hex"), Buffer.from(b, "hex"));
  } catch {
    return false;
  }
}

const OTP_TTL_MS      = 5 * 60 * 1000;   // 5 minutes
const RESEND_COOLDOWN = 60 * 1000;        // 60 s between requests
const MAX_ATTEMPTS    = 5;

// ── Guard: rate limit ────────────────────────────────────────────────────────
//
// Uses a dedicated `rate_limits` collection that is separate from the OTP doc,
// so deleting/expiring an OTP cannot reset the cooldown window. The check and
// timestamp update are wrapped in a transaction to make them atomic.

async function checkAndSetRateLimit(uid, type) {
  const docRef = db.collection("rate_limits").doc(`${type}_${uid}`);
  await db.runTransaction(async (t) => {
    const snap = await t.get(docRef);
    if (snap.exists) {
      const lastMs = snap.data().at?.toMillis() ?? 0;
      if (Date.now() - lastMs < RESEND_COOLDOWN) {
        throw new HttpsError(
          "resource-exhausted",
          "Please wait 60 seconds before requesting another code."
        );
      }
    }
    t.set(docRef, { at: admin.firestore.Timestamp.fromMillis(Date.now()) });
  });
}

// ── Guard: validate stored OTP document ─────────────────────────────────────

async function validateOtpDoc(docRef, inputOtp, uid) {
  const snap = await docRef.get();

  if (!snap.exists) {
    throw new HttpsError("not-found", "No code found. Please request a new one.");
  }

  const d = snap.data();

  if (d.used) {
    throw new HttpsError("already-exists", "This code has already been used.");
  }
  if (d.expiresAt.toDate() < new Date()) {
    await docRef.delete();
    throw new HttpsError("deadline-exceeded", "Code expired. Please request a new one.");
  }
  if (d.attempts >= MAX_ATTEMPTS) {
    await docRef.delete();
    throw new HttpsError(
      "resource-exhausted",
      "Too many incorrect attempts. Please request a new code."
    );
  }

  if (!safeEqual(hashOtp(inputOtp, uid), d.hashedOtp)) {
    const newAttempts = d.attempts + 1;
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    const left = MAX_ATTEMPTS - newAttempts;
    throw new HttpsError(
      "invalid-argument",
      left > 0
        ? `Incorrect code. ${left} attempt${left === 1 ? "" : "s"} remaining.`
        : "Incorrect code."
    );
  }
}

// ── HTML email templates ─────────────────────────────────────────────────────

function verifyHtml(otp) {
  return `
  <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:32px;background:#f9fafb;border-radius:12px;border:1px solid #e5e7eb;">
    <h2 style="color:#00897B;margin:0 0 8px;">Verify your email</h2>
    <p style="color:#6b7280;margin:0 0 28px;">Enter this code in SmartSplit to activate your account. It expires in <strong>5 minutes</strong>.</p>
    <div style="text-align:center;padding:24px;background:#fff;border-radius:8px;border:1px solid #d1fae5;margin-bottom:24px;">
      <span style="letter-spacing:14px;font-size:40px;font-weight:700;color:#00897B;font-family:monospace;">${otp}</span>
    </div>
    <p style="color:#9ca3af;font-size:13px;margin:0;">Didn't create a SmartSplit account? You can safely ignore this email.</p>
  </div>`;
}

function resetHtml(otp) {
  return `
  <div style="font-family:Arial,sans-serif;max-width:480px;margin:auto;padding:32px;background:#f9fafb;border-radius:12px;border:1px solid #e5e7eb;">
    <h2 style="color:#00897B;margin:0 0 8px;">Reset your password</h2>
    <p style="color:#6b7280;margin:0 0 28px;">Enter this code in SmartSplit to reset your password. It expires in <strong>5 minutes</strong>.</p>
    <div style="text-align:center;padding:24px;background:#fff;border-radius:8px;border:1px solid #d1fae5;margin-bottom:24px;">
      <span style="letter-spacing:14px;font-size:40px;font-weight:700;color:#00897B;font-family:monospace;">${otp}</span>
    </div>
    <p style="color:#9ca3af;font-size:13px;margin:0;">Didn't request this? Your password won't change — ignore this email.</p>
  </div>`;
}

// ════════════════════════════════════════════════════════════════════════════
// Function 1 — Request email-verification OTP  (requires signed-in user)
// ════════════════════════════════════════════════════════════════════════════

exports.requestEmailVerificationOtp = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const uid   = request.auth.uid;
    const email = request.auth.token.email;
    if (!email) throw new HttpsError("failed-precondition", "No email on account.");

    const docRef = db.collection("otp_requests").doc(`verify_${uid}`);
    await checkAndSetRateLimit(uid, "verify");

    const otp = generateOtp();

    await docRef.set({
      hashedOtp:  hashOtp(otp, uid),
      expiresAt:  admin.firestore.Timestamp.fromDate(new Date(Date.now() + OTP_TTL_MS)),
      attempts:   0,
      used:       false,
      type:       "verification",
      uid,
      createdAt:  admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await sendMail(email, "Your SmartSplit verification code", verifyHtml(otp));
    } catch (mailErr) {
      // Roll back the OTP doc and rate-limit stamp so the user can retry
      // immediately without waiting 60 s for a failure they didn't cause.
      await Promise.allSettled([
        docRef.delete(),
        db.collection("rate_limits").doc(`verify_${uid}`).delete(),
      ]);
      throw mailErr;
    }
    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 2 — Verify email OTP  (requires signed-in user)
// ════════════════════════════════════════════════════════════════════════════

exports.verifyEmailOtp = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const { otp } = request.data;
    if (!otp || typeof otp !== "string" || !/^\d{6}$/.test(otp)) {
      throw new HttpsError("invalid-argument", "Enter a valid 6-digit code.");
    }

    const uid    = request.auth.uid;
    const docRef = db.collection("otp_requests").doc(`verify_${uid}`);

    await validateOtpDoc(docRef, otp, uid);  // throws on any failure

    // Mark verified in Firebase Auth (authoritative) and Firestore (redundant).
    await admin.auth().updateUser(uid, { emailVerified: true });
    await db.collection("users").doc(uid).update({ emailVerified: true }).catch(() => {});
    await docRef.update({ used: true });

    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 3 — Request password-reset OTP  (no auth required)
// ════════════════════════════════════════════════════════════════════════════

exports.requestPasswordResetOtp = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    const rawEmail = request.data?.email;
    if (!rawEmail) throw new HttpsError("invalid-argument", "Email is required.");
    const email = rawEmail.trim().toLowerCase();

    let user;
    try {
      user = await admin.auth().getUserByEmail(email);
    } catch {
      // Always succeed to avoid email-enumeration attacks.
      return { success: true };
    }

    const uid    = user.uid;
    const docRef = db.collection("otp_requests").doc(`reset_${uid}`);
    await checkAndSetRateLimit(uid, "reset");

    const otp = generateOtp();

    await docRef.set({
      hashedOtp:  hashOtp(otp, uid),
      expiresAt:  admin.firestore.Timestamp.fromDate(new Date(Date.now() + OTP_TTL_MS)),
      attempts:   0,
      used:       false,
      type:       "password_reset",
      uid,
      email,
      createdAt:  admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await sendMail(email, "Your SmartSplit password reset code", resetHtml(otp));
    } catch (mailErr) {
      await Promise.allSettled([
        docRef.delete(),
        db.collection("rate_limits").doc(`reset_${uid}`).delete(),
      ]);
      throw mailErr;
    }
    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 4 — Verify reset OTP and set new password  (no auth required)
// ════════════════════════════════════════════════════════════════════════════

exports.verifyPasswordResetOtp = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    const { email: rawEmail, otp, newPassword } = request.data ?? {};

    if (!rawEmail || !otp || !newPassword) {
      throw new HttpsError("invalid-argument", "Email, code, and new password are required.");
    }
    if (!/^\d{6}$/.test(otp)) {
      throw new HttpsError("invalid-argument", "Enter a valid 6-digit code.");
    }
    if (newPassword.length < 8) {
      throw new HttpsError("invalid-argument", "Password must be at least 8 characters.");
    }

    const email = rawEmail.trim().toLowerCase();

    let user;
    try {
      user = await admin.auth().getUserByEmail(email);
    } catch {
      throw new HttpsError("not-found", "No account found with that email.");
    }

    const uid    = user.uid;
    const docRef = db.collection("otp_requests").doc(`reset_${uid}`);

    await validateOtpDoc(docRef, otp, uid);  // throws on any failure

    await admin.auth().updateUser(uid, { password: newPassword });
    await docRef.update({ used: true });

    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 5 — Request pre-registration OTP  (no auth — email must not exist)
// ════════════════════════════════════════════════════════════════════════════

exports.requestRegistrationOtp = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    const rawEmail = request.data?.email;
    if (!rawEmail) throw new HttpsError("invalid-argument", "Email is required.");
    const email = rawEmail.trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpsError("invalid-argument", "Enter a valid email address.");
    }

    // Reject if an account already exists — user should sign in instead.
    try {
      await admin.auth().getUserByEmail(email);
      throw new HttpsError("already-exists", "An account already exists with this email. Please sign in.");
    } catch (err) {
      if (err.code === "app/already-exists" || (err.httpErrorCode && err.httpErrorCode.status === 409)) throw err;
      if (err instanceof HttpsError) throw err;
      // auth/user-not-found is expected — continue
    }

    // Reject domains with no MX record — catches obviously fake addresses
    // before spending a send attempt. Real-mailbox-not-found cases (e.g.
    // test@gmail.com) still pass here; SMTP accepts those silently.
    const reachable = await domainIsReachable(email);
    if (!reachable) {
      throw new HttpsError(
        "invalid-argument",
        "This email address doesn't appear to be valid. Please check it and try again."
      );
    }

    // Use an email-derived key since there is no uid yet.
    const emailHash = crypto.createHash("sha256").update(email).digest("hex").substring(0, 32);
    await checkAndSetRateLimit(emailHash, "register");

    const otp    = generateOtp();
    const docRef = db.collection("otp_requests").doc(`register_${emailHash}`);

    await docRef.set({
      hashedOtp: hashOtp(otp, emailHash),
      expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + OTP_TTL_MS)),
      attempts:  0,
      used:      false,
      type:      "registration",
      email,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    try {
      await sendMail(email, "Your SmartSplit registration code", verifyHtml(otp));
    } catch (mailErr) {
      await Promise.allSettled([
        docRef.delete(),
        db.collection("rate_limits").doc(`register_${emailHash}`).delete(),
      ]);
      throw mailErr;
    }
    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 6 — Verify registration OTP  (no auth)
// ════════════════════════════════════════════════════════════════════════════

exports.verifyRegistrationOtp = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    const { email: rawEmail, otp } = request.data ?? {};
    if (!rawEmail || !otp) {
      throw new HttpsError("invalid-argument", "Email and code are required.");
    }
    if (!/^\d{6}$/.test(otp)) {
      throw new HttpsError("invalid-argument", "Enter a valid 6-digit code.");
    }

    const email     = rawEmail.trim().toLowerCase();
    const emailHash = crypto.createHash("sha256").update(email).digest("hex").substring(0, 32);
    const docRef    = db.collection("otp_requests").doc(`register_${emailHash}`);

    await validateOtpDoc(docRef, otp, emailHash);
    await docRef.update({ used: true });

    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 7 — Finalise registration: mark emailVerified after account created
// Called immediately after createUserWithEmailAndPassword succeeds.
// ════════════════════════════════════════════════════════════════════════════

exports.finalizeRegistration = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const rawEmail = request.auth.token.email;
    if (!rawEmail) throw new HttpsError("failed-precondition", "No email on account.");
    const email     = rawEmail.trim().toLowerCase();
    const emailHash = crypto.createHash("sha256").update(email).digest("hex").substring(0, 32);

    const docRef = db.collection("otp_requests").doc(`register_${emailHash}`);
    const snap   = await docRef.get();

    if (!snap.exists || !snap.data().used) {
      throw new HttpsError(
        "failed-precondition",
        "Email not pre-verified. Please complete email verification first."
      );
    }

    const uid = request.auth.uid;
    await admin.auth().updateUser(uid, { emailVerified: true });
    await db.collection("users").doc(uid).update({ emailVerified: true }).catch(() => {});
    await docRef.delete();

    return { success: true };
  }
);

// ════════════════════════════════════════════════════════════════════════════
// Function 8 — Dispatch in-app notifications  (requires signed-in user)
//
// Writes to users/{uid}/notifications via Admin SDK (bypasses Firestore rules)
// and sends FCM push to each recipient's registered device token.
// ════════════════════════════════════════════════════════════════════════════

exports.dispatchNotification = onCall(
  { enforceAppCheck: false, invoker: "public" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");

    const {
      toUserIds,
      excludeUserId,
      type,
      title,
      body,
      groupId,
      relatedId,
      fromUserName,
    } = request.data ?? {};

    if (!Array.isArray(toUserIds) || toUserIds.length === 0) {
      throw new HttpsError("invalid-argument", "toUserIds must be a non-empty array.");
    }
    if (!type || !title || !body) {
      throw new HttpsError("invalid-argument", "type, title, and body are required.");
    }

    // If a groupId is provided, verify the caller is a member of that group.
    if (groupId) {
      const groupSnap = await db.collection("groups").doc(groupId).get();
      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "Group not found.");
      }
      const members = groupSnap.data().members ?? [];
      if (!members.includes(request.auth.uid)) {
        throw new HttpsError("permission-denied", "Not a member of this group.");
      }
    }

    const recipients = toUserIds.filter((id) => id !== excludeUserId);
    if (recipients.length === 0) return { success: true };

    const batch = db.batch();
    const now   = admin.firestore.FieldValue.serverTimestamp();

    for (const uid of recipients) {
      const ref = db.collection("users").doc(uid).collection("notifications").doc();
      batch.set(ref, {
        id:        ref.id,
        type,
        title,
        body,
        isRead:    false,
        createdAt: now,
        ...(groupId      && { groupId }),
        ...(relatedId    && { relatedId }),
        ...(fromUserName && { fromUserName }),
      });
    }
    await batch.commit();

    // Best-effort FCM push to each recipient's device token.
    const tokenDocs = await Promise.all(
      recipients.map((uid) => db.collection("users").doc(uid).get())
    );
    const messages = tokenDocs
      .map((snap) => snap.data()?.fcmToken)
      .filter(Boolean)
      .map((token) => ({
        token,
        notification: { title, body },
        data: {
          type,
          ...(groupId   && { groupId }),
          ...(relatedId && { relatedId }),
        },
        android: { priority: "high" },
      }));

    if (messages.length > 0) {
      await admin.messaging().sendEach(messages);
    }

    return { success: true };
  }
);
