import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/abstract_text_formatter.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/research_monitoring/research_monitoring_cubit.dart';
import '../../cubits/research_monitoring/research_monitoring_state.dart';
import '../../models/research_monitoring_models.dart';
import '../../models/paper_model.dart';
import '../graph_view/connected_graph_view.dart';
import '../paper_details/paper_details_view.dart';

class GraphUpdatesView extends StatelessWidget {
  final String localGraphId;
  final String graphTitle;

  const GraphUpdatesView({
    super.key,
    required this.localGraphId,
    required this.graphTitle,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ResearchMonitoringCubit(
        localGraphId: localGraphId,
        libraryCubit: context.read<LibraryCubit>(),
      )..load(),
      child: _GraphUpdatesScaffold(graphTitle: graphTitle),
    );
  }
}

enum _UpdateFilter { newItems, all, added }

class _GraphUpdatesScaffold extends StatefulWidget {
  final String graphTitle;

  const _GraphUpdatesScaffold({required this.graphTitle});

  @override
  State<_GraphUpdatesScaffold> createState() => _GraphUpdatesScaffoldState();
}

class _GraphUpdatesScaffoldState extends State<_GraphUpdatesScaffold> {
  _UpdateFilter _filter = _UpdateFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Research updates'),
        actions: [
          IconButton(
            tooltip: 'Refresh updates',
            onPressed: context.read<ResearchMonitoringCubit>().load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: BlocConsumer<ResearchMonitoringCubit, ResearchMonitoringState>(
        listener: (context, state) {
          final message = state.errorMessage;
          if (message == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppTheme.accentRose,
            ),
          );
        },
        builder: (context, state) {
          if (state.isLoading && state.monitoring == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null && state.monitoring == null) {
            return _ErrorView(
              message: state.errorMessage!,
              onRetry: context.read<ResearchMonitoringCubit>().load,
            );
          }
          if (state.isNotMonitoring) {
            return _NotMonitoringView(graphTitle: widget.graphTitle);
          }

          final visibleUpdates = _visibleUpdates(state.updates);
          return RefreshIndicator(
            onRefresh: context.read<ResearchMonitoringCubit>().load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _MonitoringHeader(
                  monitoring: state.monitoring!,
                  unreadCount: state.unreadCount,
                  isActing: state.isActing,
                  onPauseResume: () => context
                      .read<ResearchMonitoringCubit>()
                      .setPaused(!state.monitoring!.isPaused),
                  onStop: () => _confirmStop(context),
                ),
                const SizedBox(height: 18),
                _UpdateFilterBar(
                  filter: _filter,
                  totalCount: state.updates.length,
                  unreadCount: state.unreadCount,
                  addedCount: state.updates
                      .where((update) => update.isAddedToGraph)
                      .length,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 12),
                if (visibleUpdates.isEmpty)
                  _EmptyUpdatesView(filter: _filter)
                else
                  ...visibleUpdates.map(
                    (update) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ResearchUpdateCard(
                        update: update,
                        onInspect: () => _showUpdateDetails(context, update),
                        onAdd: () => _confirmAdd(context, update),
                        onOpen: () => _openPaperDetails(context, update),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<ResearchUpdate> _visibleUpdates(List<ResearchUpdate> updates) {
    switch (_filter) {
      case _UpdateFilter.newItems:
        return updates.where((update) => !update.isRead).toList();
      case _UpdateFilter.all:
        return updates;
      case _UpdateFilter.added:
        return updates.where((update) => update.isAddedToGraph).toList();
    }
  }

  Future<void> _confirmAdd(BuildContext context, ResearchUpdate update) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add paper to this graph?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(update.title, maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              const Text(
                'PaperGraph will add one node, preserve the current layout, '
                'and connect it when the scanner has a known relationship.',
                style: TextStyle(height: 1.35),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final added = await context.read<ResearchMonitoringCubit>().addToGraph(
      update,
    );
    if (!context.mounted || !added) return;

    final snapshot = context.read<LibraryCubit>().getCachedGraph(
      context.read<ResearchMonitoringCubit>().localGraphId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Paper added to the saved graph.'),
        action: snapshot == null
            ? null
            : SnackBarAction(
                label: 'View graph',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        ConnectedGraphView(initialSnapshot: snapshot),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _showUpdateDetails(
    BuildContext context,
    ResearchUpdate update,
  ) async {
    if (!update.isRead) {
      await context.read<ResearchMonitoringCubit>().markRead(update);
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final secondary = isDark
            ? AppTheme.darkTextSecondary
            : AppTheme.lightTextSecondary;
        final preview = update.abstractText?.trim().isNotEmpty == true
            ? abstractPreview(update.abstractText!)
            : null;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          update.title,
                          style: const TextStyle(
                            fontSize: 19,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(
                              icon: Icons.link_rounded,
                              label: _ResearchUpdateCard._relationLabel(
                                update.relationType,
                              ),
                            ),
                            _InfoChip(
                              icon: Icons.auto_awesome_rounded,
                              label:
                                  '${(update.relevanceScore * 100).round()}% relevant',
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          update.explanation,
                          style: TextStyle(color: secondary, height: 1.45),
                        ),
                        if (preview != null) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Abstract preview',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            abstractPreview(
                              update.abstractText!,
                              maxCharacters: 300,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondary,
                              height: 1.45,
                              fontSize: 13.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _UpdateDetailsActions(
                  isAdded: update.isAddedToGraph,
                  onOpenPaper: () {
                    Navigator.pop(sheetContext);
                    _openPaperDetails(context, update);
                  },
                  onAdd: update.isAddedToGraph
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          _confirmAdd(context, update);
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openPaperDetails(BuildContext context, ResearchUpdate update) {
    final paper = PaperModel(
      id: update.canonicalPaperId,
      title: update.title,
      authors: const [],
      abstractText: update.abstractText ?? '',
      category: '',
      year: update.publishedAt?.year ?? DateTime.now().year,
      citationsCount: 0,
      influentialCitations: 0,
      connectedPaperIds: const [],
      pdfUrl: '',
      journal: '',
      doi: update.doi ?? '',
      keyTakeaways: const [],
    );
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => PaperDetailsView(paper: paper)));
  }

  Future<void> _confirmStop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Stop research updates?'),
        content: const Text(
          'New papers will no longer be checked for this graph. Your saved graph will remain on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep monitoring'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRose),
            child: const Text('Stop updates'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final stopped = await context
          .read<ResearchMonitoringCubit>()
          .stopMonitoring();
      if (stopped && context.mounted) Navigator.pop(context);
    }
  }
}

class _UpdateDetailsActions extends StatelessWidget {
  final bool isAdded;
  final VoidCallback onOpenPaper;
  final VoidCallback? onAdd;

  const _UpdateDetailsActions({
    required this.isAdded,
    required this.onOpenPaper,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withAlpha(90),
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 370;
            final openButton = OutlinedButton.icon(
              onPressed: onOpenPaper,
              icon: const Icon(Icons.article_outlined, size: 17),
              label: const Text('Paper details'),
            );
            final addButton = FilledButton.icon(
              onPressed: onAdd,
              icon: Icon(
                isAdded ? Icons.check_rounded : Icons.add_rounded,
                size: 17,
              ),
              label: Text(isAdded ? 'Added' : 'Add to graph'),
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [openButton, const SizedBox(height: 8), addButton],
              );
            }

            return Row(
              children: [
                Expanded(child: openButton),
                const SizedBox(width: 10),
                Expanded(child: addButton),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MonitoringHeader extends StatelessWidget {
  final MonitoredGraphSummary monitoring;
  final int unreadCount;
  final bool isActing;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;

  const _MonitoringHeader({
    required this.monitoring,
    required this.unreadCount,
    required this.isActing,
    required this.onPauseResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final isPaused = monitoring.isPaused;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
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
                        isPaused
                            ? Icons.pause_rounded
                            : Icons.track_changes_rounded,
                        size: 20,
                        color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                      ),
                    ),
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isPaused
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF161618)
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        monitoring.graphTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isPaused
                            ? 'Research updates are paused'
                            : 'Research updates are on',
                        style: TextStyle(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unreadCount > 0) _CountBadge(count: unreadCount),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              isPaused
                  ? 'Resume when you want PaperGraph to check this graph again.'
                  : 'We check for relevant papers on a ${monitoring.frequency} schedule.',
              style: TextStyle(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isActing ? null : onPauseResume,
                    icon: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 18,
                    ),
                    label: Text(isPaused ? 'Resume' : 'Pause'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Stop monitoring',
                  onPressed: isActing ? null : onStop,
                  icon: const Icon(Icons.notifications_off_outlined, size: 19),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateFilterBar extends StatelessWidget {
  final _UpdateFilter filter;
  final int totalCount;
  final int unreadCount;
  final int addedCount;
  final ValueChanged<_UpdateFilter> onChanged;

  const _UpdateFilterBar({
    required this.filter,
    required this.totalCount,
    required this.unreadCount,
    required this.addedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$totalCount total updates · $unreadCount new',
          style: TextStyle(
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip('New', unreadCount, _UpdateFilter.newItems),
              const SizedBox(width: 8),
              _chip('All', totalCount, _UpdateFilter.all),
              const SizedBox(width: 8),
              _chip('Added', addedCount, _UpdateFilter.added),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, int count, _UpdateFilter value) {
    return ChoiceChip(
      label: Text('$label $count'),
      selected: filter == value,
      onSelected: (_) => onChanged(value),
    );
  }
}

class _ResearchUpdateCard extends StatelessWidget {
  final ResearchUpdate update;
  final VoidCallback onInspect;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  const _ResearchUpdateCard({
    required this.update,
    required this.onInspect,
    required this.onAdd,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = update.isRead
        ? (isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary)
        : AppTheme.primaryBlue;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onInspect,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accent, width: update.isRead ? 2 : 4),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      update.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.28,
                        fontWeight: update.isRead
                            ? FontWeight.w600
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ScoreBadge(score: update.relevanceScore),
                ],
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _InfoChip(
                    icon: Icons.link_rounded,
                    label: _relationLabel(update.relationType),
                  ),
                  _InfoChip(
                    icon: Icons.schedule_rounded,
                    label: _formatDate(update.publishedAt ?? update.detectedAt),
                  ),
                ],
              ),
              if (update.explanation.isNotEmpty) ...[
                const SizedBox(height: 11),
                Text(
                  update.explanation,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
              if (update.abstractText?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  abstractPreview(update.abstractText!, maxCharacters: 180),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('Paper details'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: update.isAddedToGraph ? null : onAdd,
                      icon: Icon(
                        update.isAddedToGraph
                            ? Icons.check_rounded
                            : Icons.add_rounded,
                        size: 17,
                      ),
                      label: Text(
                        update.isAddedToGraph ? 'Added' : 'Add to graph',
                      ),
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

  static String _relationLabel(String relationType) {
    switch (relationType) {
      case 'direct_citation':
        return 'Direct citation';
      case 'shared_references':
        return 'Shared references';
      case 'semantic_similarity':
        return 'Semantic similarity';
      case 'related_recommendation':
        return 'Related recommendation';
      case 'same_topic':
        return 'Same topic';
      default:
        return 'Related research';
    }
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year}';
  }
}

class _ScoreBadge extends StatelessWidget {
  final double score;

  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE5E5EA),
          width: 0.5,
        ),
      ),
      child: Text(
        '${(score * 100).round()}% match',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyUpdatesView extends StatelessWidget {
  final _UpdateFilter filter;

  const _EmptyUpdatesView({required this.filter});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final filterLabel = switch (filter) {
      _UpdateFilter.newItems => 'new',
      _UpdateFilter.all => 'all',
      _UpdateFilter.added => 'added',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 54),
      child: Column(
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: 48,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          const SizedBox(height: 16),
          const Text(
            'No updates in this view',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            filter == _UpdateFilter.all
                ? 'We will show an update here when the scanner finds research connected to this graph.'
                : 'There are no $filterLabel updates to show right now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: secondary, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _NotMonitoringView extends StatelessWidget {
  final String graphTitle;

  const _NotMonitoringView({required this.graphTitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_off_outlined, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Research updates are off',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Monitoring is not active for “$graphTitle”. Saving the graph again while signed in will start monitoring.',
              textAlign: TextAlign.center,
              style: TextStyle(color: secondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
