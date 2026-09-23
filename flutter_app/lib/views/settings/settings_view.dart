import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/services/biometric_service.dart';
import '../../core/services/fcm_notification_service.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/theme/theme_cubit.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_view.dart';
import '../auth/register_view.dart';
import '../auth/widgets/auth_gate_sheet.dart';
import '../favorites/favorites_view.dart';
import 'account_view.dart';

const _appVersion = '2.0.0';
const _appVersionLabel = '2.0.0 (Build 2)';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late bool _biometricsEnabled;
  bool _biometricsAvailable = false;
  bool _biometricsSupported = false;
  bool _researchNotificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    _biometricsEnabled = HiveService.isBiometricsEnabled();
    _researchNotificationsEnabled = FcmNotificationService.isEnabled;
    _loadBiometricAvailability();
  }

  Future<void> _loadBiometricAvailability() async {
    final availability = await BiometricService.getAvailability();
    final available = availability == BiometricAvailability.available;
    final supported = availability != BiometricAvailability.notSupported;
    if (!mounted) return;
    if (!available && _biometricsEnabled) {
      await HiveService.setBiometricsEnabled(false);
    }
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = available;
      _biometricsSupported = supported;
      if (!available) _biometricsEnabled = false;
    });
  }

  Future<void> _handleResearchNotificationsToggle(bool value) async {
    if (value) {
      final enabled = await FcmNotificationService.enable();
      if (!mounted) return;
      if (enabled) {
        setState(() => _researchNotificationsEnabled = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Research update notifications enabled'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _researchNotificationsEnabled = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notifications were not enabled. Check device permissions and sign in.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await FcmNotificationService.disable();
    if (!mounted) return;
    setState(() => _researchNotificationsEnabled = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Research update notifications disabled'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleBiometricToggle(bool value) async {
    if (!_biometricsAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Biometric unlock is unavailable. Set up Face ID or fingerprint in device settings.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final reason = value
        ? 'Authenticate to enable PaperGraph biometric unlock'
        : 'Authenticate to disable PaperGraph biometric unlock';

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
        title: const Text(
          'Remove saved graph copies?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: const Text(
          'This removes all saved graph copies from this device, including graphs in your Library. Saved papers and personal notes will not be affected. You can create the graphs again when you are online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final count = await HiveService.clearCachedGraphsForActiveUser();
        if (mounted) {
          context.read<LibraryCubit>().loadLibrary();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$count offline graph${count == 1 ? '' : 's'} removed',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove offline graph data'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);
    final libraryState = context.watch<LibraryCubit>().state;
    final int cachedGraphsCount = libraryState is LibraryLoaded
        ? libraryState.cachedGraphs.length
        : 0;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        title: Text(
          'Settings',
          style: AppTheme.brandTitleStyle(
            fontSize: 29,
            color: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Profile Header
          _buildProfileSection(isDark, authProvider),
          const SizedBox(height: 24),

          // 1. Appearance
          _buildSectionHeader(context, 'Appearance'),
          _buildGroupContainer(
            context: context,
            children: [
              SwitchListTile(
                secondary: Icon(
                  isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                  color: isDark
                      ? AppTheme.primaryLightBlue
                      : AppTheme.primaryBlue,
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
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                value: isDark,
                onChanged: (_) => context.read<ThemeCubit>().toggleTheme(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. Security & Privacy
          _buildSectionHeader(context, 'Security & Privacy'),
          _buildGroupContainer(
            context: context,
            children: [
              SwitchListTile(
                secondary: Icon(
                  Icons.fingerprint_rounded,
                  color: _biometricsAvailable
                      ? (isDark
                            ? AppTheme.primaryLightBlue
                            : AppTheme.primaryBlue)
                      : (isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary),
                  size: 22,
                ),
                title: Text(
                  'Unlock with biometrics',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    color: _biometricsAvailable
                        ? null
                        : (isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary),
                  ),
                ),
                subtitle: Text(
                  _biometricsAvailable
                      ? 'Use Face ID, fingerprint, or device passcode'
                      : _biometricsSupported
                      ? 'Set up Face ID or fingerprint in device settings'
                      : 'Biometric unlock is not supported on this device',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                value: _biometricsEnabled,
                onChanged: _biometricsAvailable ? _handleBiometricToggle : null,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Research updates
          _buildSectionHeader(context, 'Research updates'),
          _buildGroupContainer(
            context: context,
            children: [
              SwitchListTile(
                secondary: Icon(
                  Icons.auto_awesome_outlined,
                  color: isDark
                      ? AppTheme.primaryLightBlue
                      : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Research update notifications',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  authProvider.isAuthenticated
                      ? 'Get notified when a monitored graph has new relevant papers'
                      : 'Sign in to enable research update notifications',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                value: _researchNotificationsEnabled,
                onChanged: authProvider.isAuthenticated
                    ? _handleResearchNotificationsToggle
                    : (_) => AuthGateBottomSheet.show(
                        context,
                        reason: AuthGateReason.researchUpdates,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 4. App data
          _buildSectionHeader(context, 'App data'),
          _buildGroupContainer(
            context: context,
            children: [
              ListTile(
                leading: Icon(
                  Icons.download_done_rounded,
                  color: isDark
                      ? AppTheme.primaryLightBlue
                      : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Offline storage',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  '$cachedGraphsCount graph${cachedGraphsCount == 1 ? '' : 's'} available without internet',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (cachedGraphsCount > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF242426)
                              : const Color(0xFFF2F2F7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark
                                ? const Color(0x18FFFFFF)
                                : const Color(0xFFE5E5EA),
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          '$cachedGraphsCount',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ],
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FavoritesView(
                      mode: FavoritesViewMode.savedGraphs,
                    ),
                  ),
                ),
              ),
              _buildGroupDivider(context),
              ListTile(
                leading: Icon(
                  Icons.delete_sweep_outlined,
                  color: cachedGraphsCount > 0
                      ? AppTheme.accentRose
                      : (isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary),
                  size: 22,
                ),
                title: Text(
                  'Clear cached data',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    color: cachedGraphsCount > 0
                        ? null
                        : (isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary),
                  ),
                ),
                subtitle: Text(
                  cachedGraphsCount > 0
                      ? 'Remove saved graph copies; papers and notes stay safe'
                      : 'No offline graph copies to remove',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                onTap: cachedGraphsCount > 0 ? _showClearCacheDialog : null,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 5. Permissions
          _buildSectionHeader(context, 'Permissions'),
          _buildGroupContainer(
            context: context,
            children: [
              ListTile(
                leading: Icon(
                  Icons.security_outlined,
                  color: isDark
                      ? AppTheme.primaryLightBlue
                      : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'System permissions',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                subtitle: Text(
                  'Notifications and device access',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
                onTap: () => openAppSettings(),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 6. About & legal
          _buildSectionHeader(context, 'About & legal'),
          _buildGroupContainer(
            context: context,
            children: [
              ListTile(
                leading: Icon(
                  Icons.info_outline_rounded,
                  color: isDark
                      ? AppTheme.primaryLightBlue
                      : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Version',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                trailing: Text(
                  _appVersionLabel,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
              _buildGroupDivider(context),
              ListTile(
                leading: Icon(
                  Icons.description_outlined,
                  color: isDark
                      ? AppTheme.primaryLightBlue
                      : AppTheme.primaryBlue,
                  size: 22,
                ),
                title: const Text(
                  'Open Source Licenses',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'PaperGraph',
                  applicationVersion: _appVersion,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          const SizedBox(height: 110), // Clearance for floating navigation bar
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
                    color: isDark
                        ? AppTheme.darkSurface
                        : const Color(0xFFE8EEF5),
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.primaryBlue,
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
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sign in to sync graphs across devices',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
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
                      backgroundColor: isDark
                          ? AppTheme.primaryLightBlue
                          : AppTheme.primaryBlue,
                      foregroundColor: isDark ? AppTheme.darkBg : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Sign In',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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
                      foregroundColor: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                      side: BorderSide(
                        color: isDark
                            ? AppTheme.darkBorder
                            : AppTheme.lightBorder,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Register',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 6),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const AccountView())),
        child: Row(
          children: [
            // Academic verified avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? const Color(0xFF202026)
                    : const Color(0xFFF2F2F7),
                border: Border.all(
                  color: isDark
                      ? const Color(0x33FFFFFF)
                      : const Color(0x24000000),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'R',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.primaryBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ],
        ),
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
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
        child: Column(children: children),
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
