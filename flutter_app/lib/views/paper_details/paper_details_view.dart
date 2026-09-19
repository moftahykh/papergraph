import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/abstract_text_formatter.dart';
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
  final bool loadDetailsOnOpen;

  const PaperDetailsView({
    super.key,
    required this.paper,
    this.loadDetailsOnOpen = true,
  });

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
    if (widget.loadDetailsOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final current = context.read<PaperDetailsCubit>().state;
          if (current is! PaperDetailsLoaded ||
              current.details.paper.canonicalId != widget.paper.id) {
            context.read<PaperDetailsCubit>().loadDetails(widget.paper.id);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    final saved = await context
        .read<LibraryCubit>()
        .saveNotes(widget.paper.id, _notesController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Notes saved' : 'Notes could not be saved. Try again.',
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
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
          if (loaded.paper.year != null) {
            effectiveYear = loaded.paper.year!;
          }
          if (loaded.paper.venue != null && loaded.paper.venue!.isNotEmpty) {
            effectiveVenue = loaded.paper.venue!;
          }
          if (loaded.paper.abstractText != null && loaded.paper.abstractText!.isNotEmpty) {
            effectiveAbstract = loaded.paper.abstractText!;
          }
          // The details endpoint is authoritative for this paper. A provider
          // can legitimately confirm zero citations, so do not keep the
          // graph snapshot's fallback value when the loaded value is zero.
          effectiveCitations = loaded.paper.citationCount;
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
        final visibleAuthors = effectiveAuthors.length > 8
            ? '${effectiveAuthors.take(8).join(' • ')} + ${effectiveAuthors.length - 8} more'
            : effectiveAuthors.join(' • ');

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Paper',
              style: AppTheme.brandTitleStyle(
                fontSize: 27,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : AppTheme.lightTextPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: isFav ? AppTheme.accentAmber : null,
                ),
                tooltip: isFav ? 'Remove from library' : 'Save to library',
                onPressed: () async {
                  final wasSaved = isFav;
                  final succeeded = await context
                      .read<LibraryCubit>()
                      .toggleSavePaper(_toCanonicalPaper(dynamicPaperModel));
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        succeeded
                            ? (wasSaved
                                ? 'Removed from library'
                                : 'Saved to library')
                            : 'Your change could not be saved. Try again.',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share paper',
                onPressed: () async {
                  final shareText = resolvedUrl.isNotEmpty
                      ? resolvedUrl
                      : (effectiveDoi.isNotEmpty
                          ? 'https://doi.org/$effectiveDoi'
                          : effectiveTitle);
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Paper link copied')),
                  );
                },
              ),
              PopupMenuButton<String>(
                tooltip: 'More options',
                onSelected: (value) {
                  if (value == 'citation') {
                    CitationBottomSheet.show(context, dynamicPaperModel);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'citation',
                    child: Row(
                      children: [
                        Icon(Icons.format_quote_rounded, size: 18),
                        SizedBox(width: 10),
                        Text('Export citation'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (isLoadingDetails)
                const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (widget.paper.category.isNotEmpty)
                            _buildMetadataItem(
                              Icons.category_outlined,
                              widget.paper.category,
                              isDark,
                            ),
                          _buildMetadataItem(
                            Icons.calendar_today_outlined,
                            '$effectiveYear',
                            isDark,
                          ),
                          _buildMetadataItem(
                            Icons.format_quote_rounded,
                            '$effectiveCitations citations',
                            isDark,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        effectiveTitle,
                        style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          height: 1.22,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if (effectiveAuthors.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          visibleAuthors,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                      if (effectiveVenue.isNotEmpty || effectiveDoi.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            if (effectiveVenue.isNotEmpty)
                              Text(
                                effectiveVenue,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppTheme.darkTextSecondary
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
                                child: Text(
                                  'DOI: $effectiveDoi',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: isDark
                                        ? AppTheme.primaryLightBlue
                                        : AppTheme.primaryBlue,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ConnectedGraphView(
                                  centerPaper: dynamicPaperModel,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.account_tree_outlined,
                            size: 19,
                          ),
                          label: const Text(
                            'Explore graph',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: isDark
                                ? Colors.white
                                : const Color(0xFF18181B),
                            foregroundColor: isDark
                                ? const Color(0xFF09090B)
                                : Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: resolvedUrl.isEmpty
                              ? null
                              : () => PaperUrlHelper.launchPaper(
                                    context,
                                    url: resolvedUrl,
                                    title: effectiveTitle,
                                  ),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: const Text('Read paper'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      if (tldr != null && tldr.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _buildSectionHeader(
                          'Quick summary',
                          Icons.auto_awesome_rounded,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppTheme.actionPurple.withAlpha(24)
                                : const Color(0xFFF3F1FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.actionPurple.withAlpha(55),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Summary',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? AppTheme.actionPurpleDark
                                      : AppTheme.actionPurple,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                tldr,
                                style: const TextStyle(
                                  fontSize: 15,
                                  height: 1.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      _buildSectionHeader('Abstract', Icons.description_outlined),
                      const SizedBox(height: 10),
                      if (effectiveAbstract.isNotEmpty &&
                          !effectiveAbstract.contains(
                            'Synthesized node from PaperGraph',
                          ))
                        FormattedAbstract(
                          text: effectiveAbstract,
                          bodyStyle: const TextStyle(
                            fontSize: 15.5,
                            height: 1.7,
                          ),
                        )
                      else if (isLoadingDetails)
                        Text(
                          'Retrieving the full abstract…',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        )
                      else
                        Text(
                          'The abstract is not available from the current source. Open the paper to read the full publication.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.55,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      const SizedBox(height: 24),
                      _buildExpandableSection(
                        title: 'My notes',
                        icon: Icons.edit_note_rounded,
                        isDark: isDark,
                        children: [
                          TextField(
                            controller: _notesController,
                            minLines: 3,
                            maxLines: 6,
                            decoration: const InputDecoration(
                              hintText: 'Add an insight, question, or citation note…',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _saveNotes,
                              icon: const Icon(Icons.save_outlined, size: 17),
                              label: const Text('Save note'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildExpandableSection(
                        title: 'Citations ($effectiveCitations)',
                        icon: Icons.format_quote_rounded,
                        isDark: isDark,
                        children: [
                          Text(
                            '$effectiveCitations citations are recorded for this paper.',
                            style: TextStyle(
                              color: isDark
                                  ? AppTheme.darkTextSecondary
                                  : AppTheme.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => CitationBottomSheet.show(
                              context,
                              dynamicPaperModel,
                            ),
                            icon: const Icon(Icons.copy_rounded, size: 17),
                            label: const Text('Export citation'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildExpandableSection(
                        title: 'Connected papers (${connectedPapers.length})',
                        icon: Icons.account_tree_outlined,
                        isDark: isDark,
                        children: connectedPapers.isEmpty
                            ? [
                                Text(
                                  'No connected papers are stored for this paper yet.',
                                  style: TextStyle(
                                    color: isDark
                                        ? AppTheme.darkTextSecondary
                                        : AppTheme.lightTextSecondary,
                                  ),
                                ),
                              ]
                            : connectedPapers
                                .map(
                                  (paper) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      paper.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${paper.year} • ${paper.citationsCount} citations',
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PaperDetailsView(
                                          paper: paper,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
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

  Widget _buildMetadataItem(
    IconData icon,
    String label,
    bool isDark,
  ) {
    final color = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableSection({
    required String title,
    IconData? icon,
    Widget? customLeading,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: customLeading ??
              Icon(
                icon,
                size: 20,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Strictly responsive section header with Expanded to prevent RenderFlex horizontal overflows
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).brightness == Brightness.dark
              ? AppTheme.primaryLightBlue
              : AppTheme.primaryBlue,
        ),
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
