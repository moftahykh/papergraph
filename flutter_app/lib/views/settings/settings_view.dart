import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/services/biometric_service.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/theme/theme_cubit.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_view.dart';
import '../auth/register_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late bool _biometricsEnabled;

  @override
  void initState() {
    super.initState();
    _biometricsEnabled = HiveService.isBiometricsEnabled();
  }

  Future<void> _handleBiometricToggle(bool value) async {
    final reason = value
        ? 'Authenticate to enable biometric app lock'
        : 'Authenticate to disable biometric app lock';

    final authenticated = await BiometricService.authenticate(reason: reason);
    if (!mounted) return;

    if (authenticated) {
      await HiveService.setBiometricsEnabled(value);
      if (!mounted) return;
      setState(() {
        _biometricsEnabled = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? 'Biometric lock enabled' : 'Biometric lock disabled',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      // Revert switch to reflect reality
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric verification cancelled or failed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showClearCacheDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Clear Literature Cache',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This will remove locally stored graphs and cached data. Your saved favorites and personal notes will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentRose,
            ),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final count = await HiveService.cleanExpiredGraphs();
        // Also purge graph snapshots safely
        final all = HiveService.getCachedGraphs();
        for (final g in all) {
          await HiveService.removeCachedGraph(g.graphId);
        }
        if (mounted) {
          context.read<LibraryCubit>().loadLibrary();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Local cache cleared ($count entries removed)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear local cache'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showSignOutDialog(AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Sign Out',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to sign out of your academic session?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accentRose,
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await authProvider.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginView()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);
    final libraryState = context.watch<LibraryCubit>().state;
    final int cachedGraphsCount = libraryState is LibraryLoaded ? libraryState.cachedGraphs.length : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings & Profile',
          style: GoogleFonts.playfairDisplay(
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Profile Header
          _buildProfileSection(isDark, authProvider),
          const SizedBox(height: 28),

          // Preferences
          _buildSectionHeader(context, 'Preferences'),
          _buildGroupContainer(
            context: context,
            children: [
              SwitchListTile(
                secondary: Icon(
                  isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Dark Mode',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  isDark ? 'Dark Lab theme active' : 'Paper & Ink theme active',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                value: isDark,
                onChanged: (_) => context.read<ThemeCubit>().toggleTheme(),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Security & Privacy
          _buildSectionHeader(context, 'Security & Privacy'),
          _buildGroupContainer(
            context: context,
            children: [
              SwitchListTile(
                secondary: Icon(
                  Icons.fingerprint_rounded,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Biometric App Lock',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Require Face ID / Fingerprint on launch',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                value: _biometricsEnabled,
                onChanged: _handleBiometricToggle,
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Data & Storage
          _buildSectionHeader(context, 'Data & Storage'),
          _buildGroupContainer(
            context: context,
            children: [
              ListTile(
                leading: Icon(
                  Icons.hub_outlined,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Offline Literature Cache',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  '$cachedGraphsCount graph snapshot${cachedGraphsCount == 1 ? '' : 's'} stored locally',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                trailing: TextButton(
                  onPressed: cachedGraphsCount > 0 ? _showClearCacheDialog : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentRose,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              _buildGroupDivider(context),
              ListTile(
                leading: Icon(
                  Icons.security_outlined,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'System Permissions',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Storage, notifications & device access',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => openAppSettings(),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // About & Legal
          _buildSectionHeader(context, 'About & Resources'),
          _buildGroupContainer(
            context: context,
            children: [
              ListTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Version',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                trailing: Text(
                  '1.0.0 (Build 1)',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
              _buildGroupDivider(context),
              ListTile(
                leading: Icon(
                  Icons.description_outlined,
                  color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Open Source Licenses',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'PaperGraph',
                  applicationVersion: '1.0.0',
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Sign Out Action (for Authenticated Users)
          if (authProvider.isAuthenticated) ...[
            _buildGroupContainer(
              context: context,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: AppTheme.accentRose,
                    size: 22,
                  ),
                  title: const Text(
                    'Sign Out',
                    style: TextStyle(
                      color: AppTheme.accentRose,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  onTap: () => _showSignOutDialog(authProvider),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileSection(bool isDark, AuthProvider authProvider) {
    final user = authProvider.currentUser;
    final isAuthenticated = authProvider.isAuthenticated && user != null;

    if (!isAuthenticated) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE8EEF5),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.primaryBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Guest Session',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sign in to sync graphs across devices',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginView()),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                      foregroundColor: isDark ? const Color(0xFF062631) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RegisterView()),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                      side: BorderSide(
                        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Register',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final name = (user.name.isNotEmpty) ? user.name : 'Researcher';
    final email = user.email;
    final institution = (user.institution.isNotEmpty) ? user.institution : 'Academic Researcher';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          // Flat solid monogram avatar (Zero gradients, zero neon glow)
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF22304F) : AppTheme.primaryBlue,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'R',
                style: GoogleFonts.playfairDisplay(
                  color: isDark ? AppTheme.primaryLightBlue : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.verified_rounded,
                      color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                      size: 16,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.primaryLightBlue.withAlpha(25)
                        : AppTheme.primaryBlue.withAlpha(18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    institution,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _buildGroupContainer({
    required BuildContext context,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildGroupDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 52,
      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder.withAlpha(120),
    );
  }
}
