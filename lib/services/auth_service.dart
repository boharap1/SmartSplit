import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import 'secure_storage_manager.dart';

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

  /// Re-fetches the current user's Firestore document.
  Future<UserModel?> refreshUserData() async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    return getUserData(uid);
  }

  /// Updates only the provided fields in Firestore and Firebase Auth display name.
  /// Pass null for any field you do not want to change.
  /// Pass an empty string ('') to explicitly clear an optional field.
  Future<({bool success, String? error})> updateProfile({
    required String uid,
    String? name,
    String? phoneNumber,
    String? profilePicture,
    String? dob,
    String? gender,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null && name.isNotEmpty) updates['name'] = name;
      if (phoneNumber != null)    updates['phoneNumber']    = phoneNumber;
      if (profilePicture != null) updates['profilePicture'] = profilePicture;
      if (dob != null)            updates['dob']            = dob;
      if (gender != null)         updates['gender']         = gender;

      if (updates.isEmpty) return (success: true, error: null);

      await _firestore.collection('users').doc(uid).update(updates);

      if (name != null && name.isNotEmpty) {
        await currentUser?.updateDisplayName(name);
      }

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to update profile. Please try again.');
    }
  }

  // ── Change Password ───────────────────────────────────────────────────────

  Future<({bool success, String? error})> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = currentUser;
      if (user == null || user.email == null) {
        return (success: false, error: 'Not signed in.');
      }
      final credential = EmailAuthProvider.credential(
        email:    user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return (success: false, error: 'Failed to change password. Please try again.');
    }
  }

  // ── Delete Account ────────────────────────────────────────────────────────

  Future<({bool success, String? error})> deleteAccount({
    required String password,
  }) async {
    try {
      final user = currentUser;
      if (user == null || user.email == null) {
        return (success: false, error: 'Not signed in.');
      }
      final credential = EmailAuthProvider.credential(
        email:    user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      // Delete Firestore document first, then Auth user
      await _firestore.collection('users').doc(user.uid).delete();
      await user.delete();
      return (success: true, error: null);
    } on FirebaseAuthException catch (e) {
      return (success: false, error: _getErrorMessage(e.code));
    } catch (e) {
      return (success: false, error: 'Failed to delete account. Please try again.');
    }
  }

  // ── Session version (logout all other devices) ────────────────────────────

  /// Increments sessionVersion in Firestore and syncs the current device's
  /// local copy so it stays valid while all other sessions are invalidated.
  Future<({bool success, String? error})> logoutAllDevices() async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return (success: false, error: 'Not signed in.');

      await _firestore.collection('users').doc(uid).update({
        'sessionVersion': FieldValue.increment(1),
      });

      final doc        = await _firestore.collection('users').doc(uid).get();
      final newVersion = (doc.data()?['sessionVersion'] as int?) ?? 1;

      await SecureStorageManager.instance.saveSessionVersion(uid, newVersion);

      return (success: true, error: null);
    } catch (e) {
      return (success: false, error: 'Failed to logout from other devices.');
    }
  }

  /// Saves the current Firestore sessionVersion locally (call after sign-in).
  Future<void> saveLocalSessionVersion() async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    try {
      final doc     = await _firestore.collection('users').doc(uid).get();
      final version = (doc.data()?['sessionVersion'] as int?) ?? 0;
      await SecureStorageManager.instance.saveSessionVersion(uid, version);
    } catch (_) {}
  }

  /// Returns false if another device called logoutAllDevices since this
  /// session last signed in (i.e., local version < Firestore version).
  Future<bool> isSessionValid() async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    try {
      final localVersion = await SecureStorageManager.instance.getSessionVersion(uid);
      if (localVersion == null) {
        // First launch after install — save and treat as valid.
        await saveLocalSessionVersion();
        return true;
      }
      final doc              = await _firestore.collection('users').doc(uid).get();
      final firestoreVersion = (doc.data()?['sessionVersion'] as int?) ?? 0;
      return localVersion >= firestoreVersion;
    } catch (_) {
      return true; // fail open — don't kick user out if check fails
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