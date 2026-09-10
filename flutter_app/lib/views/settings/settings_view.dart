import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../auth/login_view.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  Map<String, bool> _permissionStatus = {
    'Storage': false,
    'Notifications': false,
  };

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final status = await PermissionService.checkAllPermissions();
    if (mounted) {
      setState(() {
        _permissionStatus = status;
      });
    }
  }

  void _requestStorage() async {
    final granted = await PermissionService.requestStoragePermission();
    _refreshPermissions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted ? 'Storage permission granted!' : 'Storage permission denied or restricted'),
        backgroundColor: granted ? AppTheme.accentEmerald : AppTheme.accentRose,
      ),
    );
  }

  void _requestNotifications() async {
    final granted = await PermissionService.requestNotificationPermission();
    _refreshPermissions();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(granted ? 'Notification permission granted!' : 'Notification permission denied'),
        backgroundColor: granted ? AppTheme.accentEmerald : AppTheme.accentRose,
      ),
    );
  }

  void _testBiometrics() async {
    final success = await BiometricService.authenticate(
      reason: 'Biometric Test: Verify identity for PaperGraph researcher vault',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? 'Biometric verification successful!' : 'Biometric verification failed or cancelled',
        ),
        backgroundColor: success ? AppTheme.accentEmerald : AppTheme.accentRose,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Researcher Profile Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF1E293B), const Color(0xFF131B2E)]
                      : [Colors.white, const Color(0xFFF1F5F9)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [AppTheme.primaryBlue, AppTheme.accentCyan],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryLightBlue.withAlpha(80),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'Dr. Academic Researcher',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? 'researcher@university.edu',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.institution ?? 'University of Science and Technology',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.primaryLightBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section: Appearance & Theme
            _buildSectionHeader('Appearance & Theme (متطلب الثيم)'),
            const SizedBox(height: 10),
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  themeProvider.isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: themeProvider.isDark ? Colors.amber : AppTheme.primaryBlue,
                ),
                title: const Text('Dark Mode (الوضع الليلي)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  themeProvider.isDark ? 'Academic Obsidian Theme' : 'Clean Paper White Theme',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                value: themeProvider.isDark,
                onChanged: (_) => themeProvider.toggleTheme(),
              ),
            ),
            const SizedBox(height: 24),

            // Section: Biometrics Authentication
            _buildSectionHeader('Biometrics Security (متطلب البصمة)'),
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCyan.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fingerprint_rounded, color: AppTheme.accentCyan),
                ),
                title: const Text('Biometric Authentication', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Use Fingerprint / Face ID for quick login and vault access'),
                trailing: ElevatedButton(
                  onPressed: _testBiometrics,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentCyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  child: const Text('Test Fingerprint', style: TextStyle(fontSize: 11.5)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Section: Permissions (Doctor requirement)
            _buildSectionHeader('System Permissions (متطلب الأذونات)'),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.folder_shared_rounded, color: AppTheme.primaryLightBlue),
                    title: const Text('Storage Permission (حفظ الأبحاث)'),
                    subtitle: const Text('Required to download PDF papers and export bibliographies'),
                    trailing: _buildPermissionBadge(
                      isGranted: _permissionStatus['Storage'] ?? false,
                      onRequest: _requestStorage,
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.notifications_active_rounded, color: AppTheme.accentAmber),
                    title: const Text('Notification Permission (التنبيهات)'),
                    subtitle: const Text('Receive alerts for new derivative research and citation milestones'),
                    trailing: _buildPermissionBadge(
                      isGranted: _permissionStatus['Notifications'] ?? false,
                      onRequest: _requestNotifications,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section: About Project
            _buildSectionHeader('About PaperGraph Project'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.school_rounded, color: AppTheme.primaryLightBlue),
                        SizedBox(width: 8),
                        Text(
                          'Inspired by Connected Papers',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PaperGraph is a mobile application engineered with Flutter, Hive, and Provider. It presents an innovative visual relationship graph for exploring scientific literature with offline local database synchronization and biometric authentication.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Logout Button
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  await authProvider.logout();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginView()),
                    (route) => false,
                  );
                },
                icon: const Icon(Icons.logout_rounded, color: AppTheme.accentRose),
                label: const Text(
                  'Log Out of Session',
                  style: TextStyle(color: AppTheme.accentRose, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildPermissionBadge({
    required bool isGranted,
    required VoidCallback onRequest,
  }) {
    if (isGranted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accentEmerald.withAlpha(30),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.accentEmerald, size: 14),
            SizedBox(width: 4),
            Text(
              'Granted',
              style: TextStyle(
                color: AppTheme.accentEmerald,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else {
      return TextButton(
        onPressed: onRequest,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          backgroundColor: AppTheme.primaryBlue.withAlpha(20),
        ),
        child: const Text('Allow', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      );
    }
  }
}
