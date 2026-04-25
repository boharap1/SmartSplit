import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Result type used by every OtpService method.
typedef OtpResult = ({bool success, String? error});

class OtpService {
  static final OtpService instance = OtpService._();
  OtpService._();

  // Must match the region set in functions/index.js (setGlobalOptions).
  final FirebaseFunctions _fn =
      FirebaseFunctions.instanceFor(region: 'europe-west2');

  // ── Email verification ────────────────────────────────────────────────────

  Future<OtpResult> requestEmailVerificationOtp() =>
      _call('requestEmailVerificationOtp', null);

  Future<OtpResult> verifyEmailOtp(String otp) =>
      _call('verifyEmailOtp', {'otp': otp});

  // ── Password reset ────────────────────────────────────────────────────────

  Future<OtpResult> requestPasswordResetOtp(String email) =>
      _call('requestPasswordResetOtp', {'email': email});

  Future<OtpResult> verifyPasswordResetOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) =>
      _call('verifyPasswordResetOtp', {
        'email':       email,
        'otp':         otp,
        'newPassword': newPassword,
      });

  // ── Private ───────────────────────────────────────────────────────────────

  Future<OtpResult> _call(String name, Map<String, dynamic>? data) async {
    try {
      // Force-refresh the ID token before every call. Firebase Functions v2
      // requires a valid, non-expired token in the Authorization header.
      // getIdToken(true) is a no-op for unauthenticated flows (currentUser
      // is null for password-reset calls, which is fine).
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      final callable = _fn.httpsCallable(name);
      await callable.call(data);
      return (success: true, error: null);
    } on FirebaseFunctionsException catch (e) {
      return (success: false, error: e.message ?? 'Something went wrong.');
    } catch (_) {
      return (success: false, error: 'Network error. Please try again.');
    }
  }
}
