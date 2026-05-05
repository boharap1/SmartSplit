import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Thin wrapper around local_auth.
///
/// This service does NOT store any credentials. It authenticates the device
/// owner using the OS-level biometric / credential prompt (fingerprint, face,
/// PIN, pattern). Firebase Auth still holds the actual session token — biometric
/// is used only as an app-lock layer on cold start.
class BiometricService {
  static final BiometricService instance = BiometricService._();
  BiometricService._();

  final LocalAuthentication _auth = LocalAuthentication();

  // ── Capability checks ─────────────────────────────────────────────────────

  Future<bool> isAvailable() async {
    try {
      final canCheck    = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } on PlatformException {
      return false;
    }
  }

  Future<List<BiometricType>> availableTypes() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Returns a human-readable label for the strongest available biometric.
  Future<String> primaryLabel() async {
    final types = await availableTypes();
    if (types.contains(BiometricType.face))        return 'Face ID';
    if (types.contains(BiometricType.fingerprint)) return 'Fingerprint';
    if (types.contains(BiometricType.iris))        return 'Iris';
    return 'Device credentials';
  }

  // ── Authentication ────────────────────────────────────────────────────────

  Future<BiometricResult> authenticate({
    String reason = 'Verify your identity to access SmartSplit',
  }) async {
    try {
      final success = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth:          true,
          biometricOnly:       false, // allow PIN/pattern as fallback
          sensitiveTransaction: false,
        ),
      );
      return success ? BiometricResult.success : BiometricResult.failure;
    } on PlatformException catch (e) {
      if (e.code == 'NotAvailable' || e.code == 'NotEnrolled') {
        return BiometricResult.notAvailable;
      }
      return BiometricResult.failure;
    }
  }

  Future<void> cancel() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}

enum BiometricResult { success, failure, notAvailable }
