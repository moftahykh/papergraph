import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../auth/forgot_password_view.dart';
import '../auth/login_view.dart';

class AccountView extends StatelessWidget {
  const AccountView({super.key});

  Future<void> _showSignOutDialog(
    BuildContext context,
    AuthProvider authProvider,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Sign out of PaperGraph?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: const Text(
          'You can sign back in anytime. Your account data stays protected on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await authProvider.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = context.watch<AuthProvider>().currentUser;
    final name = user?.name.trim().isNotEmpty == true
        ? user!.name.trim()
        : 'Researcher';
    final email = user?.email.trim().isNotEmpty == true
        ? user!.email.trim()
        : 'No email available';
    final initial = name.substring(0, 1).toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Account',
          style: AppTheme.brandTitleStyle(
            fontSize: 28,
            color: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.lightTextPrimary,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: isDark
                      ? AppTheme.darkSurface
                      : const Color(0xFFF2F2F7),
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: isDark ? Colors.white : AppTheme.primaryBlue,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _sectionLabel(context, 'ACCOUNT'),
          _group(
            context,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_reset_outlined),
                title: const Text(
                  'Reset password',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Send a secure reset link to your email'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: user == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ForgotPasswordView(initialEmail: user.email),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _sectionLabel(context, 'SESSION'),
          _group(
            context,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.logout_rounded,
                  color: AppTheme.accentRose,
                ),
                title: const Text(
                  'Sign out',
                  style: TextStyle(
                    color: AppTheme.accentRose,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.accentRose,
                ),
                onTap: user == null
                    ? null
                    : () => _showSignOutDialog(
                        context,
                        context.read<AuthProvider>(),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _group(BuildContext context, {required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 72,
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
          ],
        ],
      ),
    );
  }
}
