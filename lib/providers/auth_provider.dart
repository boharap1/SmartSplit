import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/biometric_service.dart';
import '../services/otp_service.dart';
import '../services/secure_storage_manager.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status       = AuthStatus.initial;
  UserModel? _user;
  String?    _errorMessage;

  // ── Biometric state ───────────────────────────────────────────────────────
  bool _biometricEnabled  = false;
  bool _biometricUnlocked = false; // true after successful lock-screen auth

  // ── Getters ───────────────────────────────────────────────────────────────

  AuthStatus get status          => _status;
  UserModel? get user            => _user;
  String?    get errorMessage    => _errorMessage;
  bool get isAuthenticated       => _status == AuthStatus.authenticated;
  bool get isLoading             => _status == AuthStatus.loading;
  bool get isEmailVerified       => _authService.isEmailVerified;
  User?      get firebaseUser    => _authService.currentUser;
  bool get biometricEnabled      => _biometricEnabled;
  bool get biometricUnlocked     => _biometricUnlocked;

  // ── Initialise ────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        // Best-effort reload: syncs emailVerified from the server so a user who
        // verified in a previous session isn't stuck on EmailVerificationScreen.
        // Wrapped in its own try-catch so a network failure at startup does not
        // force the user back to LoginScreen.
        try { await _authService.reloadUser(); } catch (_) {}
        _user = await _authService.getUserData(currentUser.uid);
        if (_user != null) {
          _status = AuthStatus.authenticated;
          await _loadBiometricPreference();
          // biometricUnlocked stays false — lock screen will prompt.
        } else {
          _status = AuthStatus.unauthenticated;
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // ── Biometric ─────────────────────────────────────────────────────────────

  Future<void> _loadBiometricPreference() async {
    _biometricEnabled =
        await SecureStorageManager.instance.isBiometricEnabled();
  }

  /// Called by BiometricLockScreen after a successful OS-level auth.
  void unlockBiometric() {
    _biometricUnlocked = true;
    notifyListeners();
  }

  /// Toggle biometric lock on/off. Triggers OS prompt before enabling to
  /// confirm the device owner is the one turning it on.
  Future<bool> setBiometricEnabled({required bool value}) async {
    if (value) {
      final available = await BiometricService.instance.isAvailable();
      if (!available) return false;

      final result = await BiometricService.instance.authenticate(
        reason: 'Confirm your identity to enable biometric lock',
      );
      if (result != BiometricResult.success) return false;
    }

    await SecureStorageManager.instance.setBiometricEnabled(value: value);
    _biometricEnabled = value;
    if (value) _biometricUnlocked = true; // already authenticated above
    notifyListeners();
    return true;
  }

  // ── Register ──────────────────────────────────────────────────────────────

  /// Called by PasswordSetupScreen after the user has verified their email via
  /// OTP. Creates the Firebase Auth account, then calls finalizeRegistration
  /// to mark emailVerified = true via the Admin SDK.
  Future<bool> registerWithVerifiedEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.registerWithEmail(
      name:     name,
      email:    email,
      password: password,
    );

    if (result.user == null) {
      _errorMessage = result.error;
      _status       = AuthStatus.error;
      notifyListeners();
      return false;
    }

    // Best-effort: mark emailVerified = true in Firebase Auth + Firestore.
    // If this fails the account is still usable; don't block the user.
    await OtpService.instance.finalizeRegistration();

    _user              = result.user;
    _status            = AuthStatus.authenticated;
    _biometricUnlocked = true;
    await SecureStorageManager.instance.saveLastEmail(email);

    // Sync the fresh emailVerified flag into the in-memory user object.
    try { await _authService.reloadUser(); } catch (_) {}
    try { await _authService.refreshToken(); } catch (_) {}

    notifyListeners();
    return true;
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.registerWithEmail(
      name: name,
      email: email,
      password: password,
    );

    if (result.user != null) {
      _user   = result.user;
      _status = AuthStatus.authenticated;
      _biometricUnlocked = true; // new account — no lock needed on first open
      await SecureStorageManager.instance.saveLastEmail(email);
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.error;
      _status       = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  // ── Sign In ───────────────────────────────────────────────────────────────

  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.signInWithEmail(
      email: email,
      password: password,
    );

    if (result.user != null) {
      _user   = result.user;
      _status = AuthStatus.authenticated;
      _biometricUnlocked = true; // just authenticated manually — no lock
      await SecureStorageManager.instance.saveLastEmail(email);
      await _loadBiometricPreference();
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.error;
      _status       = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async {
    _status = AuthStatus.loading;
    notifyListeners();

    final uid = _user?.uid ?? firebaseUser?.uid;
    await _authService.signOut();
    if (uid != null) {
      await SecureStorageManager.instance.clearSessionData(uid);
    } else {
      await SecureStorageManager.instance.clearAll();
    }

    _user              = null;
    _status            = AuthStatus.unauthenticated;
    _errorMessage      = null;
    _biometricEnabled  = false;
    _biometricUnlocked = false;
    notifyListeners();
  }

  // ── Email verification ────────────────────────────────────────────────────

  Future<bool> checkEmailVerification() async {
    await _authService.reloadUser();
    // Force JWT refresh so Firestore rules immediately see email_verified = true.
    // Without this, the token cache holds email_verified=false for up to 1 hour.
    await _authService.refreshToken();
    notifyListeners();
    return isEmailVerified;
  }

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<bool> updateProfile({
    String? name,
    String? phoneNumber,
    String? profilePicture,
    String? dob,
    String? gender,
  }) async {
    final uid = firebaseUser?.uid;
    if (uid == null) return false;

    final result = await _authService.updateProfile(
      uid:            uid,
      name:           name,
      phoneNumber:    phoneNumber,
      profilePicture: profilePicture,
      dob:            dob,
      gender:         gender,
    );

    if (result.success) {
      _user = _user?.copyWith(
        name:           name,
        phoneNumber:    phoneNumber,
        profilePicture: profilePicture,
        dob:            dob,
        gender:         gender,
      );
      _errorMessage = null;
    } else {
      _errorMessage = result.error;
    }
    notifyListeners();
    return result.success;
  }

  Future<void> refreshProfile() async {
    final fresh = await _authService.refreshUserData();
    if (fresh != null) {
      _user = fresh;
      notifyListeners();
    }
  }

  // ── Password management ───────────────────────────────────────────────────

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _errorMessage = null;
    final result = await _authService.changePassword(
      currentPassword: currentPassword,
      newPassword:     newPassword,
    );
    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    return result.success;
  }

  // ── Account deletion ──────────────────────────────────────────────────────

  Future<bool> deleteAccount({required String password}) async {
    _errorMessage = null;
    final result = await _authService.deleteAccount(password: password);
    if (result.success) {
      await SecureStorageManager.instance.clearAll();
      _user              = null;
      _status            = AuthStatus.unauthenticated;
      _biometricEnabled  = false;
      _biometricUnlocked = false;
    } else {
      _errorMessage = result.error;
    }
    notifyListeners();
    return result.success;
  }

  // ── Multi-device logout ───────────────────────────────────────────────────

  Future<bool> logoutAllDevices() async {
    _errorMessage = null;
    final result = await _authService.logoutAllDevices();
    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }
    return result.success;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) _status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
