import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/services/fcm_notification_service.dart';
import '../core/theme/app_theme.dart';
import '../cubits/graph/graph_cubit.dart';
import '../cubits/graph/graph_state.dart';
import '../cubits/library/library_cubit.dart';
import '../cubits/research_session/research_session_cubit.dart';
import '../cubits/research_session/research_session_state.dart';
import '../cubits/search/search_cubit.dart';
import '../cubits/search/search_state.dart';
import 'graph_view/connected_graph_view.dart';
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

  /// Allows descendants (like HomeView or notification toasts) to navigate
  /// directly to a specific tab and optionally select a subtab (e.g. Graphs in Library).
  static void switchTo(
    BuildContext context,
    int index, {
    int? librarySubIndex,
  }) {
    final state = context.findAncestorStateOfType<_MainNavigationViewState>();
    state?.switchToIndex(index, librarySubIndex: librarySubIndex);
  }

  @override
  State<MainNavigationView> createState() => _MainNavigationViewState();
}

class _MainNavigationViewState extends State<MainNavigationView> {
  int _currentIndex = 0;

  void switchToIndex(int index, {int? librarySubIndex}) {
    if (librarySubIndex != null) {
      FavoritesView.selectTab(librarySubIndex);
    }
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  final List<Widget> _screens = const [
    HomeView(),
    FavoritesView(),
    SettingsView(),
  ];

  @override
  void initState() {
    super.initState();
    FcmNotificationService.markAppShellReady();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ResearchSessionCubit>().syncSearch(
            context.read<SearchCubit>().state,
          );
      context.read<ResearchSessionCubit>().syncGraph(
            context.read<GraphCubit>().state,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MultiBlocListener(
      listeners: [
        BlocListener<SearchCubit, SearchState>(
          listener: (context, state) =>
              context.read<ResearchSessionCubit>().syncSearch(state),
        ),
        BlocListener<GraphCubit, GraphState>(
          listener: (context, state) =>
              context.read<ResearchSessionCubit>().syncGraph(state),
        ),
      ],
      child: AppLockGate(
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ResearchSessionDock(
                  visibleOnExplore: false,
                  onOpenResults: () => setState(() => _currentIndex = 0),
                ),
                const SizedBox(height: 8),
                Container(
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
                    labelBehavior:
                        NavigationDestinationLabelBehavior.alwaysShow,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResearchSessionDock extends StatelessWidget {
  final bool visibleOnExplore;
  final VoidCallback onOpenResults;

  const _ResearchSessionDock({
    required this.visibleOnExplore,
    required this.onOpenResults,
  });

  @override
  Widget build(BuildContext context) {
    final session = context.watch<ResearchSessionCubit>().state;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!session.hasSession) return const SizedBox.shrink();

    final currentIndex = context
        .findAncestorStateOfType<_MainNavigationViewState>()
        ?._currentIndex;
    if (!visibleOnExplore && currentIndex == 0) {
      return const SizedBox.shrink();
    }

    final type = _sessionCopy(session);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSession(context, session),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? const Color(0x22FFFFFF)
                  : const Color(0xFFE5E5EA),
              width: 0.75,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 50 : 12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _SessionProgressIcon(
                status: session.status,
                progress: session.progress,
                isDark: isDark,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      type.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.subtitle(session),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? const Color(0xFF8E8E93)
                            : const Color(0xFF636366),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                color: isDark
                    ? const Color(0xFFA1A1AA)
                    : const Color(0xFF8E8E93),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSession(BuildContext context, ResearchSessionState session) {
    if (session.status == ResearchSessionStatus.results ||
        session.status == ResearchSessionStatus.searching) {
      onOpenResults();
      return;
    }

    if (session.status == ResearchSessionStatus.error) {
      onOpenResults();
      return;
    }

    final snapshot = session.graphId == null
        ? null
        : context.read<LibraryCubit>().getCachedGraph(session.graphId!);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => snapshot == null
            ? const ConnectedGraphView()
            : ConnectedGraphView(initialSnapshot: snapshot),
      ),
    );
  }

  _SessionCopy _sessionCopy(ResearchSessionState session) {
    switch (session.status) {
      case ResearchSessionStatus.searching:
        return _SessionCopy(
          title: 'Searching literature',
          color: AppTheme.uiBlue,
          subtitle: (state) => state.query,
        );
      case ResearchSessionStatus.results:
        return _SessionCopy(
          title: 'Continue research',
          color: AppTheme.uiBlue,
          subtitle: (state) =>
              '${state.paperCount ?? 0} papers found · Tap to return to results',
        );
      case ResearchSessionStatus.building:
        return _SessionCopy(
          title: 'Building literature graph',
          color: AppTheme.uiBlue,
          subtitle: (state) =>
              '${(state.progress * 100).round()}% · ${state.query}',
        );
      case ResearchSessionStatus.ready:
        return _SessionCopy(
          title: 'Continue research',
          color: AppTheme.accentEmerald,
          subtitle: (state) =>
              '${state.paperCount ?? 0} connected papers · Tap to explore',
        );
      case ResearchSessionStatus.error:
        return _SessionCopy(
          title: 'Research needs attention',
          color: AppTheme.accentAmber,
          isError: true,
          subtitle: (state) => state.message ?? 'Tap to return to Explore',
        );
      case ResearchSessionStatus.idle:
        return _SessionCopy(
          title: '',
          color: AppTheme.uiBlue,
          subtitle: (_) => '',
        );
    }
  }
}

class _SessionCopy {
  final String title;
  final Color color;
  final bool isError;
  final String Function(ResearchSessionState) subtitle;

  const _SessionCopy({
    required this.title,
    required this.color,
    required this.subtitle,
    this.isError = false,
  });
}

class _SessionProgressIcon extends StatelessWidget {
  final ResearchSessionStatus status;
  final double progress;
  final bool isDark;

  const _SessionProgressIcon({
    required this.status,
    required this.progress,
    required this.isDark,
  });

  Color _indicatorColor() {
    switch (status) {
      case ResearchSessionStatus.ready:
        return const Color(0xFF10B981);
      case ResearchSessionStatus.error:
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF5269F4);
    }
  }

  IconData _iconData() {
    switch (status) {
      case ResearchSessionStatus.error:
        return Icons.warning_amber_rounded;
      case ResearchSessionStatus.ready:
        return Icons.account_tree_outlined;
      default:
        return Icons.search_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (status == ResearchSessionStatus.building) {
      return SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          value: progress == 0 ? null : progress,
          strokeWidth: 2.2,
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          backgroundColor: isDark
              ? const Color(0x18FFFFFF)
              : const Color(0xFFE5E5EA),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF242426)
                : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isDark
                  ? const Color(0x18FFFFFF)
                  : const Color(0xFFE5E5EA),
              width: 0.5,
            ),
          ),
          child: Icon(
            _iconData(),
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            size: 17,
          ),
        ),
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _indicatorColor(),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? const Color(0xFF161618) : Colors.white,
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
