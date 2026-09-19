import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../widgets/paper_graph_mark.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../cubits/graph/graph_cubit.dart';
import '../../../cubits/graph/graph_state.dart';
import '../../../models/graph_job_status.dart';

extension GraphJobStatusDisplay on GraphJobStatus {
  String get displayTitle {
    switch (this) {
      case GraphJobStatus.queued:
        return 'Queueing graph task...';
      case GraphJobStatus.resolvingOrigin:
        return 'Resolving seed paper identity...';
      case GraphJobStatus.generatingCandidates:
        return 'Generating candidate literature pool...';
      case GraphJobStatus.preRanking:
        return 'Applying PreScore quotas...';
      case GraphJobStatus.enrichingMetadata:
        return 'Enriching canonical paper metadata...';
      case GraphJobStatus.enrichingReferences:
        return 'Harvesting foundational references...';
      case GraphJobStatus.computingWbc:
        return 'Comparing shared references…';
      case GraphJobStatus.enrichingCitations:
        return 'Harvesting derivative citations...';
      case GraphJobStatus.computingNcc:
        return 'Analyzing co-citation patterns…';
      case GraphJobStatus.computingFinalScores:
        return 'Ranking papers by relevance…';
      case GraphJobStatus.extractingPriorWorks:
        return 'Extracting foundational prior works...';
      case GraphJobStatus.extractingDerivativeWorks:
        return 'Extracting subsequent derivative works...';
      case GraphJobStatus.buildingLayout:
        return 'Synthesizing deterministic 2D graph layout...';
      case GraphJobStatus.completed:
        return 'Graph generation complete';
      case GraphJobStatus.partial:
        return 'Graph generated with partial coverage';
      case GraphJobStatus.failed:
        return 'Graph generation failed';
    }
  }
}

class GraphProgressiveLoadingView extends StatefulWidget {
  final GraphState state;
  final bool isDark;

  const GraphProgressiveLoadingView({
    super.key,
    required this.state,
    required this.isDark,
  });

  @override
  State<GraphProgressiveLoadingView> createState() =>
      _GraphProgressiveLoadingViewState();
}

class _GraphProgressiveLoadingViewState
    extends State<GraphProgressiveLoadingView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    GraphJobStatus currentStage = GraphJobStatus.queued;
    double progress = 0.05;

    final state = widget.state;
    final isDark = widget.isDark;

    if (state is GraphPolling) {
      currentStage = state.currentStage;
      progress = state.progress.clamp(0.05, 0.98);
    }

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(isDark ? 140 : 30),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return PaperGraphMark(
                      size: 130,
                      isDark: isDark,
                      pulse: _pulseController.value,
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Synthesizing Literature Graph',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppTheme.darkTextPrimary
                        : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currentStage.displayTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppTheme.accentCyan
                        : const Color(0xFF0284C7),
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? AppTheme.darkSurface
                        : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? AppTheme.accentCyan : AppTheme.primaryBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(progress * 100).toInt()}% completed',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'You can leave this screen. We’ll keep building your graph.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.explore_outlined, size: 18),
                    label: const Text('Continue exploring'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    context.read<GraphCubit>().cancel();
                    Navigator.of(context).maybePop();
                  },
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text(
                    'Stop tracking',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                  ),
                ),
                if (state is GraphPolling) ...[
                  const SizedBox(height: 12),
                  _buildNotificationOptIn(state.graphId, isDark),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationOptIn(String graphId, bool isDark) {
    final isEnabled = LocalNotificationService.isGraphNotificationEnabled(
      graphId,
    );

    if (isEnabled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF10B981),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Notification enabled when ready',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white70 : const Color(0xFF1C1C1E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return TextButton.icon(
      onPressed: () async {
        final granted =
            await LocalNotificationService.requestContextualPermission();
        if (!mounted) return;
        if (granted) {
          await LocalNotificationService.setGraphNotificationEnabled(
            graphId,
            true,
          );
          if (!mounted) return;
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("We'll notify you as soon as this graph finishes!"),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications disabled. In-app notice will still show when complete.',
              ),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      icon: const Icon(Icons.notifications_none_rounded, size: 14),
      label: const Text('Notify me when done', style: TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
        foregroundColor: isDark
            ? const Color(0xFFA1A1AA)
            : const Color(0xFF71717A),
      ),
    );
  }
}
