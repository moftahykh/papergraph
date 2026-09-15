import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/paper_url_helper.dart';
import '../../../models/graph_models.dart';
import '../../../models/metric_result.dart';

class GraphBottomSheet extends StatefulWidget {
  final GraphSnapshot snapshot;
  final GraphNode? selectedNode;
  final ValueChanged<GraphNode> onNodeSelected;
  final ValueChanged<String>? onRecenterGraph;
  final ValueChanged<GraphNode>? onOpenFullDetails;
  final VoidCallback? onClose;
  final int initialTabIndex;

  const GraphBottomSheet({
    super.key,
    required this.snapshot,
    this.selectedNode,
    required this.onNodeSelected,
    this.onRecenterGraph,
    this.onOpenFullDetails,
    this.onClose,
    this.initialTabIndex = 0,
  });

  @override
  State<GraphBottomSheet> createState() => _GraphBottomSheetState();
}

class _GraphBottomSheetState extends State<GraphBottomSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchFilterController = TextEditingController();
  String _listFilter = '';
  String _sortBy = 'citations'; // citations, year, score
  double _sheetHeight = 380.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void didUpdateWidget(covariant GraphBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedNode?.canonicalId != widget.selectedNode?.canonicalId &&
        widget.selectedNode != null) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchFilterController.dispose();
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
        border: Border(top: BorderSide(color: borderColor, width: 1.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 120 : 30),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle and Close Button
          GestureDetector(
            onVerticalDragUpdate: (details) {
              setState(() {
                _sheetHeight -= details.delta.dy;
                if (_sheetHeight < 250) _sheetHeight = 250;
                final maxHeight = MediaQuery.of(context).size.height * 0.85;
                if (_sheetHeight > maxHeight) _sheetHeight = maxHeight;
              });
            },
            child: Container(
              color: Colors.transparent, // Capture drags on empty space
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 40),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF4B4F59) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: widget.onClose,
                    tooltip: 'Close Sheet',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
                  ),
                ],
              ),
            ),
          ),

          // 4-Tab Navigation Bar
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: AppTheme.primaryBlue,
            indicatorWeight: 3,
            labelColor: isDark ? Colors.white : AppTheme.primaryBlue,
            unselectedLabelColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 13),
            tabs: const [
              Tab(
                icon: Icon(Icons.article_outlined, size: 18),
                text: 'Selected Paper',
              ),
              Tab(
                icon: Icon(Icons.history_edu_outlined, size: 18),
                text: 'Prior Works',
              ),
              Tab(
                icon: Icon(Icons.trending_up_outlined, size: 18),
                text: 'Derivative Works',
              ),
              Tab(
                icon: Icon(Icons.list_alt_outlined, size: 18),
                text: 'List View',
              ),
            ],
          ),

          const Divider(height: 1, thickness: 1),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSelectedPaperTab(isDark),
                _buildPriorWorksTab(isDark),
                _buildDerivativeWorksTab(isDark),
                _buildListViewTab(isDark),
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
              size: 44,
              color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
            ),
            const SizedBox(height: 12),
            Text(
              'Select a Paper Node',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap any node in the graph to inspect metrics, citations, and relationships.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.darkTextSecondary : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      );
    }

    final textColor = isDark ? AppTheme.darkTextPrimary : const Color(0xFF0F172A);
    final subtextColor = isDark ? AppTheme.darkTextSecondary : const Color(0xFF64748B);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Title & Badges
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                node.title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (node.isOrigin) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withAlpha(40),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Text(
                  'SEED ORIGIN',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 6),

        // Authors & Meta
        Text(
          node.authors.isNotEmpty ? node.authors.join(', ') : 'Unknown Authors',
          style: TextStyle(fontSize: 12, color: subtextColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 8),

        // Badges Row (Year, Citations, Confidence)
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (node.year != null)
              _buildBadge(
                Icons.calendar_today_rounded,
                '${node.year}',
                const Color(0xFF10B981),
                isDark,
              ),
            _buildBadge(
              Icons.format_quote_rounded,
              '${node.citationCount} Citations',
              const Color(0xFF3B82F6),
              isDark,
            ),
            if (node.confidence != null)
              _buildBadge(
                Icons.verified_outlined,
                '${node.confidence!.value.toUpperCase()} CONFIDENCE',
                _confidenceColor(node.confidence!),
                isDark,
              ),
            if (node.archetype != null)
              _buildBadge(
                Icons.category_outlined,
                node.archetype!.toUpperCase(),
                const Color(0xFF8B5CF6),
                isDark,
              ),
          ],
        ),

        const SizedBox(height: 12),

        // Metrics Breakdown Row (WBC, NCC, Score)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkSurface : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildMetricColumn(
                  'WBC Metric',
                  node.scores?['wbc']?.value,
                  node.scores?['wbc']?.availability ?? MetricAvailability.unavailable,
                  isDark,
                ),
              ),
              Container(width: 1, height: 32, color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
              Expanded(
                child: _buildMetricColumn(
                  'NCC Metric',
                  node.scores?['ncc']?.value,
                  node.scores?['ncc']?.availability ?? MetricAvailability.unavailable,
                  isDark,
                ),
              ),
              Container(width: 1, height: 32, color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
              Expanded(
                child: _buildMetricColumn(
                  'Final Score',
                  node.finalScore,
                  node.finalScore != null ? MetricAvailability.available : MetricAvailability.unavailable,
                  isDark,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Action Buttons (Responsive Wrap layout - guarantees zero RenderFlex overflow)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: 'Read Original Paper / PDF in Browser',
              child: IconButton.filled(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.accentEmerald,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(10),
                ),
                onPressed: () {
                  final url = PaperUrlHelper.resolvePaperUrl(
                    canonicalId: node.canonicalId,
                    title: node.title,
                  );
                  PaperUrlHelper.launchPaper(context, url: url, title: node.title);
                },
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => widget.onOpenFullDetails?.call(node),
              icon: const Icon(Icons.menu_book_rounded, size: 16),
              label: const Text('Full Details & BibTeX', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (!node.isOrigin)
              OutlinedButton.icon(
                onPressed: () => widget.onRecenterGraph?.call(node.canonicalId),
                icon: const Icon(Icons.hub_outlined, size: 16),
                label: const Text('Re-center', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryLightBlue,
                  side: const BorderSide(color: AppTheme.primaryBlue),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // TAB 2: Prior Works
  Widget _buildPriorWorksTab(bool isDark) {
    final originYear = widget.snapshot.origin.year ?? 2020;
    // Nodes that are foundational: either scored as prior_score or published prior to origin
    final priorNodes = widget.snapshot.nodes.where((n) {
      if (n.isOrigin) return false;
      final pScore = n.scores?['prior_score']?.value;
      if (pScore != null && pScore > 0.0) return true;
      if (n.archetype == 'foundational') return true;
      if (n.year != null && n.year! < originYear) return true;
      return false;
    }).toList();

    // Sort descending by prior_score or year
    priorNodes.sort((a, b) {
      final scoreA = a.scores?['prior_score']?.value ?? 0.0;
      final scoreB = b.scores?['prior_score']?.value ?? 0.0;
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return (b.year ?? 0).compareTo(a.year ?? 0);
    });

    if (priorNodes.isEmpty) {
      return _buildEmptyTab(
        'No Prior Works Identified',
        'No foundational pre-dating literature was classified for this graph.',
        Icons.history_edu_outlined,
        isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: priorNodes.length,
      itemBuilder: (context, idx) {
        final item = priorNodes[idx];
        final score = item.scores?['prior_score']?.value;
        return _buildNodeListTile(item, idx + 1, score, 'PriorScore', isDark);
      },
    );
  }

  // TAB 3: Derivative Works
  Widget _buildDerivativeWorksTab(bool isDark) {
    final originYear = widget.snapshot.origin.year ?? 2020;
    // Nodes that are derivative: either scored as derivative_score or published after origin
    final derivNodes = widget.snapshot.nodes.where((n) {
      if (n.isOrigin) return false;
      final dScore = n.scores?['derivative_score']?.value;
      if (dScore != null && dScore > 0.0) return true;
      if (n.archetype == 'subsequent' || n.archetype == 'derivative') return true;
      if (n.year != null && n.year! >= originYear) return true;
      return false;
    }).toList();

    // Sort descending by derivative_score or citations
    derivNodes.sort((a, b) {
      final scoreA = a.scores?['derivative_score']?.value ?? 0.0;
      final scoreB = b.scores?['derivative_score']?.value ?? 0.0;
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return b.citationCount.compareTo(a.citationCount);
    });

    if (derivNodes.isEmpty) {
      return _buildEmptyTab(
        'No Derivative Works Identified',
        'No subsequent derivative papers were found citing this seed.',
        Icons.trending_up_outlined,
        isDark,
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: derivNodes.length,
      itemBuilder: (context, idx) {
        final item = derivNodes[idx];
        final score = item.scores?['derivative_score']?.value;
        return _buildNodeListTile(item, idx + 1, score, 'DerivScore', isDark);
      },
    );
  }

  // TAB 4: List View with Search and Filter
  Widget _buildListViewTab(bool isDark) {
    var list = widget.snapshot.nodes.where((n) {
      if (_listFilter.isEmpty) return true;
      final q = _listFilter.toLowerCase();
      final titleMatch = n.title.toLowerCase().contains(q);
      final authorMatch = n.authors.any((a) => a.toLowerCase().contains(q));
      return titleMatch || authorMatch;
    }).toList();

    if (_sortBy == 'citations') {
      list.sort((a, b) => b.citationCount.compareTo(a.citationCount));
    } else if (_sortBy == 'year') {
      list.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
    } else if (_sortBy == 'score') {
      list.sort((a, b) => (b.finalScore ?? 0.0).compareTo(a.finalScore ?? 0.0));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchFilterController,
                    onChanged: (val) => setState(() => _listFilter = val.trim()),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filter by title or author...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: isDark ? AppTheme.darkSurface : const Color(0xFFF1F5F9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _sortBy,
                underline: const SizedBox(),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.primaryBlue,
                  fontWeight: FontWeight.bold,
                ),
                dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                items: const [
                  DropdownMenuItem(value: 'citations', child: Text('Citations')),
                  DropdownMenuItem(value: 'year', child: Text('Year')),
                  DropdownMenuItem(value: 'score', child: Text('Score')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _sortBy = val);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            itemCount: list.length,
            itemBuilder: (context, idx) {
              final item = list[idx];
              return _buildNodeListTile(
                item,
                idx + 1,
                item.finalScore,
                'Score',
                isDark,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNodeListTile(
    GraphNode node,
    int rank,
    double? scoreValue,
    String scoreLabel,
    bool isDark,
  ) {
    final isSelected = node.canonicalId == widget.selectedNode?.canonicalId;
    final cardBg = isSelected
        ? (isDark ? AppTheme.primaryLightBlue.withAlpha(50) : const Color(0xFFDBEAFE))
        : (isDark ? AppTheme.darkSurface : const Color(0xFFF8FAFC));
    final borderColor = isSelected
        ? AppTheme.accentCyan
        : (isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0));

    return GestureDetector(
      onTap: () {
        widget.onNodeSelected(node);
        _tabController.animateTo(0);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1.0),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.primaryBlue,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${node.year ?? "N/A"} • ${node.citationCount} citations',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (scoreValue != null) ...[
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    scoreValue.toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  Text(
                    scoreLabel,
                    style: TextStyle(
                      fontSize: 9,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              tooltip: 'Open Paper in Browser',
              color: isDark ? const Color(0xFF38BDF8) : AppTheme.primaryBlue,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                final url = PaperUrlHelper.resolvePaperUrl(
                  canonicalId: node.canonicalId,
                  title: node.title,
                );
                PaperUrlHelper.launchPaper(context, url: url, title: node.title);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn(
    String label,
    double? value,
    MetricAvailability availability,
    bool isDark,
  ) {
    final valText = value != null ? value.toStringAsFixed(2) : '—';
    final subText = availability == MetricAvailability.available ? 'Evaluated' : availability.value;
    final color = availability == MetricAvailability.available ? const Color(0xFF10B981) : const Color(0xFF94A3B8);

    return Column(
      children: [
        Text(
          valText,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        Text(
          subText,
          style: TextStyle(fontSize: 9, color: color),
        ),
      ],
    );
  }

  Widget _buildBadge(IconData icon, String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(isDark ? 35 : 25),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(isDark ? 80 : 120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTab(String title, String desc, IconData icon, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 36,
              color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              desc,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _confidenceColor(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return const Color(0xFF10B981);
      case ConfidenceLevel.medium:
        return const Color(0xFF38BDF8);
      case ConfidenceLevel.low:
        return const Color(0xFFF59E0B);
      case ConfidenceLevel.insufficient:
        return const Color(0xFFEF4444);
    }
  }
}
