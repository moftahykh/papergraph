import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_theme.dart';
import '../../cubits/research_monitoring/research_monitoring_cubit.dart';
import '../../cubits/research_monitoring/research_monitoring_state.dart';
import '../../models/research_monitoring_models.dart';
import '../../core/utils/paper_url_helper.dart';

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
      create: (_) => ResearchMonitoringCubit(localGraphId: localGraphId)..load(),
      child: _GraphUpdatesScaffold(graphTitle: graphTitle),
    );
  }
}

class _GraphUpdatesScaffold extends StatelessWidget {
  final String graphTitle;

  const _GraphUpdatesScaffold({required this.graphTitle});

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
            return _NotMonitoringView(graphTitle: graphTitle);
          }

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
                if (state.updates.isEmpty)
                  const _EmptyUpdatesView()
                else
                  ...state.updates.map(
                    (update) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ResearchUpdateCard(
                        update: update,
                        onRead: () => context
                            .read<ResearchMonitoringCubit>()
                            .markRead(update),
                        onAdd: () => context
                            .read<ResearchMonitoringCubit>()
                            .addToGraph(update),
                        onOpen: () => _openPaper(context, update),
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

  void _openPaper(BuildContext context, ResearchUpdate update) {
    final url = PaperUrlHelper.resolvePaperUrl(
      doi: update.doi,
      canonicalId: update.canonicalPaperId,
      title: update.title,
    );
    PaperUrlHelper.launchPaper(context, url: url, title: update.title);
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
    final accent = isPaused ? AppTheme.accentAmber : AppTheme.accentEmerald;

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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(24),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPaused
                        ? Icons.pause_circle_outline_rounded
                        : Icons.track_changes_rounded,
                    color: accent,
                  ),
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
                if (unreadCount > 0)
                  _CountBadge(count: unreadCount, color: accent),
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
                      isPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
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

class _ResearchUpdateCard extends StatelessWidget {
  final ResearchUpdate update;
  final VoidCallback onRead;
  final VoidCallback onAdd;
  final VoidCallback onOpen;

  const _ResearchUpdateCard({
    required this.update,
    required this.onRead,
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
        onTap: update.isRead ? null : onRead,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: accent,
                width: update.isRead ? 2 : 4,
              ),
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
                  update.abstractText!,
                  maxLines: 3,
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
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Open paper'),
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
              if (!update.isRead)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onRead,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Mark as read'),
                  ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.accentEmerald.withAlpha(22),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${(score * 100).round()}%',
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.accentEmerald,
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
  final Color color;

  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyUpdatesView extends StatelessWidget {
  const _EmptyUpdatesView();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
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
            'No new relevant papers yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'We will show an update here when the scanner finds research connected to this graph.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: secondary,
              fontSize: 13,
              height: 1.45,
            ),
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