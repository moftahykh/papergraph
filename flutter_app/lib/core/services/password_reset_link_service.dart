import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Receives Firebase Auth password-reset links when the app is installed.
///
/// Firebase action links contain `mode=resetPassword` and an `oobCode`.
/// The service deliberately emits only valid reset codes and de-duplicates
/// repeated delivery when Android resumes an existing task.
class PasswordResetLinkService {
  PasswordResetLinkService._();

  static final PasswordResetLinkService instance = PasswordResetLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  String? _lastCode;
  bool _started = false;

  Future<void> start({required ValueChanged<String> onResetCode}) async {
    if (_started) return;
    _started = true;

    try {
      final initialUri = await _appLinks.getInitialLink();
      _emitIfResetLink(initialUri, onResetCode);
    } catch (error) {
      debugPrint('Password reset initial link error: $error');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _emitIfResetLink(uri, onResetCode),
      onError: (Object error) {
        debugPrint('Password reset link stream error: $error');
      },
    );
  }

  void _emitIfResetLink(Uri? uri, ValueChanged<String> onResetCode) {
    if (uri == null) return;

    final mode = uri.queryParameters['mode'];
    final code = uri.queryParameters['oobCode'];
    if (mode != 'resetPassword' || code == null || code.isEmpty) return;
    if (code == _lastCode) return;

    _lastCode = code;
    onResetCode(code);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
