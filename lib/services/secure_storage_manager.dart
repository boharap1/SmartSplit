import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps flutter_secure_storage with typed accessors.
///
/// Android: uses EncryptedSharedPreferences (AES-256, requires minSdk 23).
/// iOS: uses Keychain with first-unlock accessibility.
///
/// Raw SharedPreferences must NOT be used for any data stored here — all
/// sensitive flags go through this class only.
class SecureStorageManager {
  static final SecureStorageManager instance = SecureStorageManager._();
  SecureStorageManager._();

  static const _kBiometricEnabled       = 'biometric_enabled';
  static const _kLastEmail              = 'last_login_email';
  static const _kSessionVersionPrefix   = 'session_v_';

  final FlutterSecureStorage _store = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Biometric preference ──────────────────────────────────────────────────

  Future<void> setBiometricEnabled({required bool value}) =>
      _store.write(key: _kBiometricEnabled, value: value.toString());

  Future<bool> isBiometricEnabled() async {
    try {
      return await _store.read(key: _kBiometricEnabled) == 'true';
    } catch (_) {
      return false;
    }
  }

  // ── Last-used email (pre-fill login field) ────────────────────────────────

  Future<void> saveLastEmail(String email) =>
      _store.write(key: _kLastEmail, value: email);

  Future<String?> getLastEmail() async {
    try {
      return await _store.read(key: _kLastEmail);
    } catch (_) {
      return null;
    }
  }

  // ── Session version (multi-device logout) ────────────────────────────────

  Future<void> saveSessionVersion(String uid, int version) =>
      _store.write(key: '$_kSessionVersionPrefix$uid', value: version.toString());

  Future<int?> getSessionVersion(String uid) async {
    try {
      final v = await _store.read(key: '$_kSessionVersionPrefix$uid');
      return v != null ? int.tryParse(v) : null;
    } catch (_) {
      return null;
    }
  }

  // ── Sign-out wipe: clears auth state but keeps last email for prefill ─────

  Future<void> clearSessionData(String uid) async {
    try {
      await _store.delete(key: _kBiometricEnabled);
      await _store.delete(key: '$_kSessionVersionPrefix$uid');
    } catch (_) {}
  }

  // ── Full wipe (call on account deletion) ─────────────────────────────────

  Future<void> clearAll() async {
    try {
      await _store.deleteAll();
    } catch (_) {}
  }
}
