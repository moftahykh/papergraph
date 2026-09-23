import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

enum BiometricAvailability {
  available,
  notEnrolled,
  notSupported,
}

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<BiometricAvailability> getAvailability() async {
    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final deviceSupported = await _auth.isDeviceSupported();
      if (!deviceSupported || !canCheckBiometrics) {
        return BiometricAvailability.notSupported;
      }

      final enrolledBiometrics = await _auth.getAvailableBiometrics();
      return enrolledBiometrics.isEmpty
          ? BiometricAvailability.notEnrolled
          : BiometricAvailability.available;
    } on PlatformException {
      return BiometricAvailability.notSupported;
    }
  }

  static Future<bool> isBiometricAvailable() async {
    return await getAvailability() == BiometricAvailability.available;
  }

  static Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return <BiometricType>[];
    }
  }

  static Future<bool> authenticate({String? reason}) async {
    try {
      final bool isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        return false;
      }

      return await _auth.authenticate(
        localizedReason:
            reason ??
            'Please authenticate with your fingerprint or face to access PaperGraph',
        options: const AuthenticationOptions(
          stickyAuth: true,
          // Keep the device passcode/PIN fallback so users cannot be locked
          // out after a biometric enrollment change or temporary sensor issue.
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }
}
