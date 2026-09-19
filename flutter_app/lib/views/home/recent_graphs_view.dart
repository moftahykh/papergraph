import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import '../graph_view/connected_graph_view.dart';
import '../widgets/paper_graph_mark.dart';

/// Full screen view displaying all recently explored graphs with search,
/// library-bookmarking, and deletion capabilities.
class RecentGraphsView extends StatefulWidget {
  const RecentGraphsView({super.key});

  @override
  State<RecentGraphsView> createState() => _RecentGraphsViewState();
}

class _RecentGraphsViewState extends State<RecentGraphsView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        toolbarHeight: 68,
        elevation: 0,
        backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 19,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Recent Graphs',
          style: AppTheme.brandTitleStyle(
            fontSize: 28,
            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
          ),
        ),
      ),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          final allRecent = state is LibraryLoaded
              ? state.recentGraphs
              : const <GraphSnapshot>[];

          final filtered = _query.isEmpty
              ? allRecent
              : allRecent.where((g) {
                  final title = g.origin.title.toLowerCase();
                  final doi = g.origin.canonicalId.toLowerCase();
                  final q = _query.toLowerCase();
                  return title.contains(q) || doi.contains(q);
                }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value.trim()),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search recent graphs...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: isDark ? AppTheme.darkSurface : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final graph = filtered[index];
                          final isSaved = state is LibraryLoaded &&
                              state.isGraphCached(graph.graphId);
                          return _buildGraphCard(
                            context,
                            graph,
                            isSaved,
                            isDark,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PaperGraphMark(size: 42, isDark: isDark),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty ? 'No recent graphs' : 'No matching graphs found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _query.isEmpty
                  ? 'Graphs you explore will appear here for fast re-opening.'
                  : 'Try searching with another keyword or paper title.',
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
      ),
    );
  }

  Widget _buildGraphCard(
    BuildContext context,
    GraphSnapshot graph,
    bool isSaved,
    bool isDark,
  ) {
    final metaParts = <String>[
      if (graph.origin.year != null) '${graph.origin.year}',
      '${graph.nodes.length} papers',
      graph.status == GraphJobStatus.partial ? 'partial' : 'completed',
    ];

    return Material(
      color: isDark ? AppTheme.darkCard : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ConnectedGraphView(initialSnapshot: graph),
            ),
          );
          if (!context.mounted) return;
          context.read<LibraryCubit>().loadLibrary();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 13, 10, 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
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
                  Icons.bubble_chart_outlined,
                  size: 18,
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : AppTheme.lightTextPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final part in metaParts)
                          Text(
                            part,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Bookmark save toggle button
              IconButton(
                icon: Icon(
                  isSaved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 20,
                  color: isSaved
                      ? (isDark ? Colors.white : AppTheme.primaryBlue)
                      : (isDark ? Colors.white38 : Colors.black38),
                ),
                tooltip: isSaved ? 'Saved to library' : 'Save to library',
                onPressed: () async {
                  final cubit = context.read<LibraryCubit>();
                  if (isSaved) {
                    await cubit.removeCachedGraph(graph.graphId);
                  } else {
                    await cubit.cacheGraph(graph);
                  }
                },
              ),
              // Delete from recents menu
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                color: isDark ? AppTheme.darkCard : Colors.white,
                onSelected: (action) async {
                  if (action == 'delete') {
                    await context
                        .read<LibraryCubit>()
                        .removeCachedGraph(graph.graphId);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          size: 17,
                          color: Color(0xFFEF4444),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Remove from history',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ],
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
}
