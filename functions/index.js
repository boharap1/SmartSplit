/**
 * SmartSplit — OTP Cloud Functions
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

async function checkRateLimit(docRef) {
  const snap = await docRef.get();
  if (!snap.exists) return;
  const created = snap.data().createdAt?.toDate?.();
  if (created && Date.now() - created.getTime() < RESEND_COOLDOWN) {
    throw new HttpsError(
      "resource-exhausted",
      "Please wait 60 seconds before requesting another code."
    );
  }
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
    await checkRateLimit(docRef);

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

    await sendMail(email, "Your SmartSplit verification code", verifyHtml(otp));
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
    await checkRateLimit(docRef);

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

    await sendMail(email, "Your SmartSplit password reset code", resetHtml(otp));
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
