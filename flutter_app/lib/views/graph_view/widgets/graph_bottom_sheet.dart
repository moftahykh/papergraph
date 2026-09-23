import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/connection_reason_helper.dart';
import '../../../core/utils/paper_url_helper.dart';
import '../../../models/graph_models.dart';
import '../../../models/metric_result.dart';

/// Contextual bottom sheet for literature exploration.
///
/// Features progressive disclosure: starts as a compact peek showing
/// identity, relationship reason, and primary actions, and expands smoothly
/// for deep metrics and connected works.
class GraphBottomSheet extends StatefulWidget {
  final GraphSnapshot snapshot;
  final GraphNode? selectedNode;
  final ValueChanged<GraphNode> onNodeSelected;
  final ValueChanged<String>? onRecenterGraph;
  final ValueChanged<GraphNode>? onOpenFullDetails;
  final ValueChanged<GraphNode>? onFocusNode;
  final VoidCallback? onClose;
  final int initialTabIndex;

  const GraphBottomSheet({
    super.key,
    required this.snapshot,
    this.selectedNode,
    required this.onNodeSelected,
    this.onRecenterGraph,
    this.onOpenFullDetails,
    this.onFocusNode,
    this.onClose,
    this.initialTabIndex = 0,
  });

  @override
  State<GraphBottomSheet> createState() => _GraphBottomSheetState();
}

class _GraphBottomSheetState extends State<GraphBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double _sheetHeight = 380.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void didUpdateWidget(covariant GraphBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedNode?.canonicalId !=
            widget.selectedNode?.canonicalId &&
        widget.selectedNode != null) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppTheme.darkCard : Colors.white;
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0);

    return Container(
      height: _sheetHeight,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: borderColor, width: 1.0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 20),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle and Close Row
          GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _sheetHeight -= details.delta.dy;
                if (_sheetHeight < 240) _sheetHeight = 240;
                final maxHeight = MediaQuery.of(context).size.height * 0.85;
                if (_sheetHeight > maxHeight) _sheetHeight = maxHeight;
              });
            },
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 36),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF4B4F59)
                          : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: widget.onClose,
                    tooltip: 'Close sheet',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Keep the same relationship taxonomy as the full list view.
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: isDark
                ? AppTheme.actionPurpleDark
                : AppTheme.actionPurple,
            indicatorWeight: 2.5,
            labelColor: isDark
                ? AppTheme.darkTextPrimary
                : AppTheme.actionPurple,
            unselectedLabelColor: isDark
                ? AppTheme.darkTextSecondary
                : const Color(0xFF64748B),
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
            ),
            tabs: const [
              Tab(icon: Icon(Icons.article_outlined, size: 16), text: 'Paper'),
              Tab(
                icon: Icon(Icons.format_quote_outlined, size: 16),
                text: 'Citations',
              ),
              Tab(
                icon: Icon(Icons.auto_awesome_outlined, size: 16),
                text: 'Similar',
              ),
              Tab(
                icon: Icon(Icons.history_edu_outlined, size: 16),
                text: 'Earlier',
              ),
              Tab(
                icon: Icon(Icons.trending_up_outlined, size: 16),
                text: 'Later',
              ),
            ],
          ),

          Divider(
            height: 1,
            thickness: 0.75,
            color: isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSelectedPaperTab(isDark),
                _buildCitationsTab(isDark),
                _buildSimilarTab(isDark),
                _buildPriorWorksTab(isDark),
                _buildDerivativeWorksTab(isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // TAB 1: Selected Paper Details
  Widget _buildSelectedPaperTab(bool isDark) {
    final node = widget.selectedNode;
    if (node == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 36,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 8),
            Text(
              'Select a paper',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap any node in the graph to inspect relationships and citation context.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    final textColor = isDark
        ? AppTheme.darkTextPrimary
        : const Color(0xFF111827);
    final subtextColor = isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF6B7280);

    // Explain connection to seed/origin
    final explanation = ConnectionReasonHelper.explainConnection(
      node: node,
      snapshot: widget.snapshot,
    );

    Color badgeColor;
    switch (explanation.category) {
      case ConnectionCategory.origin:
        badgeColor = isDark ? Colors.white : const Color(0xFF18181B);
        break;
      case ConnectionCategory.citation:
        badgeColor = isDark ? const Color(0xFFD4D4D8) : const Color(0xFF3F3F46);
        break;
      case ConnectionCategory.similarity:
        badgeColor = isDark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
        break;
      default:
        badgeColor = isDark
            ? AppTheme.darkTextSecondary
            : const Color(0xFF71717A);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        // Title and Origin / Category badge
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                node.title,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: textColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(12)
                    : Colors.black.withAlpha(8),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                  width: 0.8,
                ),
              ),
              child: Text(
                explanation.badgeLabel,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 4),

        // Authors & Publication Venue
          Text(
            node.authors.isNotEmpty
                ? node.authors.join(', ')
                : 'Author information unavailable',
          style: TextStyle(fontSize: 12, color: subtextColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 8),

        // Badges Row (Year, Citations, Confidence)
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (node.year != null)
              _buildMetaTag(
                Icons.calendar_today_rounded,
                '${node.year}',
                isDark,
              ),
            _buildMetaTag(
              Icons.format_quote_rounded,
              _citationLabel(node),
              isDark,
            ),
            if (node.confidence != null)
              _buildMetaTag(
                Icons.verified_outlined,
                '${_confidenceLabel(node.confidence!)} data confidence',
                isDark,
              ),
          ],
        ),

        const SizedBox(height: 10),

        _buildConnectionSummary(
          explanation: explanation,
          accent: badgeColor,
          isDark: isDark,
        ),

        const SizedBox(height: 10),

        _buildRankingSignals(node, isDark),

        const SizedBox(height: 10),

        // Action Buttons Row (Directly accessible actions)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // External Paper / PDF
            Tooltip(
              message: 'Open Paper / PDF in Browser',
              child: IconButton.filled(
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? AppTheme.darkBorder
                      : const Color(0xFFE4E4E7),
                  foregroundColor: isDark
                      ? Colors.white
                      : const Color(0xFF18181B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(8),
                ),
                onPressed: () {
                  final url = PaperUrlHelper.resolvePaperUrl(
                    canonicalId: node.canonicalId,
                    title: node.title,
                  );
                  PaperUrlHelper.launchPaper(
                    context,
                    url: url,
                    title: node.title,
                  );
                },
              ),
            ),

            // Full Details & BibTeX
            ElevatedButton.icon(
              onPressed: () => widget.onOpenFullDetails?.call(node),
              icon: const Icon(Icons.menu_book_rounded, size: 15),
              label: const Text(
                'Paper details',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? Colors.white
                    : const Color(0xFF18181B),
                foregroundColor: isDark
                    ? const Color(0xFF09090B)
                    : Colors.white,
                elevation: 0,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),

            // Re-center Graph
            if (!node.isOrigin)
              OutlinedButton.icon(
                onPressed: () => widget.onRecenterGraph?.call(node.canonicalId),
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text(
                  'Center graph',
                  style: TextStyle(fontSize: 11.5),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? AppTheme.darkTextSecondary
                      : const Color(0xFF475569),
                  side: BorderSide(
                    color: isDark
                        ? AppTheme.darkBorder
                        : const Color(0xFFCBD5E1),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),

            // Focus on Node in Graph
            OutlinedButton.icon(
              onPressed: () => widget.onFocusNode?.call(node),
              icon: const Icon(Icons.center_focus_strong_rounded, size: 15),
              label: const Text('Focus', style: TextStyle(fontSize: 11.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? AppTheme.actionPurpleDark
                    : AppTheme.actionPurple,
                side: BorderSide(
                  color: isDark
                      ? AppTheme.actionPurpleDark
                      : AppTheme.actionPurple,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
      ],
    );
  }

  // TAB 2: Direct citations
  Widget _buildCitationsTab(bool isDark) {
    final originId = widget.snapshot.origin.canonicalId;
    final ids = <String>{};
    for (final edge in widget.snapshot.citationEdges) {
      if (edge.source == originId) ids.add(edge.target);
      if (edge.target == originId) ids.add(edge.source);
    }
    final nodes = widget.snapshot.nodes
        .where((node) => !node.isOrigin && ids.contains(node.canonicalId))
        .toList()
      ..sort((a, b) => b.citationCount.compareTo(a.citationCount));
    return _buildNodeCollectionTab(
      nodes,
      title: 'No direct citations identified',
      description: 'No confirmed citation links are available in this graph.',
      icon: Icons.format_quote_outlined,
      isDark: isDark,
    );
  }

  // TAB 3: Validated similarities
  Widget _buildSimilarTab(bool isDark) {
    final originId = widget.snapshot.origin.canonicalId;
    final ids = <String>{};
    for (final edge in widget.snapshot.similarityEdges) {
      if (edge.source == originId) ids.add(edge.target);
      if (edge.target == originId) ids.add(edge.source);
    }
    final nodes = widget.snapshot.nodes
        .where((node) => !node.isOrigin && ids.contains(node.canonicalId))
        .toList()
      ..sort((a, b) => (b.finalScore ?? 0).compareTo(a.finalScore ?? 0));
    return _buildNodeCollectionTab(
      nodes,
      title: 'No similar papers identified',
      description: 'No validated similarity links are available in this graph.',
      icon: Icons.auto_awesome_outlined,
      isDark: isDark,
    );
  }

  Widget _buildNodeCollectionTab(
    List<GraphNode> nodes, {
    required String title,
    required String description,
    required IconData icon,
    required bool isDark,
  }) {
    if (nodes.isEmpty) {
      return _buildEmptyTab(title, description, icon, isDark);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: nodes.length,
      itemBuilder: (context, index) =>
          _buildSimpleNodeTile(nodes[index], isDark),
    );
  }

  // TAB 4: Prior Works
  Widget _buildPriorWorksTab(bool isDark) {
    final originYear = widget.snapshot.origin.year ?? 2020;
    final priorNodes = widget.snapshot.nodes.where((n) {
      if (n.isOrigin) return false;
      final pScore = n.scores?['prior_score']?.value;
      if (pScore != null && pScore > 0.0) return true;
      if (n.archetype == 'foundational') return true;
      if (n.year != null && n.year! < originYear) return true;
      return false;
    }).toList()..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));

    if (priorNodes.isEmpty) {
      return _buildEmptyTab(
        'No earlier works identified',
        'No papers classified as earlier or foundational are available in this graph.',
        Icons.history_edu_outlined,
        isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: priorNodes.length,
      itemBuilder: (context, idx) =>
          _buildSimpleNodeTile(priorNodes[idx], isDark),
    );
  }

  // TAB 5: Derivative Works
  Widget _buildDerivativeWorksTab(bool isDark) {
    final originYear = widget.snapshot.origin.year ?? 2020;
    final derivNodes = widget.snapshot.nodes.where((n) {
      if (n.isOrigin) return false;
      final dScore = n.scores?['derivative_score']?.value;
      if (dScore != null && dScore > 0.0) return true;
      if (n.archetype == 'subsequent' || n.archetype == 'derivative') {
        return true;
      }
      if (n.year != null && n.year! >= originYear) return true;
      return false;
    }).toList()..sort((a, b) => b.citationCount.compareTo(a.citationCount));

    if (derivNodes.isEmpty) {
      return _buildEmptyTab(
        'No later works identified',
        'No papers classified as later or follow-up research are available in this graph.',
        Icons.trending_up_outlined,
        isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: derivNodes.length,
      itemBuilder: (context, idx) =>
          _buildSimpleNodeTile(derivNodes[idx], isDark),
    );
  }

  Widget _buildConnectionSummary({
    required ConnectionExplanation explanation,
    required Color accent,
    required bool isDark,
  }) {
    final textColor = isDark
        ? AppTheme.darkTextPrimary
        : const Color(0xFF111827);
    final subtextColor = isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF64748B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.link_rounded,
                size: 17,
                color: isDark ? Colors.white : const Color(0xFF18181B),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Why this paper appears',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              if (explanation.evidenceLimited)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkSurface
                        : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Limited evidence',
                    style: TextStyle(
                      color: AppTheme.accentAmber,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            explanation.title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            explanation.description,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: subtextColor),
          ),
          if (explanation.evidence.isNotEmpty) ...[
            const SizedBox(height: 9),
            for (final evidence in explanation.evidence)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 14,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 10.8,
                            height: 1.35,
                            color: subtextColor,
                          ),
                          children: [
                            TextSpan(
                              text: '${evidence.label}: ',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            TextSpan(text: evidence.value),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankingSignals(GraphNode node, bool isDark) {
    final explanation = ConnectionReasonHelper.explainConnection(
      node: node,
      snapshot: widget.snapshot,
    );
    final isSimilarity =
        explanation.category == ConnectionCategory.similarity;
    final signals = <Widget>[
      _buildMetricSignal(
        label: 'Shared references',
        result: node.scores?['wbc'],
        help: 'Similarity based on references both papers cite.',
        isDark: isDark,
      ),
      _buildMetricSignal(
        label: 'Co-citation',
        result: node.scores?['ncc'],
        help: 'How strongly the papers are cited together.',
        isDark: isDark,
      ),
      _buildMetricSignal(
        label: node.isOrigin ? 'Graph baseline' : 'Connection strength',
        result: MetricResult(
          value: node.isOrigin ? null : node.finalScore,
          availability: node.isOrigin
              ? MetricAvailability.notApplicable
              : node.finalScore == null
              ? MetricAvailability.unavailable
              : MetricAvailability.available,
        ),
        displayValue: node.isOrigin ? 'Starting paper' : null,
        help: node.isOrigin
            ? 'This is the starting paper used to build the graph.'
            : 'Combined score used to rank this paper in the graph. It is not a measure of research quality.',
        isDark: isDark,
      ),
      if (!isSimilarity && node.scores?.containsKey('prior_score') == true)
        _buildMetricSignal(
          label: 'Foundation signal',
          result: node.scores?['prior_score'],
          help: 'Signal used to classify earlier foundational work.',
          isDark: isDark,
        ),
      if (!isSimilarity &&
          node.scores?.containsKey('derivative_score') == true)
        _buildMetricSignal(
          label: 'Follow-up signal',
          result: node.scores?['derivative_score'],
          help: 'Signal used to classify later follow-up work.',
          isDark: isDark,
        ),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : const Color(0xFFF7F8FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Connection signals',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : const Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'These signals explain why this paper is connected to your graph. They do not measure research quality.',
            style: TextStyle(
              fontSize: 10.5,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 9),
          Wrap(spacing: 8, runSpacing: 8, children: signals),
        ],
      ),
    );
  }

  Widget _buildMetricSignal({
    required String label,
    required MetricResult? result,
    required String help,
    required bool isDark,
    String? displayValue,
  }) {
    final value = displayValue ?? _metricDisplayValue(result);
    final available = displayValue != null || result?.isAvailable == true;
    final tooltip = result?.reason?.trim().isNotEmpty == true
        ? result!.reason!.trim()
        : result?.isAvailable == true
        ? help
        : '$help No relationship evidence is available in this snapshot.';
    return Tooltip(
      message: tooltip,
      child: Container(
        constraints: const BoxConstraints(minWidth: 104),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9.8,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: available
                    ? (isDark
                          ? AppTheme.darkTextPrimary
                          : const Color(0xFF111827))
                    : (isDark
                          ? AppTheme.darkTextSecondary
                          : const Color(0xFF94A3B8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _metricDisplayValue(MetricResult? result) {
    if (result?.isAvailable == true) {
      return '${(result!.value!.clamp(0.0, 1.0) * 100).round()}%';
    }
    switch (result?.availability) {
      case MetricAvailability.providerError:
        return 'Unavailable from source';
      case MetricAvailability.notApplicable:
        return 'Not relevant to this link';
      case MetricAvailability.available:
      case MetricAvailability.unavailable:
      case null:
        return 'Unavailable';
    }
  }

  String _confidenceLabel(ConfidenceLevel confidence) {
    switch (confidence) {
      case ConfidenceLevel.high:
        return 'High';
      case ConfidenceLevel.medium:
        return 'Medium';
      case ConfidenceLevel.low:
        return 'Low';
      case ConfidenceLevel.insufficient:
        return 'Limited';
    }
  }

  Widget _buildSimpleNodeTile(GraphNode node, bool isDark) {
    final isSelected = widget.selectedNode?.canonicalId == node.canonicalId;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: isDark
            ? AppTheme.actionPurple.withAlpha(30)
            : const Color(0xFFEEF2FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        title: Text(
          node.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF111827),
          ),
        ),
        subtitle: Text(
            '${node.year ?? 'Year unavailable'} · ${_citationLabel(node)}',
          style: TextStyle(
            fontSize: 11,
            color: isDark
                ? AppTheme.darkTextSecondary
                : const Color(0xFF6B7280),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: () {
          widget.onNodeSelected(node);
          _tabController.animateTo(0);
        },
      ),
    );
  }

  String _citationLabel(GraphNode node) {
    if (node.citationCount == 0) {
      return 'Citation data unavailable';
    }
    return '${node.citationCount} citations';
  }

  Widget _buildEmptyTab(
    String title,
    String description,
    IconData icon,
    bool isDark,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaTag(IconData icon, String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark
                ? AppTheme.darkTextSecondary
                : const Color(0xFF64748B),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
