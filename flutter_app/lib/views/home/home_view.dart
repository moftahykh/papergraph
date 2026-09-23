import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/graph/graph_cubit.dart';
import '../../cubits/graph/graph_state.dart';
import '../../cubits/discovery/discovery_cubit.dart';
import '../../cubits/discovery/discovery_state.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../cubits/search/search_cubit.dart';
import '../../cubits/search/search_state.dart';
import '../../models/api_schemas.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import '../../providers/auth_provider.dart';
import '../auth/widgets/auth_gate_sheet.dart';
import '../favorites/favorites_view.dart';
import '../graph_view/connected_graph_view.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/paper_graph_mark.dart';
import '../research_monitoring/graph_updates_view.dart';
import '../settings/settings_view.dart';

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
  final FocusNode _searchFocusNode = FocusNode();
  String? _dismissedReadyGraphId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DiscoveryCubit>().load();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePasteDoi() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty or does not contain text'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _searchController.text = text;
    setState(() {});
    if (_looksLikeIdentifier(text)) {
      _openGraphFor(text);
    } else {
      if (!_checkGuestSearchLimit()) return;
      if (!mounted) return;
      context.read<SearchCubit>().search(text, immediate: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final searchState = context.read<SearchCubit>().state;
    final query = switch (searchState) {
      SearchLoading(:final query) => query,
      SearchLoaded(:final query) => query,
      SearchEmpty(:final query) => query,
      SearchError(:final query) => query,
      _ => '',
    };
    if (query.isNotEmpty && _searchController.text != query) {
      _searchController
        ..text = query
        ..selection = TextSelection.collapsed(offset: query.length);
    }
  }

  bool _checkGuestSearchLimit() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.isAuthenticated) {
      return true; // Authenticated members have unlimited search
    }

    final count = HiveService.getGuestSearchCount();
    if (count >= HiveService.guestPreviewLimit) {
      AuthGateBottomSheet.show(context);
      return false;
    }

    HiveService.incrementGuestSearchCount();
    setState(() {}); // refresh banner state
    return true;
  }

  Future<void> _openGraphFor(String identifier) async {
    final graphState = context.read<GraphCubit>().state;
    if (graphState is GraphCreating || graphState is GraphPolling) {
      _showActiveGraphJobMessage();
      return;
    }

    if (!_checkGuestSearchLimit()) return;
    final clean = identifier.trim();
    if (clean.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConnectedGraphView(seedDoi: clean)),
    );
    if (!mounted) return;
    context.read<LibraryCubit>().loadLibrary();
  }

  Future<void> _openActiveGraphJob() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ConnectedGraphView()));
    if (!mounted) return;
    context.read<LibraryCubit>().loadLibrary();
  }

  void _showActiveGraphJobMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('A literature graph is already being built.'),
          action: SnackBarAction(label: 'View', onPressed: _openActiveGraphJob),
        ),
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
            PaperGraphMark(size: 24, isDark: isDark),
            const SizedBox(width: 10),
            Text(
              'PaperGraph',
              style: GoogleFonts.instrumentSerif(
                fontSize: 24,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        actions: [
          BlocBuilder<NotificationCubit, NotificationState>(
            builder: (context, notifState) {
              final unreadCount = notifState.notifications
                  .where((n) => !n.isRead)
                  .length;
              return IconButton(
                tooltip: 'Notifications',
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text('$unreadCount'),
                  backgroundColor: const Color(0xFFEF4444),
                  child: const Icon(Icons.notifications_outlined),
                ),
                onPressed: () => NotificationsSheet.show(context),
              );
            },
          ),
          IconButton(
            tooltip: 'Profile and settings',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsView(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Explore connected literature.',
                style: AppTheme.brandTitleStyle(
                  fontSize: 32,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ).copyWith(height: 1.15),
              ),
              const SizedBox(height: 6),
              Text(
                'Discover the papers connected to your research — citations, similarities, and foundational prior works.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _buildGuestTrialBanner(isDark),
              const SizedBox(height: 12),
              _buildSearchField(isDark),
              _buildTrendingChips(isDark),
              _buildActiveGraphJob(isDark, accent),
              const SizedBox(height: 6),
              _buildSearchResults(isDark, accent),
              const SizedBox(height: 24),
              _buildRecentGraphs(isDark, accent),
              _buildDiscoveryRecommendation(isDark, accent),
              const SizedBox(height: 110),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveGraphJob(bool isDark, Color accent) {
    return BlocBuilder<GraphCubit, GraphState>(
      builder: (context, graphState) {
        if (graphState is GraphLoaded && graphState.isNewlyGenerated) {
          final snapshot = graphState.snapshot;
          if (_dismissedReadyGraphId == snapshot.graphId) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              color: isDark ? const Color(0xFF161618) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () async {
                  final libCubit = context.read<LibraryCubit>();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ConnectedGraphView(initialSnapshot: snapshot),
                    ),
                  );
                  libCubit.loadLibrary();
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x22FFFFFF)
                          : const Color(0xFFE5E5EA),
                      width: 0.75,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(isDark ? 40 : 8),
                        blurRadius: 14,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
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
                              Icons.bubble_chart_outlined,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1C1C1E),
                              size: 18,
                            ),
                          ),
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF161618)
                                      : Colors.white,
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LITERATURE GRAPH READY',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.7,
                                color: isDark
                                    ? const Color(0xFFA1A1AA)
                                    : const Color(0xFF71717A),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              snapshot.origin.title,
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
                            const SizedBox(height: 1),
                            Text(
                              '${snapshot.nodes.length} connected papers · Tap to explore',
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
                      // iOS Pro pill action button
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open',
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFF09090B)
                                    : Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: isDark
                                  ? const Color(0xFF09090B)
                                  : Colors.white,
                              size: 13,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() {
                            _dismissedReadyGraphId = snapshot.graphId;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: isDark
                                ? const Color(0xFF71717A)
                                : const Color(0xFF8E8E93),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (graphState is! GraphCreating && graphState is! GraphPolling) {
          return const SizedBox.shrink();
        }

        final progress = graphState is GraphPolling
            ? graphState.progress.clamp(0.05, 0.98).toDouble()
            : 0.05;
        final originId = graphState is GraphCreating
            ? graphState.originId
            : (graphState as GraphPolling).originId;

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Material(
            color: isDark ? const Color(0xFF161618) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _openActiveGraphJob,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x22FFFFFF)
                        : const Color(0xFFE5E5EA),
                    width: 0.75,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 40 : 8),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.2,
                        backgroundColor: isDark
                            ? const Color(0x18FFFFFF)
                            : const Color(0xFFE5E5EA),
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SYNTHESIZING GRAPH',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.7,
                              color: isDark
                                  ? const Color(0xFFA1A1AA)
                                  : const Color(0xFF71717A),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Building literature graph',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF1C1C1E),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            originId.isEmpty
                                ? '${(progress * 100).round()}% completed'
                                : '${(progress * 100).round()}% · $originId',
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
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View',
                          style: TextStyle(
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1C1C1E),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(width: 1),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark
                              ? const Color(0xFFA1A1AA)
                              : const Color(0xFF8E8E93),
                          size: 16,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGuestTrialBanner(bool isDark) {
    final authProvider = Provider.of<AuthProvider>(context);
    if (authProvider.isAuthenticated) {
      return const SizedBox.shrink();
    }

    final count = HiveService.getGuestSearchCount();
    final hasSearchLeft = count < HiveService.guestPreviewLimit;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161618) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE5E5EA),
          width: 0.75,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasSearchLeft
                ? Icons.info_outline_rounded
                : Icons.lock_outline_rounded,
            size: 16,
            color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasSearchLeft
                  ? 'Guest Preview: ${HiveService.guestPreviewLimit} free searches available'
                  : 'Free search used. Create account for unlimited access',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? const Color(0xFFD4D4D8)
                    : const Color(0xFF3F3F46),
              ),
            ),
          ),
          if (!hasSearchLeft) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => AuthGateBottomSheet.show(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  'Unlock',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF09090B) : Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(bool isDark) {
    final hasText = _searchController.text.isNotEmpty;

    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14.5),
      onChanged: (value) {
        setState(() {}); // refresh the clear-button visibility

        final auth = Provider.of<AuthProvider>(context, listen: false);
        final hasSearchLeft =
            auth.isAuthenticated ||
            HiveService.getGuestSearchCount() < HiveService.guestPreviewLimit;
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
        if (_looksLikeIdentifier(value)) {
          _openGraphFor(value);
        } else {
          // Do not consume the guest preview for an empty or too-short query.
          if (value.trim().length < 2) return;
          if (!_checkGuestSearchLimit()) return;
          context.read<SearchCubit>().search(value, immediate: true);
        }
      },
      decoration: InputDecoration(
        hintText: 'Search papers, authors, or DOI',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: hasText
            ? IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 19),
                onPressed: () {
                  _searchController.clear();
                  context.read<SearchCubit>().clear();
                  setState(() {});
                },
              )
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _handlePasteDoi,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFFE4E4E7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.content_paste_rounded,
                              size: 13,
                              color: isDark
                                  ? const Color(0xFFF4F4F5)
                                  : const Color(0xFF18181B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Paste',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? const Color(0xFFF4F4F5)
                                    : const Color(0xFF18181B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTrendingChips(bool isDark) {
    return BlocBuilder<DiscoveryCubit, DiscoveryState>(
      builder: (context, discoveryState) {
        final topics = discoveryState is DiscoveryLoaded
            ? discoveryState.topics
            : const <DiscoveryTopic>[];

        if (topics.isEmpty) {
          if (discoveryState is DiscoveryUnavailable) {
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  Text(
                    'Trending topics unavailable',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        context.read<DiscoveryCubit>().load(force: true),
                    child: Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppTheme.primaryLightBlue
                            : AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: topics.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final topic = topics[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    _searchController.text = topic.query;
                    setState(() {});
                    if (!_checkGuestSearchLimit()) return;
                    context.read<SearchCubit>().search(
                      topic.query,
                      immediate: true,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1C1C1F)
                          : const Color(0xFFEBEBF0),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isDark
                            ? const Color(0x22FFFFFF)
                            : const Color(0x16000000),
                        width: 0.75,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        topic.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFFE4E4E7)
                              : const Color(0xFF27272A),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
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
          return _hint(
            isDark,
            'No papers matched. Try a full title or paste the DOI directly.',
          );
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
        return const SizedBox.shrink();
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
                color: isDark ? AppTheme.darkBorder : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.article_outlined,
                  size: 19,
                  color: isDark
                      ? AppTheme.darkTextPrimary
                      : AppTheme.lightTextPrimary,
                ),
              ),
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
                  if (item.matchReason != null &&
                      item.matchReason!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.matchReason!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                ? libState.recentGraphs
                : const <GraphSnapshot>[];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      graphs.isEmpty ? 'START EXPLORING' : 'RECENT GRAPHS',
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
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FavoritesView(
                                mode: FavoritesViewMode.graphs,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          child: Text(
                            'View all',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? const Color(0xFFA1A1AA)
                                  : const Color(0xFF71717A),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (graphs.isEmpty)
                  _buildFirstGraphCard(isDark, accent)
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

  Widget _buildFirstGraphCard(bool isDark, Color accent) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 24 : 8),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkSurface
                  : const Color(0xFFF1F4F8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: PaperGraphMark(size: 34, isDark: isDark),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start your first research map',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Search for a paper or paste a DOI to explore its connected literature.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: secondary,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    _startFirstResearchMap();
                  },
                  icon: const Icon(Icons.search_rounded, size: 17),
                  label: const Text('Create your first graph'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: isDark ? AppTheme.darkBg : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 10,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentGraphTile(GraphSnapshot graph, bool isDark, Color accent) {
    final year = graph.origin.year != null ? '${graph.origin.year}' : null;
    final paperCount = '${graph.nodes.length} papers';
    final isPartial = graph.status == GraphJobStatus.partial;
    const partialColor = Color(0xFFF59E0B);

    final originNode =
        graph.nodes.where((n) => n.isOrigin).firstOrNull ??
        (graph.nodes.isNotEmpty ? graph.nodes.first : null);
    final authorsText = originNode != null && originNode.authors.isNotEmpty
        ? originNode.authors.take(3).join(', ') +
              (originNode.authors.length > 3 ? ' et al.' : '')
        : (originNode?.venue != null && originNode!.venue!.isNotEmpty
              ? originNode.venue!
              : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE5E5EA),
          width: 0.75,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 35 : 8),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final libCubit = context.read<LibraryCubit>();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConnectedGraphView(initialSnapshot: graph),
              ),
            );
            libCubit.loadLibrary();
          },
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF242426)
                        : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x18FFFFFF)
                          : const Color(0xFFE5E5EA),
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    Icons.hub_outlined,
                    size: 19,
                    color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        graph.origin.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: isDark
                              ? AppTheme.darkTextPrimary
                              : AppTheme.lightTextPrimary,
                        ),
                      ),
                      if (authorsText != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          authorsText,
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (year != null)
                            _buildPillBadge(text: year, isDark: isDark),
                          _buildPillBadge(text: paperCount, isDark: isDark),
                          if (isPartial)
                            _buildPillBadge(
                              text: 'LIMITED DATA',
                              textColor: partialColor,
                              bgColor: partialColor.withAlpha(25),
                              borderColor: partialColor.withAlpha(60),
                              isDark: isDark,
                              isBold: true,
                            ),
                        ],
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

  Widget _buildPillBadge({
    required String text,
    Color? textColor,
    Color? bgColor,
    Color? borderColor,
    required bool isDark,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:
            bgColor ??
            (isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7)),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color:
              borderColor ??
              (isDark ? const Color(0x18FFFFFF) : const Color(0xFFE5E5EA)),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: isBold ? 0.3 : 0,
          color:
              textColor ??
              (isDark ? const Color(0xFFD4D4D8) : const Color(0xFF52525B)),
        ),
      ),
    );
  }

  Widget _buildDiscoveryRecommendation(bool isDark, Color accent) {
    return BlocBuilder<DiscoveryCubit, DiscoveryState>(
      builder: (context, state) {
        if (state is! DiscoveryLoaded) {
          return const SizedBox.shrink();
        }

        final secondary = isDark
            ? AppTheme.darkTextSecondary
            : AppTheme.lightTextSecondary;

        if (state.recommendation == null) {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );
          final isAuthenticated = authProvider.isAuthenticated;
          final hasSavedGraph = context.select<LibraryCubit, bool>((cubit) {
            final libraryState = cubit.state;
            return libraryState is LibraryLoaded &&
                libraryState.cachedGraphs.isNotEmpty;
          });
          final hasActiveResearchUpdates =
              isAuthenticated && hasSavedGraph;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'RESEARCH UPDATES',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x22FFFFFF)
                        : const Color(0xFFE5E5EA),
                    width: 0.75,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: !isAuthenticated
                        ? () => AuthGateBottomSheet.show(
                            context,
                            reason: AuthGateReason.researchUpdates,
                          )
                        : hasActiveResearchUpdates
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const FavoritesView(
                                mode: FavoritesViewMode.savedGraphs,
                              ),
                            ),
                          )
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF242426)
                                      : const Color(0xFFF2F2F7),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  Icons.notifications_none_rounded,
                                  color: accent,
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      !isAuthenticated
                                          ? 'Sign in to follow research updates'
                                          : hasActiveResearchUpdates
                                          ? 'Graph saved on this device'
                                          : 'Save your first graph to unlock research updates',
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? AppTheme.darkTextPrimary
                                            : AppTheme.lightTextPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      !isAuthenticated
                                          ? 'Save a graph and receive relevant new-paper alerts.'
                                          : hasActiveResearchUpdates
                                          ? 'Open your saved graph to check research updates.'
                                          : 'Research alerts will appear after you save a graph.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isAuthenticated ||
                                  hasActiveResearchUpdates) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: secondary,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        final recommendation = state.recommendation!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'NEW IN YOUR RESEARCH',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0x22FFFFFF)
                      : const Color(0xFFE5E5EA),
                  width: 0.75,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 35 : 8),
                    blurRadius: 14,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () =>
                      _openExistingGraphForRecommendation(recommendation),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF242426)
                                    : const Color(0xFFF2F2F7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.auto_awesome_outlined,
                                color: accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                recommendation.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                  color: isDark
                                      ? AppTheme.darkTextPrimary
                                      : AppTheme.lightTextPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          recommendation.reason,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildPillBadge(
                              text: recommendation.relationType,
                              isDark: isDark,
                              isBold: true,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                recommendation.graphTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: secondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'View in Graph →',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _startFirstResearchMap() {
    FocusScope.of(context).requestFocus(_searchFocusNode);
  }

  Future<void> _openExistingGraphForRecommendation(
    DiscoveryRecommendation recommendation,
  ) async {
    final localGraphId = recommendation.localGraphId.trim();
    if (localGraphId.isEmpty) return;

    final snapshot = context.read<LibraryCubit>().getCachedGraph(localGraphId);
    if (snapshot != null) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConnectedGraphView(initialSnapshot: snapshot),
        ),
      );
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GraphUpdatesView(
            localGraphId: localGraphId,
            graphTitle: recommendation.graphTitle.isNotEmpty
                ? recommendation.graphTitle
                : 'Saved graph',
          ),
        ),
      );
    }
    if (!mounted) return;
    context.read<LibraryCubit>().loadLibrary();
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
