import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Register with email and password
  Future<({UserModel? user, String? error})> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user == null) {
        return (user: null, error: 'Registration failed. Please try again.');
      }

      await credential.user!.updateDisplayName(name.trim());

      final UserModel userModel = UserModel(
        uid: credential.user!.uid,
        name: name.trim(),
        email: email.trim(),
        createdAt: DateTime.now(),
      );

      await _firestore
          .collection('users')
          .doc(credential.user!.uid)
          .set(userModel.toFirestore());

      await credential.user!.sendEmailVerification();

      return (user: userModel, error: null);
    } on FirebaseAuthException catch (e) {
      return (user: null, error: _getErrorMessage(e.code));
    } catch (e) {
      return (user: null, error: 'Registration failed. Please try again.');
    }
  }

  // Sign in with email and password
  Future<({UserModel? user, String? error})> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      if (credential.user == null) {
        return (user: null, error: 'Sign in failed. Please try again.');
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(credential.user!.uid)
          .get();

      if (!userDoc.exists) {
        // User exists in Auth but not in Firestore - create document
        final UserModel userModel = UserModel(
          uid: credential.user!.uid,
          name: credential.user!.displayName ?? 'User',
          email: email.trim(),
          createdAt: DateTime.now(),
        );
        await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .set(userModel.toFirestore());
        return (user: userModel, error: null);
      }

      final userModel = UserModel.fromFirestore(userDoc);
      return (user: userModel, error: null);
    } on FirebaseAuthException catch (e) {
      return (user: null, error: _getErrorMessage(e.code));
    } catch (e) {
      return (user: null, error: 'Sign in failed. Please try again.');
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<({bool success, String? error})> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return (success: false, error: 'Failed to send reset email. Please try again.');
    }
  }

  Future<({bool success, String? error})> resendEmailVerification() async {
    try {
      if (currentUser != null) {
        await currentUser!.sendEmailVerification();
        return (success: true, error: null);
      }
      return (success: false, error: 'No user signed in.');
    } catch (e) {
      return (success: false, error: 'Failed to resend verification email. Please try again.');
    }
  }

  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  Future<void> reloadUser() async {
    await currentUser?.reload();
  }

  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered. Please sign in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email/password sign in is not enabled.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}