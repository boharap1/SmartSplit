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

  static const _cooldownSeconds = 60;

  // Timestamps of the last successful OTP dispatch — survives screen rebuilds.
  static DateTime? _resetSentAt;
  static DateTime? _verifySentAt;

  /// Remaining cooldown in seconds for password-reset requests (0 = ready).
  int get resetCooldownRemaining {
    if (_resetSentAt == null) return 0;
    final elapsed = DateTime.now().difference(_resetSentAt!).inSeconds;
    return (_cooldownSeconds - elapsed).clamp(0, _cooldownSeconds);
  }

  /// Remaining cooldown in seconds for email-verification requests (0 = ready).
  int get verifyCooldownRemaining {
    if (_verifySentAt == null) return 0;
    final elapsed = DateTime.now().difference(_verifySentAt!).inSeconds;
    return (_cooldownSeconds - elapsed).clamp(0, _cooldownSeconds);
  }

  // ── Email verification ────────────────────────────────────────────────────

  Future<OtpResult> requestEmailVerificationOtp() async {
    final result = await _call('requestEmailVerificationOtp', null);
    if (result.success) _verifySentAt = DateTime.now();
    return result;
  }

  Future<OtpResult> verifyEmailOtp(String otp) =>
      _call('verifyEmailOtp', {'otp': otp});

  // ── Registration (pre-creation email verification) ────────────────────────

  static DateTime? _registrationSentAt;

  int get registrationCooldownRemaining {
    if (_registrationSentAt == null) return 0;
    final elapsed = DateTime.now().difference(_registrationSentAt!).inSeconds;
    return (_cooldownSeconds - elapsed).clamp(0, _cooldownSeconds);
  }

  Future<OtpResult> requestRegistrationOtp(String email) async {
    final result = await _call('requestRegistrationOtp', {'email': email});
    if (result.success) _registrationSentAt = DateTime.now();
    return result;
  }

  Future<OtpResult> verifyRegistrationOtp(String email, String otp) =>
      _call('verifyRegistrationOtp', {'email': email, 'otp': otp});

  Future<OtpResult> finalizeRegistration() =>
      _call('finalizeRegistration', null);

  // ── Password reset ────────────────────────────────────────────────────────

  Future<OtpResult> requestPasswordResetOtp(String email) async {
    final result = await _call('requestPasswordResetOtp', {'email': email});
    if (result.success) _resetSentAt = DateTime.now();
    return result;
  }

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
