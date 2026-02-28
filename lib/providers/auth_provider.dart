import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus {
  initial,
  loading,
  authenticated,
  unauthenticated,
  error,
}

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();

  AuthStatus _status = AuthStatus.initial;
  UserModel? _user;
  String? _errorMessage;

  // Getters
  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isEmailVerified => _authService.isEmailVerified;
  User? get firebaseUser => _authService.currentUser;

  // Initialize - check if user is already logged in
  Future<void> initialize() async {
    _status = AuthStatus.loading;
    notifyListeners();

    try {
      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        // Fetch user data from Firestore
        _user = await _authService.getUserData(currentUser.uid);
        if (_user != null) {
          _status = AuthStatus.authenticated;
        } else {
          _status = AuthStatus.unauthenticated;
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  // Register
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
      _user = result.user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.error;
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  // Sign In
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
      _user = result.user;
      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result.error;
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  // Sign Out
  Future<void> signOut() async {
    _status = AuthStatus.loading;
    notifyListeners();

    await _authService.signOut();

    _user = null;
    _status = AuthStatus.unauthenticated;
    _errorMessage = null;
    notifyListeners();
  }

  // Send Password Reset Email
  Future<bool> sendPasswordResetEmail(String email) async {
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.sendPasswordResetEmail(email);

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }

    return result.success;
  }

  // Resend Email Verification
  Future<bool> resendEmailVerification() async {
    final result = await _authService.resendEmailVerification();

    if (!result.success) {
      _errorMessage = result.error;
      notifyListeners();
    }

    return result.success;
  }

  // Check Email Verification Status
  Future<bool> checkEmailVerification() async {
    await _authService.reloadUser();
    notifyListeners();
    return isEmailVerified;
  }

  // Clear Error
  void clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }
}