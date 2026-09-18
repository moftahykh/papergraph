import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../core/services/biometric_service.dart';
import '../core/services/fcm_notification_service.dart';
import '../core/services/hive_service.dart';
import '../models/user_model.dart';

/// Firebase-backed authentication provider.
///
/// Keeps the exact public interface the views already use
/// (login / register / authenticateWithBiometrics / logout), but backed by
/// real Firebase Auth email+password authentication instead of the previous
/// local simulation.
///
/// Safety notes:
/// - No Firebase call happens unless Firebase is initialized, so unit/widget
///   tests and pre-`flutterfire configure` runs keep working.
/// - Profile extras (institution, researchField) are stored locally in Hive
///   alongside the cached user; Firebase Auth only owns identity.
class AuthProvider extends ChangeNotifier {
  static final List<VoidCallback> _authListeners = [];

  /// Registers a global listener triggered whenever authentication state changes
  /// (e.g. login, logout, user switch) to synchronize offline caches & providers.
  static void addAuthListener(VoidCallback listener) {
    if (!_authListeners.contains(listener)) {
      _authListeners.add(listener);
    }
  }

  /// Removes a registered auth state listener.
  static void removeAuthListener(VoidCallback listener) {
    _authListeners.remove(listener);
  }

  static void _notifyAuthChanged() {
    for (final listener in List<VoidCallback>.from(_authListeners)) {
      try {
        listener();
      } catch (e) {
        debugPrint('AuthProvider listener error: $e');
      }
    }
  }

  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<fb.User?>? _authSub;

  AuthProvider() {
    if (_firebaseReady) {
      final firebaseUser = fb.FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        HiveService.setActiveUserScope(firebaseUser.uid);
        _adoptFirebaseUser(firebaseUser);
      } else {
        HiveService.setActiveUserScope('anonymous');
      }

      // Keep the local profile in sync with the persisted Firebase session.
      _authSub = fb.FirebaseAuth.instance.authStateChanges().listen((
        fb.User? user,
      ) {
        if (user != null) {
          _adoptFirebaseUser(user);
        } else {
          _handleFirebaseSignedOut();
        }
      });
    } else {
      // Used only as a graceful fallback in tests or builds where Firebase
      // could not be initialized. Production authentication still requires
      // a live Firebase session.
      _loadUserSession();
    }
  }

  bool get _firebaseReady => Firebase.apps.isNotEmpty;

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _loadUserSession() {
    final saved = HiveService.getSavedUser();
    if (saved != null) {
      _currentUser = UserModel.fromMap(saved);
      HiveService.setActiveUserScope(_currentUser!.id);
      notifyListeners();
    } else {
      HiveService.setActiveUserScope('anonymous');
    }
  }

  void _handleFirebaseSignedOut() {
    _currentUser = null;
    // A passive Firebase sign-out must hide, not delete, the last local
    // profile. Keeping saved_user allows the same account's offline library
    // to reappear after re-authentication, while the explicit anonymous scope
    // prevents a guest session from reading it.
    HiveService.setActiveUserScope('anonymous');
    _notifyAuthChanged();
    notifyListeners();
  }

  /// Builds/updates the local [UserModel] from a Firebase user, merging any
  /// locally cached profile extras (institution, researchField).
  Future<void> _adoptFirebaseUser(fb.User user) async {
    final previousScope = HiveService.activeUserId;
    HiveService.setActiveUserScope(user.uid);
    final saved = HiveService.getSavedUser();
    final savedModel = saved != null ? UserModel.fromMap(saved) : null;
    final hasLocalProfile = savedModel != null && savedModel.id == user.uid;
    final accountChanged = savedModel?.id != user.uid;
    final scopeChanged = previousScope != user.uid;

    _currentUser = UserModel(
      id: user.uid,
      name: (user.displayName != null && user.displayName!.isNotEmpty)
          ? user.displayName!
          : hasLocalProfile
          ? savedModel.name
          : (user.email?.split('@').first ?? 'Researcher'),
      email: user.email ?? '',
      institution: hasLocalProfile ? savedModel.institution : '',
      researchField: hasLocalProfile ? savedModel.researchField : '',
      joinedDate: user.metadata.creationTime ?? DateTime.now(),
    );
    await HiveService.saveUser(_currentUser!.toMap());
    await HiveService.migrateLegacyDataForUser(user.uid);
    if (accountChanged || scopeChanged) {
      _notifyAuthChanged();
    }
    unawaited(FcmNotificationService.syncRegistration());
    notifyListeners();
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    _errorMessage = null;

    if (email.trim().isEmpty || password.isEmpty) {
      _errorMessage = 'Please enter both email and password';
      _setLoading(false);
      return false;
    }
    if (!_firebaseReady) {
      _errorMessage =
          'Firebase is not configured yet. Run `flutterfire configure` first.';
      _setLoading(false);
      return false;
    }

    try {
      final cred = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (cred.user != null) {
        await _adoptFirebaseUser(cred.user!);
      }
      _setLoading(false);
      return true;
    } on fb.FirebaseAuthException catch (e) {
      _errorMessage = _mapAuthError(e);
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Login failed: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String institution,
    required String researchField,
    required String password,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    if (name.trim().isEmpty || email.trim().isEmpty || password.isEmpty) {
      _errorMessage = 'Please fill in all required fields';
      _setLoading(false);
      return false;
    }
    if (password.length < 6) {
      _errorMessage = 'Password must be at least 6 characters';
      _setLoading(false);
      return false;
    }
    if (!_firebaseReady) {
      _errorMessage =
          'Firebase is not configured yet. Run `flutterfire configure` first.';
      _setLoading(false);
      return false;
    }

    try {
      final cred = await fb.FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
      await cred.user?.updateDisplayName(name.trim());

      _currentUser = UserModel(
        id: cred.user!.uid,
        name: name.trim(),
        email: email.trim(),
        institution: institution.trim().isEmpty
            ? 'Academic Institution'
            : institution.trim(),
        researchField: researchField.trim().isEmpty
            ? 'General Computer Science'
            : researchField.trim(),
        joinedDate: cred.user!.metadata.creationTime ?? DateTime.now(),
      );
      await HiveService.saveUser(_currentUser!.toMap());
      await HiveService.migrateLegacyDataForUser(cred.user!.uid);
      _notifyAuthChanged();
      _setLoading(false);
      notifyListeners();
      return true;
    } on fb.FirebaseAuthException catch (e) {
      _errorMessage = _mapAuthError(e);
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Registration failed: $e';
      _setLoading(false);
      return false;
    }
  }

  /// Biometric quick-unlock: requires an existing account (live Firebase
  /// session or a locally cached one), then gates it behind biometrics.
  Future<bool> authenticateWithBiometrics() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final fbUser = _firebaseReady
          ? fb.FirebaseAuth.instance.currentUser
          : null;
      if (fbUser == null) {
        _errorMessage =
            'Your session has expired. Please sign in with email first.';
        _setLoading(false);
        return false;
      }

      final isBioSupported = await BiometricService.isBiometricAvailable();
      if (!isBioSupported) {
        _errorMessage =
            'Biometric authentication is not supported or not set up on this device. Please use your email and password.';
        _setLoading(false);
        return false;
      }

      final success = await BiometricService.authenticate(
        reason:
            'Authenticate with Fingerprint/Face to access your research profile and vault',
      );

      if (success) {
        await _adoptFirebaseUser(fbUser);
        _setLoading(false);
        return true;
      }

      _errorMessage =
          'Biometric authentication was cancelled or not recognized';
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Biometric error: $e';
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    await FcmNotificationService.unregisterCurrentToken();
    if (_firebaseReady) {
      try {
        await fb.FirebaseAuth.instance.signOut();
      } catch (_) {}
    }
    _currentUser = null;
    await HiveService.clearUser();
    _notifyAuthChanged();
    notifyListeners();
  }

  /// Checks if an account already exists for the given email before sending OTP.
  Future<bool> isEmailRegistered(String email) async {
    if (!_firebaseReady) return false;
    final cleanEmail = email.trim().toLowerCase();
    try {
      // ignore: deprecated_member_use
      final methods = await fb.FirebaseAuth.instance.fetchSignInMethodsForEmail(
        cleanEmail,
      );
      return methods.isNotEmpty;
    } on fb.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Sends a password reset email via Firebase Auth.
  Future<bool> sendPasswordReset(String email) async {
    _setLoading(true);
    _errorMessage = null;

    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty) {
      _errorMessage = 'Please enter your email address';
      _setLoading(false);
      return false;
    }
    if (!_firebaseReady) {
      _errorMessage = 'Firebase is not initialized.';
      _setLoading(false);
      return false;
    }

    try {
      await fb.FirebaseAuth.instance.sendPasswordResetEmail(email: cleanEmail);
      _setLoading(false);
      return true;
    } on fb.FirebaseAuthException catch (e) {
      _errorMessage = _mapAuthError(e);
      _setLoading(false);
      return false;
    } catch (e) {
      _errorMessage = 'Could not send reset email: $e';
      _setLoading(false);
      return false;
    }
  }

  String _mapAuthError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found for this email. Try registering first.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'This email is already registered. Try logging in.';
      case 'weak-password':
        return 'Password is too weak (at least 6 characters).';
      case 'invalid-email':
        return 'Invalid email address format.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return e.message ?? 'Authentication error (${e.code})';
    }
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
