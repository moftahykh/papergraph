import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/graph/graph_cubit.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/library/library_state.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import '../../models/paper_model.dart';
import '../graph_view/connected_graph_view.dart';
import '../paper_details/citation_bottom_sheet.dart';
import '../paper_details/paper_details_view.dart';

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Offline Library (المكتبة المحلية)'),
          bottom: const TabBar(
            tabs: [
              Tab(
                icon: Icon(Icons.bookmark_rounded, size: 20),
                text: 'Saved Papers & Notes',
              ),
              Tab(
                icon: Icon(Icons.hub_rounded, size: 20),
                text: 'Cached Graphs',
              ),
            ],
          ),
        ),
        body: BlocBuilder<LibraryCubit, LibraryState>(
          builder: (context, state) {
            final savedPapers = state is LibraryLoaded ? state.savedPapers : <CanonicalPaper>[];
            final cachedGraphs = state is LibraryLoaded ? state.cachedGraphs : <GraphSnapshot>[];
            final paperNotes = state is LibraryLoaded ? state.paperNotes : <String, String>{};

            return TabBarView(
              children: [
                // TAB 1: Saved Papers & Research Notes
                _buildSavedPapersTab(context, savedPapers, paperNotes, isDark),

                // TAB 2: Cached Literature Graphs
                _buildCachedGraphsTab(context, cachedGraphs, isDark),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- TAB 1: SAVED PAPERS & PERSONAL NOTES ---
  Widget _buildSavedPapersTab(
    BuildContext context,
    List<CanonicalPaper> papers,
    Map<String, String> notes,
    bool isDark,
  ) {
    return Column(
      children: [
        // Offline Hive Status Banner
        _buildOfflineStatusBanner(
          title: 'Hive Local Paper Storage',
          description: 'All ${papers.length} saved papers and personal annotations are stored locally and accessible offline.',
          isDark: isDark,
        ),

        // Papers List or Empty State
        Expanded(
          child: papers.isEmpty
              ? _buildEmptyState(
                  icon: Icons.bookmark_outline_rounded,
                  title: 'No Saved Papers Yet',
                  description: 'Save landmark research papers and notes by tapping the bookmark icon in search or paper details.',
                  isDark: isDark,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: papers.length,
                  itemBuilder: (context, index) {
                    final paper = papers[index];
                    final note = notes[paper.canonicalId] ?? '';
                    return _buildCanonicalPaperCard(context, paper, note, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCanonicalPaperCard(
    BuildContext context,
    CanonicalPaper paper,
    String note,
    bool isDark,
  ) {
    // Convert to PaperModel for existing details / citation views
    final paperModel = PaperModel(
      id: paper.canonicalId,
      title: paper.title,
      authors: paper.authors.map((a) => a.name).toList(),
      year: paper.year ?? 2020,
      journal: paper.venue ?? 'Academic Literature',
      abstractText: paper.abstractText ?? 'Synthesized research paper.',
      citationsCount: paper.citationCount,
      influentialCitations: 0,
      connectedPaperIds: const [],
      pdfUrl: '',
      keyTakeaways: const [],
      category: paper.topics.isNotEmpty ? paper.topics.first : 'Research Paper',
      doi: paper.doi ?? (paper.canonicalId.startsWith('10.') ? paper.canonicalId : ''),
      isFavorite: true,
      personalNotes: note,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaperDetailsView(paper: paperModel)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      paper.topics.isNotEmpty ? paper.topics.first : 'Paper',
                      style: const TextStyle(
                        color: AppTheme.primaryLightBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    paper.yearDisplay,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.bookmark_rounded, color: AppTheme.accentAmber, size: 22),
                    tooltip: 'Remove from Library',
                    onPressed: () {
                      context.read<LibraryCubit>().removePaper(paper.canonicalId);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Text(
                paper.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.3),
              ),
              const SizedBox(height: 4),

              Text(
                paper.authorDisplay,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),

              // Personal notes indicator and inline editor
              if (note.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.note_rounded, size: 14, color: AppTheme.accentCyan),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        color: AppTheme.accentCyan,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Edit Research Notes',
                        onPressed: () => _showEditNotesDialog(context, paper.canonicalId, note),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Action buttons
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConnectedGraphView(centerPaper: paperModel),
                        ),
                      );
                    },
                    icon: const Icon(Icons.hub_rounded, size: 15),
                    label: const Text('Connected Graph', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentCyan,
                      side: const BorderSide(color: AppTheme.accentCyan),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (note.isEmpty)
                    TextButton.icon(
                      onPressed: () => _showEditNotesDialog(context, paper.canonicalId, ''),
                      icon: const Icon(Icons.add_comment_outlined, size: 15),
                      label: const Text('Add Note', style: TextStyle(fontSize: 12)),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.format_quote_rounded, size: 20),
                    tooltip: 'Cite Paper',
                    onPressed: () => CitationBottomSheet.show(context, paperModel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 2: CACHED LITERATURE GRAPHS ---
  Widget _buildCachedGraphsTab(
    BuildContext context,
    List<GraphSnapshot> graphs,
    bool isDark,
  ) {
    final expiredCount = graphs.where((g) => g.isExpired).length;

    return Column(
      children: [
        // Offline Cache Header & Prune Action
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withAlpha(20),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF0284C7).withAlpha(60)),
          ),
          child: Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: Color(0xFF38BDF8), size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Offline Literature Graph Cache',
                      style: TextStyle(
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${graphs.length} cached graph snapshots. Opens instantly without internet.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (expiredCount > 0)
                TextButton.icon(
                  onPressed: () async {
                    final pruned = await context.read<LibraryCubit>().pruneExpiredGraphs();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Pruned $pruned expired graph snapshots.'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.auto_delete_outlined, size: 14),
                  label: Text('Prune ($expiredCount)', style: const TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFF59E0B),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
            ],
          ),
        ),

        // Graphs List or Empty State
        Expanded(
          child: graphs.isEmpty
              ? _buildEmptyState(
                  icon: Icons.hub_outlined,
                  title: 'No Cached Graphs',
                  description: 'When viewing any synthesized literature graph, tap the bookmark icon in the top bar to save it for offline access.',
                  isDark: isDark,
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: graphs.length,
                  itemBuilder: (context, index) {
                    final snapshot = graphs[index];
                    return _buildCachedGraphCard(context, snapshot, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCachedGraphCard(
    BuildContext context,
    GraphSnapshot snapshot,
    bool isDark,
  ) {
    final daysUntilExpiry = snapshot.effectiveExpiresAt.difference(DateTime.now()).inDays;
    final isExpired = snapshot.isExpired;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Open graph in offline mode without making any external provider calls
          context.read<GraphCubit>().openCachedGraph(snapshot);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConnectedGraphView(initialSnapshot: snapshot),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? const Color(0xFFF59E0B).withAlpha(30)
                          : const Color(0xFF10B981).withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isExpired ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isExpired ? Icons.schedule_rounded : Icons.offline_pin_rounded,
                          size: 12,
                          color: isExpired ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isExpired
                              ? 'Expired Cache'
                              : 'Expires in ${daysUntilExpiry.clamp(0, 365)}d',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isExpired ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Schema v${snapshot.schemaVersion} • ${snapshot.algorithmVersion}',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                    tooltip: 'Remove Cached Graph',
                    onPressed: () {
                      context.read<LibraryCubit>().removeCachedGraph(snapshot.graphId);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Seed Paper Title
              Text(
                snapshot.origin.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.3),
              ),
              const SizedBox(height: 6),

              // Metadata counts
              Row(
                children: [
                  Icon(Icons.description_outlined, size: 14, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${snapshot.nodes.length} papers',
                    style: TextStyle(fontSize: 11.5, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.arrow_right_alt, size: 14, color: AppTheme.primaryLightBlue),
                  const SizedBox(width: 4),
                  Text(
                    '${snapshot.citationEdges.length} citations',
                    style: TextStyle(fontSize: 11.5, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.share_outlined, size: 14, color: AppTheme.accentCyan),
                  const SizedBox(width: 4),
                  Text(
                    '${snapshot.similarityEdges.length} similarities',
                    style: TextStyle(fontSize: 11.5, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Open Offline Graph CTA
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      context.read<GraphCubit>().openCachedGraph(snapshot);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConnectedGraphView(initialSnapshot: snapshot),
                        ),
                      );
                    },
                    icon: const Icon(Icons.hub_rounded, size: 15),
                    label: const Text('Open Graph Offline', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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

  // --- REUSABLE WIDGET HELPERS ---
  Widget _buildOfflineStatusBanner({
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.accentEmerald.withAlpha(25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accentEmerald.withAlpha(80)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: AppTheme.accentEmerald, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.accentEmerald,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primaryBlue.withAlpha(20),
              ),
              child: Icon(icon, size: 64, color: AppTheme.primaryLightBlue),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNotesDialog(BuildContext context, String paperId, String initialNote) {
    final controller = TextEditingController(text: initialNote);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: AppTheme.accentCyan),
            SizedBox(width: 8),
            Text('Research Notes'),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter your research notes, insights, or citations...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<LibraryCubit>().saveNotes(paperId, controller.text);
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Research notes saved to offline storage!'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
