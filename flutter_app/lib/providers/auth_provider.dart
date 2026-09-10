import 'package:flutter/material.dart';
import '../core/services/biometric_service.dart';
import '../core/services/hive_service.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _errorMessage;

  AuthProvider() {
    _loadUserSession();
  }

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void _loadUserSession() {
    final saved = HiveService.getSavedUser();
    if (saved != null) {
      _currentUser = UserModel.fromMap(saved);
      notifyListeners();
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      await Future.delayed(const Duration(milliseconds: 600)); // Smooth UX transition

      if (email.trim().isEmpty || password.trim().isEmpty) {
        _errorMessage = 'Please enter both email and password';
        _setLoading(false);
        return false;
      }

      if (password.length < 6) {
        _errorMessage = 'Password must be at least 6 characters';
        _setLoading(false);
        return false;
      }

      // Successful simulated/cloud authentication
      _currentUser = UserModel(
        id: 'usr_${email.hashCode.abs()}',
        name: email.split('@').first.toUpperCase(),
        email: email.trim(),
        institution: 'Computer Science & AI Institute',
        researchField: 'Artificial Intelligence & Systems',
        joinedDate: DateTime.now(),
      );

      await HiveService.saveUser(_currentUser!.toMap());
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Login failed: ${e.toString()}';
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

    try {
      await Future.delayed(const Duration(milliseconds: 600));

      if (name.isEmpty || email.isEmpty || password.isEmpty) {
        _errorMessage = 'Please fill in all required fields';
        _setLoading(false);
        return false;
      }

      _currentUser = UserModel(
        id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
        name: name.trim(),
        email: email.trim(),
        institution: institution.trim().isEmpty ? 'Academic Institution' : institution.trim(),
        researchField: researchField.trim().isEmpty ? 'General Computer Science' : researchField.trim(),
        joinedDate: DateTime.now(),
      );

      await HiveService.saveUser(_currentUser!.toMap());
      _setLoading(false);
      return true;
    } catch (e) {
      _errorMessage = 'Registration failed: ${e.toString()}';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final success = await BiometricService.authenticate(
        reason: 'Authenticate with Fingerprint/Face to access your research profile and vault',
      );

      if (success) {
        // If there's an existing saved user, log them in, or initialize academic researcher profile
        if (_currentUser == null) {
          final saved = HiveService.getSavedUser();
          if (saved != null) {
            _currentUser = UserModel.fromMap(saved);
          } else {
            _currentUser = UserModel(
              id: 'usr_biometric_default',
              name: 'Dr. Researcher',
              email: 'researcher@university.edu',
              institution: 'Graduate Research Lab',
              researchField: 'Deep Learning & Graphs',
              joinedDate: DateTime.now(),
            );
            await HiveService.saveUser(_currentUser!.toMap());
          }
        }
        _setLoading(false);
        return true;
      } else {
        _errorMessage = 'Biometric authentication was cancelled or not recognized';
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _errorMessage = 'Biometric error: ${e.toString()}';
      _setLoading(false);
      return false;
    }
  }

  Future<void> logout() async {
    _currentUser = null;
    await HiveService.clearUser();
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
