import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'favorites/favorites_view.dart';
import 'home/home_view.dart';
import 'settings/settings_view.dart';
import 'widgets/app_lock_gate.dart';

class MainNavigationView extends StatefulWidget {
  final bool requireInitialUnlock;

  const MainNavigationView({
    super.key,
    this.requireInitialUnlock = false,
  });

  @override
  State<MainNavigationView> createState() => _MainNavigationViewState();
}

class _MainNavigationViewState extends State<MainNavigationView> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeView(),
    FavoritesView(),
    SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppLockGate(
      lockOnStart: widget.requireInitialUnlock,
      child: Scaffold(
        // Reserve layout space for the floating navigation container so
        // scrollable page content never renders underneath it.
        extendBody: false,
        body: IndexedStack(
          index: _currentIndex,
          children: _screens,
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 70 : 18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: NavigationBar(
              height: 68,
              elevation: 0,
              backgroundColor: Colors.transparent,
              indicatorColor: isDark
                  ? AppTheme.primaryLightBlue.withAlpha(30)
                  : AppTheme.primaryBlue.withAlpha(20),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                if (index != _currentIndex) {
                  setState(() => _currentIndex = index);
                }
              },
              destinations: [
                NavigationDestination(
                  icon: Icon(
                    Icons.explore_outlined,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                  selectedIcon: Icon(
                    Icons.explore_rounded,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                  label: 'Explore',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.bookmarks_outlined,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                  selectedIcon: Icon(
                    Icons.bookmarks_rounded,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.settings_outlined,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                  selectedIcon: Icon(
                    Icons.settings_rounded,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
