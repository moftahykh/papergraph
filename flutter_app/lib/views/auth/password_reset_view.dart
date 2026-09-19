import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'login_view.dart';

class PasswordResetView extends StatefulWidget {
  final String actionCode;

  const PasswordResetView({super.key, required this.actionCode});

  @override
  State<PasswordResetView> createState() => _PasswordResetViewState();
}

class _PasswordResetViewState extends State<PasswordResetView> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _email;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _verifyActionCode();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _verifyActionCode() async {
    try {
      final email = await fb.FirebaseAuth.instance.verifyPasswordResetCode(
        widget.actionCode,
      );
      if (!mounted) return;
      setState(() {
        _email = email;
        _isLoading = false;
      });
    } on fb.FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _messageForError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'This password reset link is invalid or expired.';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      await fb.FirebaseAuth.instance.confirmPasswordReset(
        code: widget.actionCode,
        newPassword: _passwordController.text,
      );

      if (!mounted) return;
      await context.read<AuthProvider>().logout();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginView(
            successMessage:
                'Your password was updated. Sign in with your new password.',
          ),
        ),
        (route) => false,
      );
    } on fb.FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = _messageForError(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Could not update your password. Please try again.';
      });
    }
  }

  String _messageForError(fb.FirebaseAuthException error) {
    switch (error.code) {
      case 'expired-action-code':
      case 'invalid-action-code':
        return 'This password reset link is invalid or expired.';
      case 'weak-password':
        return 'Choose a stronger password with at least 6 characters.';
      case 'user-disabled':
        return 'This account is disabled. Contact support for help.';
      default:
        return 'Could not use this password reset link. Please request a new one.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset password'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: CircularProgressIndicator(),
                  ),
                )
              : _errorMessage != null
              ? _buildError(isDark)
              : _buildForm(isDark),
        ),
      ),
    );
  }

  Widget _buildForm(bool isDark) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.lock_reset_rounded,
            size: 46,
            color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
          ),
          const SizedBox(height: 20),
          Text(
            'Create a new password',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : AppTheme.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Choose a new password for ${_email ?? 'your account'}.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 30),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.length < 6) {
                return 'Use at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _errorBanner(),
          ],
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _isSaving ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: isDark ? Colors.white : const Color(0xFF18181B),
              foregroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
            ),
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Update password',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.link_off_rounded,
          size: 52,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
        const SizedBox(height: 20),
        Text(
          _errorMessage!,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginView()),
            (route) => false,
          ),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _errorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentRose.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accentRose.withAlpha(80)),
      ),
      child: Text(
        _errorMessage!,
        style: const TextStyle(
          color: AppTheme.accentRose,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
