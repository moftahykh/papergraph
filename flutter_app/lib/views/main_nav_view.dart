import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../core/theme/app_theme.dart';
import '../cubits/library/library_cubit.dart';
import '../cubits/library/library_state.dart';
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
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (context, libraryState) {
        final int itemCount = libraryState is LibraryLoaded
            ? libraryState.savedPapers.length + libraryState.cachedGraphs.length
            : 0;

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
                  isLabelVisible: itemCount > 0,
                  label: Text('$itemCount'),
                  backgroundColor: AppTheme.accentEmerald,
                  child: const Icon(Icons.bookmark_outline_rounded),
                ),
                activeIcon: Badge(
                  isLabelVisible: itemCount > 0,
                  label: Text('$itemCount'),
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
      },
    );
  }
}
