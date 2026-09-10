import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/paper_model.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/papers_provider.dart';
import '../graph_view/connected_graph_view.dart';
import '../paper_details/citation_bottom_sheet.dart';
import '../paper_details/paper_details_view.dart';

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favoritesProvider = Provider.of<FavoritesProvider>(context);
    final papersProvider = Provider.of<PapersProvider>(context, listen: false);
    final favorites = favoritesProvider.favoritePapers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Offline Library (المفضلة)'),
      ),
      body: Column(
        children: [
          // Offline Hive Banner (Highlights doctor requirement)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      const Text(
                        'Hive Local Database Active',
                        style: TextStyle(
                          color: AppTheme.accentEmerald,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'All ${favorites.length} saved papers & personal notes are stored locally and accessible offline.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Papers List or Empty State
          Expanded(
            child: favorites.isEmpty
                ? Center(
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
                            child: const Icon(
                              Icons.bookmark_outline_rounded,
                              size: 64,
                              color: AppTheme.primaryLightBlue,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Your Library is Empty',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Save landmark research papers and notes by tapping the bookmark icon on any paper.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final paper = favorites[index];
                      return _buildFavoritePaperCard(context, paper, isDark, favoritesProvider, papersProvider);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoritePaperCard(
    BuildContext context,
    PaperModel paper,
    bool isDark,
    FavoritesProvider favoritesProvider,
    PapersProvider papersProvider,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaperDetailsView(paper: paper)),
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
                      paper.category,
                      style: const TextStyle(
                        color: AppTheme.primaryLightBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${paper.year}',
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
                    onPressed: () => favoritesProvider.toggleFavorite(paper, papersProvider),
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
                paper.authors.join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),

              // Personal notes indicator if present
              if (paper.personalNotes.isNotEmpty) ...[
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
                          paper.personalNotes,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
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
                          builder: (_) => ConnectedGraphView(centerPaper: paper),
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
                  IconButton(
                    icon: const Icon(Icons.format_quote_rounded, size: 20),
                    tooltip: 'Cite Paper',
                    onPressed: () => CitationBottomSheet.show(context, paper),
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
