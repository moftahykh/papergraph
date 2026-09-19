import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/biometric_service.dart';
import '../../core/services/hive_service.dart';
import '../../providers/auth_provider.dart';

/// Covers the application and requires biometric authentication when app lock
/// is enabled. It checks on first launch and whenever the app returns from the
/// background.
class AppLockGate extends StatefulWidget {
  final Widget child;
  final bool lockOnStart;

  const AppLockGate({super.key, required this.child, this.lockOnStart = false});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

/// Centralized re-authentication policy.
///
/// Losing input focus is not enough to lock the app: Android reports
/// [AppLifecycleState.inactive] when the notification shade, app switcher, or
/// a system dialog is visible. Re-authentication is required only after the
/// app has actually been hidden for at least this timeout.
class AppLockPolicy {
  static const Duration backgroundTimeout = Duration(minutes: 5);

  static bool shouldLockAfter({
    required DateTime backgroundedAt,
    required DateTime resumedAt,
  }) {
    return resumedAt.difference(backgroundedAt) >= backgroundTimeout;
  }
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _isLocked = false;
  bool _isAuthenticating = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.lockOnStart) {
      _isLocked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lockIfRequired());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android uses inactive when the notification shade, app switcher, or a
    // system dialog takes focus. Ignore it: the app is still visible.
    if (state == AppLifecycleState.inactive) {
      return;
    }

    // hidden/paused means the app is no longer visible. Do not start a new
    // background session for lifecycle changes caused by the biometric sheet.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_isAuthenticating) return;
      _backgroundedAt ??= DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (_isAuthenticating) {
        _backgroundedAt = null;
        return;
      }

      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          AppLockPolicy.shouldLockAfter(
            backgroundedAt: backgroundedAt,
            resumedAt: DateTime.now(),
          )) {
        _lockIfRequired();
      }
    }
  }

  Future<void> _lockIfRequired() async {
    if (!mounted || _isAuthenticating) return;

    final isAuthenticated = Provider.of<AuthProvider>(
      context,
      listen: false,
    ).isAuthenticated;
    if (!isAuthenticated || !HiveService.isBiometricsEnabled()) {
      if (_isLocked) setState(() => _isLocked = false);
      return;
    }

    final availableBiometrics = await BiometricService.getAvailableBiometrics();
    if (!mounted) return;
    if (availableBiometrics.isEmpty) {
      // Avoid permanently locking users out if enrolled biometrics are
      // removed in system settings after app lock was enabled.
      await HiveService.setBiometricsEnabled(false);
      if (mounted && _isLocked) setState(() => _isLocked = false);
      return;
    }

    setState(() => _isLocked = true);
    await _authenticate();
  }

  Future<void> _authenticate() async {
    if (!mounted || _isAuthenticating) return;
    setState(() => _isAuthenticating = true);

    final authenticated = await BiometricService.authenticate(
      reason: 'Authenticate to unlock PaperGraph',
    );

    if (!mounted) return;
    setState(() {
      _isAuthenticating = false;
      _backgroundedAt = null;
      if (authenticated) {
        _isLocked = false;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_isLocked)
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.fingerprint_rounded,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'PaperGraph is locked',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Use Face ID, fingerprint, or your device passcode to continue.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isAuthenticating ? null : _authenticate,
                        icon: _isAuthenticating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_open_rounded),
                        label: Text(
                          _isAuthenticating ? 'Authenticating…' : 'Unlock',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
