import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/library/library_cubit.dart';
import '../../models/canonical_paper.dart';
import '../../models/paper_model.dart';
import '../../providers/papers_provider.dart';
import '../graph_view/connected_graph_view.dart';
import 'citation_bottom_sheet.dart';

class PaperDetailsView extends StatefulWidget {
  final PaperModel paper;

  const PaperDetailsView({super.key, required this.paper});

  @override
  State<PaperDetailsView> createState() => _PaperDetailsViewState();
}

class _PaperDetailsViewState extends State<PaperDetailsView> {
  late TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final savedNote = HiveService.getPersonalNotes(widget.paper.id);
    _notesController = TextEditingController(
      text: savedNote.isNotEmpty ? savedNote : widget.paper.personalNotes,
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _saveNotes() {
    context.read<LibraryCubit>().saveNotes(widget.paper.id, _notesController.text);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Research notes saved to local storage!'),
        backgroundColor: AppTheme.accentEmerald,
        duration: Duration(seconds: 1),
      ),
    );
  }

  CanonicalPaper _toCanonicalPaper(PaperModel model) {
    return CanonicalPaper(
      canonicalId: model.id,
      title: model.title,
      normalizedTitle: model.title.toLowerCase(),
      authors: model.authors.map((a) => Author(name: a)).toList(),
      year: model.year,
      venue: model.journal,
      abstractText: model.abstractText,
      citationCount: model.citationsCount,
      referenceCount: 0,
      doi: model.doi.isNotEmpty ? model.doi : null,
      topics: [model.category],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final papersProvider = context.read<PapersProvider>();
    final isFav = context.select<LibraryCubit, bool>(
      (c) => c.isPaperSaved(widget.paper.id),
    );
    final connectedPapers = papersProvider.getConnectedPapers(widget.paper);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Research Paper Details'),
        actions: [
          IconButton(
            icon: Icon(
              isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              color: isFav ? AppTheme.accentAmber : null,
            ),
            tooltip: isFav ? 'Remove from Library' : 'Save to Library (Hive)',
            onPressed: () {
              final canonical = _toCanonicalPaper(widget.paper);
              context.read<LibraryCubit>().toggleSavePaper(canonical);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isFav ? 'Removed from Library' : 'Saved to Library for offline reading!'),
                  duration: const Duration(seconds: 1),
                  backgroundColor: isFav ? AppTheme.accentAmber : AppTheme.accentEmerald,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.format_quote_rounded),
            tooltip: 'Export Citation',
            onPressed: () => CitationBottomSheet.show(context, widget.paper),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category & Year Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.paper.category,
                    style: const TextStyle(
                      color: AppTheme.primaryLightBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Published ${widget.paper.year}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accentEmerald.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.show_chart_rounded, size: 14, color: AppTheme.accentEmerald),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.paper.citationsCount} citations',
                        style: const TextStyle(
                          color: AppTheme.accentEmerald,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              widget.paper.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 12),

            // Authors
            Text(
              widget.paper.authors.join(' • '),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 6),

            // Journal / Conference & DOI
            Text(
              '${widget.paper.journal} (DOI: ${widget.paper.doi})',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? AppTheme.darkTextSecondary.withAlpha(180) : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 24),

            // 🌟 Creative Feature Button: Explore Connected Graph
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryBlue, AppTheme.accentCyan],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryLightBlue.withAlpha(80),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConnectedGraphView(centerPaper: widget.paper),
                    ),
                  );
                },
                icon: const Icon(Icons.hub_rounded, color: Colors.white, size: 24),
                label: const Text(
                  'Explore Connected Papers Graph',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Key Takeaways Section
            _buildSectionHeader('Key Takeaways & Core Findings', Icons.lightbulb_outline_rounded),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Column(
                children: widget.paper.keyTakeaways.map((takeaway) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppTheme.accentEmerald,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            takeaway,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.4,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),

            // Abstract Section
            _buildSectionHeader('Abstract', Icons.description_outlined),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Text(
                widget.paper.abstractText,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Personal Research Notes (Saved to Hive)
            _buildSectionHeader('Private Researcher Notes (Stored Offline)', Icons.edit_note_rounded),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add personal study notes, insights, or citation references...',
                      border: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _saveNotes,
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save Note to Local Hive'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Connected Papers Previews
            _buildSectionHeader(
              'Connected Papers in This Network (${connectedPapers.length})',
              Icons.hub_rounded,
            ),
            const SizedBox(height: 12),
            ...connectedPapers.map((cp) {
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accentCyan.withAlpha(30),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.science_rounded, color: AppTheme.accentCyan, size: 20),
                  ),
                  title: Text(
                    cp.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${cp.authors.first} et al. (${cp.year}) • ${cp.citationsCount} citations',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PaperDetailsView(paper: cp)),
                    );
                  },
                ),
              );
            }),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryLightBlue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
