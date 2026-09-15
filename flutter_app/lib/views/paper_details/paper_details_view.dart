import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/paper_url_helper.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/paper_details/paper_details_cubit.dart';
import '../../cubits/paper_details/paper_details_state.dart';
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

    // Fetch deep metadata if not already loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final current = context.read<PaperDetailsCubit>().state;
        if (current is! PaperDetailsLoaded || current.details.paper.canonicalId != widget.paper.id) {
          context.read<PaperDetailsCubit>().loadDetails(widget.paper.id);
        }
      }
    });
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

    return BlocBuilder<PaperDetailsCubit, PaperDetailsState>(
      builder: (context, detailsState) {
        // Derive dynamic metadata if loaded from backend
        String effectiveTitle = widget.paper.title;
        List<String> effectiveAuthors = widget.paper.authors;
        int effectiveYear = widget.paper.year;
        String effectiveVenue = widget.paper.journal;
        String effectiveAbstract = widget.paper.abstractText;
        int effectiveCitations = widget.paper.citationsCount;
        String effectiveDoi = widget.paper.doi;
        String? openAccessUrl;
        String? tldr;
        bool isLoadingDetails = false;

        if (detailsState is PaperDetailsLoading && detailsState.paperId == widget.paper.id) {
          isLoadingDetails = true;
        } else if (detailsState is PaperDetailsLoaded &&
            detailsState.details.paper.canonicalId == widget.paper.id) {
          final loaded = detailsState.details;
          if (loaded.paper.title.isNotEmpty) effectiveTitle = loaded.paper.title;
          if (loaded.paper.authors.isNotEmpty) {
            effectiveAuthors = loaded.paper.authors.map((a) => a.name).toList();
          }
          if (loaded.paper.year != null) effectiveYear = loaded.paper.year!;
          if (loaded.paper.venue != null && loaded.paper.venue!.isNotEmpty) {
            effectiveVenue = loaded.paper.venue!;
          }
          if (loaded.paper.abstractText != null && loaded.paper.abstractText!.isNotEmpty) {
            effectiveAbstract = loaded.paper.abstractText!;
          }
          if (loaded.paper.citationCount > 0) {
            effectiveCitations = loaded.paper.citationCount;
          }
          if (loaded.paper.doi != null && loaded.paper.doi!.isNotEmpty) {
            effectiveDoi = loaded.paper.doi!;
          }
          openAccessUrl = loaded.openAccessUrl;
          tldr = loaded.tldr;
        }

        final resolvedUrl = PaperUrlHelper.resolvePaperUrl(
          openAccessUrl: openAccessUrl,
          pdfUrl: widget.paper.pdfUrl,
          doi: effectiveDoi,
          canonicalId: widget.paper.id,
          title: effectiveTitle,
        );

        final dynamicPaperModel = widget.paper.copyWith(
          title: effectiveTitle,
          authors: effectiveAuthors,
          year: effectiveYear,
          journal: effectiveVenue,
          abstractText: effectiveAbstract,
          citationsCount: effectiveCitations,
          doi: effectiveDoi,
        );

        return Scaffold(
          appBar: AppBar(
            title: const FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Research Paper Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            actions: [
              // Direct external paper link action
              if (resolvedUrl.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.open_in_new_rounded),
                  tooltip: 'Open Original Paper in Browser',
                  onPressed: () => PaperUrlHelper.launchPaper(
                    context,
                    url: resolvedUrl,
                    title: effectiveTitle,
                  ),
                ),
              IconButton(
                icon: Icon(
                  isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: isFav ? AppTheme.accentAmber : null,
                ),
                tooltip: isFav ? 'Remove from Library' : 'Save to Library (Hive)',
                onPressed: () {
                  final canonical = _toCanonicalPaper(dynamicPaperModel);
                  context.read<LibraryCubit>().toggleSavePaper(canonical);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isFav
                            ? 'Removed from Library'
                            : 'Saved to Library for offline reading!',
                      ),
                      duration: const Duration(seconds: 1),
                      backgroundColor: isFav ? AppTheme.accentAmber : AppTheme.accentEmerald,
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.format_quote_rounded),
                tooltip: 'Export Citation',
                onPressed: () => CitationBottomSheet.show(context, dynamicPaperModel),
              ),
            ],
          ),
          body: Column(
            children: [
              if (isLoadingDetails)
                const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryLightBlue),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Responsive Badges (Category, Year, Citations)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryBlue.withAlpha(25),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.paper.category.isNotEmpty ? widget.paper.category : 'Research Paper',
                              style: const TextStyle(
                                color: AppTheme.primaryLightBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.darkSurface : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Published $effectiveYear',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.accentEmerald.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.show_chart_rounded, size: 14, color: AppTheme.accentEmerald),
                                const SizedBox(width: 4),
                                Text(
                                  '$effectiveCitations citations',
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
                        effectiveTitle,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Authors
                      if (effectiveAuthors.isNotEmpty)
                        Text(
                          effectiveAuthors.join(' • '),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                          ),
                        ),
                      const SizedBox(height: 6),

                      // Journal & DOI (clean formatting without empty labels)
                      if (effectiveVenue.isNotEmpty || effectiveDoi.isNotEmpty) ...[
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            if (effectiveVenue.isNotEmpty)
                              Text(
                                effectiveVenue,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary.withAlpha(180)
                                      : AppTheme.lightTextSecondary,
                                ),
                              ),
                            if (effectiveDoi.isNotEmpty)
                              InkWell(
                                onTap: () => PaperUrlHelper.launchPaper(
                                  context,
                                  url: PaperUrlHelper.resolvePaperUrl(
                                    doi: effectiveDoi,
                                    title: effectiveTitle,
                                  ),
                                  title: effectiveTitle,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.link_rounded, size: 13, color: AppTheme.primaryLightBlue),
                                      const SizedBox(width: 3),
                                      Flexible(
                                        child: Text(
                                          'DOI: $effectiveDoi',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.primaryLightBlue,
                                            decoration: TextDecoration.underline,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                      ],

                      // ACTION BUTTONS (Read Paper / PDF & Explore Graph)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            PaperUrlHelper.launchPaper(
                              context,
                              url: resolvedUrl,
                              title: effectiveTitle,
                            );
                          },
                          icon: const Icon(Icons.open_in_browser_rounded, size: 20),
                          label: const Text(
                            'Read Original Paper / PDF',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            backgroundColor: AppTheme.accentEmerald,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ConnectedGraphView(centerPaper: dynamicPaperModel),
                              ),
                            );
                          },
                          icon: const Icon(Icons.hub_rounded, size: 20),
                          label: const Text(
                            'Explore Connected Papers Graph',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            foregroundColor: AppTheme.primaryLightBlue,
                            side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // TL;DR Section (if available)
                      if (tldr != null && tldr.isNotEmpty) ...[
                        _buildSectionHeader('TL;DR Summary', Icons.auto_awesome_rounded),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withAlpha(20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.primaryBlue.withAlpha(60)),
                          ),
                          child: Text(
                            tldr,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.5,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                      ],

                      // Key Takeaways Section
                      if (widget.paper.keyTakeaways.isNotEmpty) ...[
                        _buildSectionHeader('Key Takeaways & Core Findings', Icons.lightbulb_outline_rounded),
                        const SizedBox(height: 10),
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
                        const SizedBox(height: 22),
                      ],

                      // Abstract Section
                      _buildSectionHeader('Abstract', Icons.description_outlined),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                        ),
                        child: (effectiveAbstract.isNotEmpty && !effectiveAbstract.contains('Synthesized node from PaperGraph'))
                            ? Text(
                                effectiveAbstract,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.7,
                                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                ),
                              )
                            : isLoadingDetails
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                isDark ? const Color(0xFF38BDF8) : AppTheme.primaryBlue,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Retrieving full abstract from academic providers…',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontStyle: FontStyle.italic,
                                                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline_rounded,
                                            size: 16,
                                            color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Publisher Abstract Unavailable via Open Access',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'The full abstract is not provided openly by the upstream repository. You can read the original work and full publication directly via the publisher link.',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          height: 1.5,
                                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                      ),
                      const SizedBox(height: 22),

                      // Personal Research Notes (Saved to Hive)
                      _buildSectionHeader('Private Researcher Notes (Stored Offline)', Icons.edit_note_rounded),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.darkCard : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? AppTheme.darkSurface : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder.withAlpha(100),
                                ),
                              ),
                              child: TextField(
                                controller: _notesController,
                                maxLines: 4,
                                minLines: 2,
                                decoration: InputDecoration(
                                  hintText: 'Add personal study notes, insights, or citation references...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  hintStyle: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                onPressed: _saveNotes,
                                icon: const Icon(Icons.save_rounded, size: 16),
                                label: const Text('Save Note'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.primaryBlue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Connected Papers Previews
                      _buildSectionHeader(
                        'Connected Papers in This Network (${connectedPapers.length})',
                        Icons.hub_rounded,
                      ),
                      const SizedBox(height: 10),
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
                              '${cp.authors.isNotEmpty ? cp.authors.first : "Author"} et al. (${cp.year}) • ${cp.citationsCount} citations',
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
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Strictly responsive section header with Expanded to prevent RenderFlex horizontal overflows
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryLightBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
