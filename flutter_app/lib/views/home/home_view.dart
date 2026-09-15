import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:provider/provider.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../cubits/search/search_cubit.dart';
import '../../cubits/search/search_state.dart';
import '../../cubits/theme/theme_cubit.dart';
import '../../models/api_schemas.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import '../../providers/auth_provider.dart';
import '../auth/widgets/auth_gate_sheet.dart';
import '../graph_view/connected_graph_view.dart';
import '../widgets/notifications_sheet.dart';

/// Search-first home (the Connected Papers model).
///
/// No hardcoded paper feed: the screen is a doorway into graph generation —
/// a prominent search field backed by the real backend search, plus the
/// user's recent cached graphs for one-tap re-opening.
class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _checkGuestSearchLimit() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated) {
      return true; // Authenticated members have unlimited search
    }

    final count = HiveService.getGuestSearchCount();
    if (count >= 1) {
      AuthGateBottomSheet.show(context);
      return false;
    }

    HiveService.incrementGuestSearchCount();
    setState(() {}); // refresh banner state
    return true;
  }

  void _openGraphFor(String identifier) {
    if (!_checkGuestSearchLimit()) return;
    final clean = identifier.trim();
    if (clean.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConnectedGraphView(seedDoi: clean)),
    );
  }

  /// Matches DOIs, paper URLs, and bare IDs (arXiv, PMID/PMC, OpenAlex, S2) —
  /// anything the backend's universal identifier classifier can resolve.
  bool _looksLikeIdentifier(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return false;
    return v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('10.') ||
        v.startsWith('doi:') ||
        v.startsWith('pmid:') ||
        v.startsWith('pmc') ||
        v.startsWith('arxiv') ||
        RegExp(r'^\d{4}\.\d{4,5}(v\d+)?$').hasMatch(v) ||
        RegExp(r'^w\d{1,12}$').hasMatch(v) ||
        RegExp(r'^[0-9a-f]{40}$').hasMatch(v);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppTheme.primaryLightBlue : AppTheme.primaryBlue;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              isDark ? 'assets/images/logo_dark.png' : 'assets/images/logo_light.png',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 8),
            const Text(
              'PaperGraph',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
          ],
        ),
        actions: [
          BlocBuilder<NotificationCubit, NotificationState>(
            builder: (context, notifState) {
              final unreadCount = notifState.notifications.where((n) => !n.isRead).length;
              return IconButton(
                tooltip: 'Notifications',
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text('$unreadCount'),
                  backgroundColor: AppTheme.accentEmerald,
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () => NotificationsSheet.show(context),
              );
            },
          ),
          IconButton(
            tooltip: 'Toggle theme',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
            onPressed: () => context.read<ThemeCubit>().toggleTheme(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 28),
              Text(
                'Explore connected literature.',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.2,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Search any paper to grow its graph — prior works, derivative works, and the neighbors in between.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _buildGuestTrialBanner(isDark),
              const SizedBox(height: 12),
              _buildSearchField(isDark),
              const SizedBox(height: 6),
              _buildSearchResults(isDark, accent),
              const SizedBox(height: 26),
              _buildRecentGraphs(isDark, accent),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuestTrialBanner(bool isDark) {
    final authProvider = Provider.of<AuthProvider>(context);
    if (authProvider.isAuthenticated) {
      return const SizedBox.shrink();
    }

    final count = HiveService.getGuestSearchCount();
    final hasSearchLeft = count < 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: hasSearchLeft
            ? (isDark ? AppTheme.primaryLightBlue.withAlpha(22) : const Color(0xFFF0F9FF))
            : (isDark ? AppTheme.accentRose.withAlpha(22) : const Color(0xFFFFF1F2)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasSearchLeft
              ? (isDark ? AppTheme.accentCyan.withAlpha(60) : const Color(0xFFBAE6FD))
              : (isDark ? AppTheme.accentRose.withAlpha(60) : const Color(0xFFFECDD3)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasSearchLeft ? Icons.info_outline_rounded : Icons.lock_outline_rounded,
            size: 18,
            color: hasSearchLeft ? AppTheme.primaryLightBlue : AppTheme.accentRose,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasSearchLeft
                  ? 'Guest Mode: 1 free preview search available'
                  : 'Free search used. Create account for unlimited access',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: hasSearchLeft
                    ? (isDark ? Colors.white : const Color(0xFF0369A1))
                    : (isDark ? Colors.white : const Color(0xFFBE123C)),
              ),
            ),
          ),
          if (!hasSearchLeft)
            GestureDetector(
              onTap: () => AuthGateBottomSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentRose,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Unlock',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14.5),
      onChanged: (value) {
        setState(() {}); // refresh the clear-button visibility

        final auth = Provider.of<AuthProvider>(context, listen: false);
        final hasSearchLeft = auth.isAuthenticated || HiveService.getGuestSearchCount() < 1;
        if (!hasSearchLeft) {
          // Do not spam backend queries when guest limit is exhausted
          return;
        }

        final cubit = context.read<SearchCubit>();
        // Links and identifiers route straight to the graph — never to search.
        if (_looksLikeIdentifier(value)) {
          cubit.clear();
        } else {
          cubit.search(value);
        }
      },
      onSubmitted: (value) {
        if (!_checkGuestSearchLimit()) return;
        if (_looksLikeIdentifier(value)) {
          _openGraphFor(value);
        } else {
          context.read<SearchCubit>().search(value, immediate: true);
        }
      },
      decoration: InputDecoration(
        hintText: 'Search by title, DOI, or keyword…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 19),
                onPressed: () {
                  _searchController.clear();
                  context.read<SearchCubit>().clear();
                  setState(() {});
                },
              )
            : null,
      ),
    );
  }

  Widget _buildSearchResults(bool isDark, Color accent) {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, state) {
        if (state is SearchLoading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        if (state is SearchEmpty) {
          return _hint(isDark,
              'No papers matched. Try a full title or paste the DOI directly.');
        }
        if (state is SearchError) {
          return _hint(isDark, state.message);
        }
        if (state is SearchLoaded) {
          return Column(
            children: [
              for (final item in state.items)
                _searchResultTile(item, isDark, accent),
            ],
          );
        }
        return _hint(
          isDark,
          _looksLikeIdentifier(_searchController.text)
              ? 'Identifier detected — press Enter to build its graph directly.'
              : 'Paste any paper link or DOI — or search by title, e.g. "Attention Is All You Need".',
        );
      },
    );
  }

  Widget _searchResultTile(SearchResultItem item, bool isDark, Color accent) {
    final metaParts = <String>[
      if (item.authors.isNotEmpty)
        item.authors.first + (item.authors.length > 1 ? ' et al.' : ''),
      if (item.year != null) '${item.year}',
      if (item.citationCount > 0) '${item.citationCount} citations',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openGraphFor(
        (item.doi != null && item.doi!.isNotEmpty)
            ? item.doi!
            : item.canonicalId,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withAlpha(20),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.hub_outlined, size: 17, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metaParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentGraphs(bool isDark, Color accent) {
    return BlocBuilder<SearchCubit, SearchState>(
      builder: (context, searchState) {
        // Recent graphs only share the screen with the idle search state.
        if (searchState is! SearchInitial) return const SizedBox.shrink();

        return BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, libState) {
            final graphs = libState is LibraryLoaded
                ? libState.cachedGraphs
                : const <GraphSnapshot>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT GRAPHS',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary,
                      ),
                    ),
                    if (graphs.isNotEmpty)
                      Text(
                        '${graphs.length}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (graphs.isEmpty)
                  _hint(isDark,
                      'Graphs you generate will appear here for quick re-opening — even offline.')
                else
                  for (final graph in graphs.take(3))
                    _recentGraphTile(graph, isDark, accent),
              ],
            );
          },
        );
      },
    );
  }

  Widget _recentGraphTile(GraphSnapshot graph, bool isDark, Color accent) {
    final metaParts = <String>[
      if (graph.origin.year != null) '${graph.origin.year}',
      '${graph.nodes.length} papers',
      graph.status == GraphJobStatus.partial ? 'partial' : 'completed',
    ];

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConnectedGraphView(initialSnapshot: graph),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: accent.withAlpha(20),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(Icons.bubble_chart_outlined, size: 17, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    graph.origin.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppTheme.darkTextPrimary
                          : AppTheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metaParts.join(' · '),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _hint(bool isDark, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: isDark
              ? AppTheme.darkTextSecondary
              : AppTheme.lightTextSecondary,
        ),
      ),
    );
  }
}
