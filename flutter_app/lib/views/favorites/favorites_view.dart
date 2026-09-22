import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/paper_url_helper.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';
import '../graph_view/connected_graph_view.dart';
import '../paper_details/citation_bottom_sheet.dart';
import '../paper_details/paper_details_view.dart';
import '../research_monitoring/graph_updates_view.dart';
import '../widgets/paper_graph_mark.dart';

enum FavoritesViewMode {
  /// The legacy two-tab Library surface, kept for direct widget coverage.
  library,
  papers,
  graphs,
}

class FavoritesView extends StatefulWidget {
  final FavoritesViewMode mode;

  const FavoritesView({
    super.key,
    this.mode = FavoritesViewMode.library,
  });

  static final ValueNotifier<int> selectedTabNotifier = ValueNotifier<int>(0);

  static void selectTab(int index) {
    selectedTabNotifier.value = index.clamp(0, 1);
  }

  @override
  State<FavoritesView> createState() => _FavoritesViewState();
}

class _FavoritesViewState extends State<FavoritesView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _librarySearchController =
      TextEditingController();
  String _libraryQuery = '';
  bool _offlineOnly = false;
  bool _withNotesOnly = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.mode == FavoritesViewMode.graphs
          ? 1
          : widget.mode == FavoritesViewMode.papers
              ? 0
              : FavoritesView.selectedTabNotifier.value.clamp(0, 1),
    );
    _tabController.addListener(_handleTabChanged);
    FavoritesView.selectedTabNotifier.addListener(_handleExternalTabRequest);
  }

  void _handleTabChanged() {
    if (_tabController.index != FavoritesView.selectedTabNotifier.value) {
      FavoritesView.selectedTabNotifier.value = _tabController.index;
    }
  }

  void _handleExternalTabRequest() {
    final target = FavoritesView.selectedTabNotifier.value.clamp(0, 1);
    if (_tabController.index != target) {
      _tabController.animateTo(target);
    }
  }

  @override
  void dispose() {
    FavoritesView.selectedTabNotifier.removeListener(_handleExternalTabRequest);
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _librarySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.mode != FavoritesViewMode.library) {
      return _buildSingleCollectionView(context, isDark);
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          'Library',
          style: AppTheme.brandTitleStyle(
            fontSize: 32,
            color: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.lightTextPrimary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            height: 46,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : const Color(0xFFF1F3F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 30 : 12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: isDark
                  ? AppTheme.primaryLightBlue
                  : AppTheme.primaryBlue,
              unselectedLabelColor: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
              labelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Papers'),
                Tab(text: 'Graphs'),
              ],
            ),
          ),
        ),
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          if (state is LibraryError) {
            return TabBarView(
              controller: _tabController,
              children: [
                _buildLoadError(context, state.message, isDark),
                _buildLoadError(context, state.message, isDark),
              ],
            );
          }
          final papers = state is LibraryLoaded
              ? state.savedPapers
              : <CanonicalPaper>[];
          // The dedicated Graphs destination is the user's full local graph
          // history, including graphs that have not been explicitly pinned
          // to the Library. The Library's legacy Graphs tab remains saved-only
          // for backwards compatibility with existing direct widget users.
          final graphs = state is LibraryLoaded
              ? widget.mode == FavoritesViewMode.graphs
                  ? state.recentGraphs
                  : state.cachedGraphs
              : <GraphSnapshot>[];
          final notes = state is LibraryLoaded
              ? state.paperNotes
              : <String, String>{};

          return TabBarView(
            controller: _tabController,
            children: [
              _buildPapersTab(context, papers, notes, isDark),
              _buildGraphsTab(context, graphs, isDark),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSingleCollectionView(BuildContext context, bool isDark) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          widget.mode == FavoritesViewMode.graphs ? 'Graphs' : 'Library',
          style: AppTheme.brandTitleStyle(
            fontSize: 32,
            color: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          if (state is LibraryError) {
            return _buildLoadError(context, state.message, isDark);
          }

          final papers = state is LibraryLoaded
              ? state.savedPapers
              : <CanonicalPaper>[];
          final graphs = state is LibraryLoaded
              ? state.cachedGraphs
              : <GraphSnapshot>[];
          final notes = state is LibraryLoaded
              ? state.paperNotes
              : <String, String>{};

          return widget.mode == FavoritesViewMode.graphs
              ? _buildGraphsTab(context, graphs, isDark)
              : _buildPapersTab(context, papers, notes, isDark);
        },
      ),
    );
  }

  Widget _buildPapersTab(
    BuildContext context,
    List<CanonicalPaper> papers,
    Map<String, String> notes,
    bool isDark,
  ) {
    if (papers.isEmpty) {
      return _buildEmptyState(
        icon: Icons.bookmark_add_outlined,
        title: 'Build your research library',
        description:
            'Save papers you want to revisit. Your notes will stay with each paper.',
        isDark: isDark,
      );
    }

    final query = _libraryQuery.toLowerCase();
    final visiblePapers = papers.where((paper) {
      final matchesQuery =
          query.isEmpty ||
          paper.title.toLowerCase().contains(query) ||
          paper.authorDisplay.toLowerCase().contains(query);
      final matchesNotes =
          !_withNotesOnly || (notes[paper.canonicalId] ?? '').trim().isNotEmpty;
      // Saved papers are already locally available. Keep this filter as a
      // product-level affordance so the UI remains ready for remote-only rows.
      final matchesOffline = !_offlineOnly || paper.canonicalId.isNotEmpty;
      return matchesQuery && matchesNotes && matchesOffline;
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
      itemCount: visiblePapers.isEmpty ? 2 : visiblePapers.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildLibraryTools(isDark);
        }
        if (visiblePapers.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_rounded,
                  size: 34,
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No papers match these filters',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  'Try another title, author, or filter.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        final paper = visiblePapers[index - 1];
        return _buildPaperCard(
          context,
          paper,
          notes[paper.canonicalId] ?? '',
          isDark,
        );
      },
    );
  }

  Widget _buildLibraryTools(bool isDark) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Column(
      children: [
        TextField(
          controller: _librarySearchController,
          onChanged: (value) => setState(() => _libraryQuery = value.trim()),
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search your library',
            prefixIcon: const Icon(Icons.search_rounded, size: 19),
            suffixIcon: _libraryQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _librarySearchController.clear();
                      setState(() => _libraryQuery = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _libraryFilterChip(
                label: 'All',
                selected: !_offlineOnly && !_withNotesOnly,
                onSelected: () => setState(() {
                  _offlineOnly = false;
                  _withNotesOnly = false;
                }),
              ),
              const SizedBox(width: 8),
              _libraryFilterChip(
                label: 'Offline',
                selected: _offlineOnly,
                onSelected: () => setState(() {
                  _offlineOnly = !_offlineOnly;
                  _withNotesOnly = false;
                }),
              ),
              const SizedBox(width: 8),
              _libraryFilterChip(
                label: 'With notes',
                selected: _withNotesOnly,
                onSelected: () => setState(() {
                  _withNotesOnly = !_withNotesOnly;
                  _offlineOnly = false;
                }),
              ),
            ],
          ),
        ),
        if (_libraryQuery.isNotEmpty || _offlineOnly || _withNotesOnly)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Refined library view',
                style: TextStyle(fontSize: 11.5, color: secondary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _libraryFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? Colors.white : AppTheme.lightTextSecondary,
      ),
      selectedColor: AppTheme.primaryBlue,
      backgroundColor: Colors.white,
      side: BorderSide(
        color: selected ? AppTheme.primaryBlue : AppTheme.lightBorder,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _buildPaperCard(
    BuildContext context,
    CanonicalPaper paper,
    String note,
    bool isDark,
  ) {
    final paperModel = PaperModel(
      id: paper.canonicalId,
      title: paper.title,
      authors: paper.authors.map((a) => a.name).toList(),
      year: paper.year ?? 2020,
      journal: paper.venue ?? 'Academic Literature',
      abstractText: paper.abstractText ?? 'Research paper',
      citationsCount: paper.citationCount,
      influentialCitations: 0,
      connectedPaperIds: const [],
      pdfUrl: '',
      keyTakeaways: const [],
      category: paper.topics.isNotEmpty ? paper.topics.first : 'Research Paper',
      doi:
          paper.doi ??
          (paper.canonicalId.startsWith('10.') ? paper.canonicalId : ''),
      isFavorite: true,
      personalNotes: note,
    );
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaperDetailsView(paper: paperModel),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      paper.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Paper options',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz_rounded, color: secondary),
                    onSelected: (value) {
                      if (value == 'notes') {
                        _showEditNotesDialog(context, paper.canonicalId, note);
                      } else if (value == 'cite') {
                        CitationBottomSheet.show(context, paperModel);
                      } else if (value == 'remove') {
                        _confirmRemovePaper(context, paper);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'notes', child: Text('Edit notes')),
                      PopupMenuItem(
                        value: 'cite',
                        child: Text('Create citation'),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove from library'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                paper.authorDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _metadata(
                    Icons.calendar_today_outlined,
                    paper.yearDisplay,
                    secondary,
                  ),
                  _metadata(
                    Icons.format_quote_rounded,
                    '${paper.citationCount} citations',
                    secondary,
                  ),
                  _metadata(
                    Icons.download_done_rounded,
                    'Available offline',
                    isDark ? AppTheme.originGreenDark : AppTheme.originGreen,
                  ),
                ],
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 11),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSurface
                        : AppTheme.primaryBlue.withAlpha(10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sticky_note_2_outlined,
                        size: 16,
                        color: isDark
                            ? AppTheme.actionPurpleDark
                            : AppTheme.actionPurple,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ConnectedGraphView(centerPaper: paperModel),
                        ),
                      ),
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('Explore graph'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Open paper',
                    onPressed: () {
                      final url = PaperUrlHelper.resolvePaperUrl(
                        doi: paper.doi,
                        canonicalId: paper.canonicalId,
                        title: paper.title,
                      );
                      PaperUrlHelper.launchPaper(
                        context,
                        url: url,
                        title: paper.title,
                      );
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGraphsTab(
    BuildContext context,
    List<GraphSnapshot> graphs,
    bool isDark,
  ) {
    if (graphs.isEmpty) {
      return _buildEmptyState(
        customIcon: PaperGraphMark(size: 40, isDark: isDark),
        title: 'No graphs yet',
        description:
            'Create a literature graph to keep it available for quick access.',
        isDark: isDark,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
      itemCount: graphs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _buildGraphCard(context, graphs[index], isDark),
    );
  }

  Widget _buildGraphCard(
    BuildContext context,
    GraphSnapshot snapshot,
    bool isDark,
  ) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final needsRefresh = snapshot.isExpired;

    void openGraph() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ConnectedGraphView(initialSnapshot: snapshot),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: openGraph,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 15, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      snapshot.origin.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.3,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Graph options',
                    padding: EdgeInsets.zero,
                    icon: Icon(Icons.more_horiz_rounded, color: secondary),
                    onSelected: (value) {
                      if (value == 'remove') {
                        _confirmRemoveGraph(context, snapshot);
                      } else if (value == 'updates') {
                        _openGraphUpdates(context, snapshot);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'updates',
                        child: Text('Research updates'),
                      ),
                      PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove graph'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                '${snapshot.nodes.length} papers  •  ${snapshot.citationEdges.length} citations  •  ${snapshot.similarityEdges.length} related links',
                style: TextStyle(fontSize: 12.5, color: secondary),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _statusChip(
                    context,
                    icon: needsRefresh
                        ? Icons.refresh_rounded
                        : Icons.download_done_rounded,
                    label: needsRefresh
                        ? 'Refresh recommended'
                        : 'Available offline',
                    warning: needsRefresh,
                  ),
                  Text(
                    _formatUpdated(snapshot.createdAt),
                    style: TextStyle(fontSize: 11.5, color: secondary),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openGraphUpdates(context, snapshot),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Updates'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: openGraph,
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('Open graph'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openGraphUpdates(BuildContext context, GraphSnapshot snapshot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GraphUpdatesView(
          localGraphId: snapshot.graphId,
          graphTitle: snapshot.origin.title,
        ),
      ),
    );
  }

  Widget _metadata(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11.5, color: color)),
      ],
    );
  }

  Widget _statusChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool warning,
  }) {
    final color = warning
        ? AppTheme.accentAmber
        : Theme.of(context).brightness == Brightness.dark
        ? AppTheme.originGreenDark
        : AppTheme.originGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadError(BuildContext context, String message, bool isDark) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 44, color: secondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: context.read<LibraryCubit>().loadLibrary,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    IconData? icon,
    Widget? customIcon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Align(
      alignment: const Alignment(0, -0.28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurface : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: Center(
                child:
                    customIcon ??
                    Icon(
                      icon,
                      size: 32,
                      color: isDark ? Colors.white : const Color(0xFF18181B),
                    ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: secondary),
            ),
          ],
        ),
      ),
    );
  }

  String _formatUpdated(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 2) return 'Updated just now';
    if (difference.inHours < 1) return 'Updated ${difference.inMinutes}m ago';
    if (difference.inHours < 24) return 'Updated ${difference.inHours}h ago';
    if (difference.inDays < 7) return 'Updated ${difference.inDays}d ago';
    return 'Updated ${value.day}/${value.month}/${value.year}';
  }

  Future<void> _confirmRemovePaper(
    BuildContext context,
    CanonicalPaper paper,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove paper?'),
        content: const Text(
          'The paper and its notes will be removed from your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final removed = await context.read<LibraryCubit>().removePaper(
        paper.canonicalId,
      );
      if (!context.mounted || removed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paper could not be removed. Try again.')),
      );
    }
  }

  Future<void> _confirmRemoveGraph(
    BuildContext context,
    GraphSnapshot snapshot,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove graph?'),
        content: const Text(
          'You will need an internet connection to create it again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final removed = await context.read<LibraryCubit>().removeCachedGraph(
        snapshot.graphId,
      );
      if (!context.mounted || removed) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Graph could not be removed. Try again.')),
      );
    }
  }

  void _showEditNotesDialog(
    BuildContext context,
    String paperId,
    String initialNote,
  ) {
    final controller = TextEditingController(text: initialNote);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('My notes'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Add an insight, question, or citation note…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final saved = await context.read<LibraryCubit>().saveNotes(
                paperId,
                controller.text,
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    saved
                        ? 'Notes saved'
                        : 'Notes could not be saved. Try again.',
                  ),
                  duration: const Duration(seconds: 2),
                  backgroundColor: saved
                      ? AppTheme.accentEmerald
                      : AppTheme.accentRose,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
