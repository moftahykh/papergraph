import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../providers/favorites_provider.dart';
import 'favorites/favorites_view.dart';
import 'home/home_view.dart';
import 'settings/settings_view.dart';

class MainNavigationView extends StatefulWidget {
  const MainNavigationView({super.key});

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
    final favoritesProvider = Provider.of<FavoritesProvider>(context);
    final favCount = favoritesProvider.count;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            activeIcon: Icon(Icons.explore_rounded),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: favCount > 0,
              label: Text('$favCount'),
              backgroundColor: AppTheme.accentEmerald,
              child: const Icon(Icons.bookmark_outline_rounded),
            ),
            activeIcon: Badge(
              isLabelVisible: favCount > 0,
              label: Text('$favCount'),
              backgroundColor: AppTheme.accentEmerald,
              child: const Icon(Icons.bookmark_rounded),
            ),
            label: 'Library',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
