import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/connection_reason_helper.dart';
import '../../../models/graph_models.dart';

/// Information-dense, categorized literature list view.
///
/// Designed as a first-class alternative to the 2D visual graph,
/// grouping connected papers into clear, verifiable academic relationships.
class GraphListViewTab extends StatefulWidget {
  final GraphSnapshot snapshot;
  final GraphNode? selectedNode;
  final ValueChanged<GraphNode> onNodeSelected;
  final ValueChanged<GraphNode> onFocusInGraph;
  final ValueChanged<GraphNode> onOpenFullDetails;
  final bool isDark;

  const GraphListViewTab({
    super.key,
    required this.snapshot,
    this.selectedNode,
    required this.onNodeSelected,
    required this.onFocusInGraph,
    required this.onOpenFullDetails,
    required this.isDark,
  });

  @override
  State<GraphListViewTab> createState() => _GraphListViewTabState();
}

class _GraphListViewTabState extends State<GraphListViewTab> {
  final TextEditingController _filterController = TextEditingController();
  String _filterQuery = '';
  String _selectedSection =
      'all'; // all, citations, similarity, prior, derivative

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final originYear = widget.snapshot.origin.year ?? 2020;
    final originId = widget.snapshot.origin.canonicalId;

    // Filter nodes based on query
    final filteredNodes = widget.snapshot.nodes.where((n) {
      if (_filterQuery.isEmpty) return true;
      final q = _filterQuery.toLowerCase();
      final titleMatch = n.title.toLowerCase().contains(q);
      final authorMatch = n.authors.any((a) => a.toLowerCase().contains(q));
      return titleMatch || authorMatch;
    }).toList();

    // Grouping into academic relationships
    final originNode = filteredNodes.firstWhere(
      (n) => n.isOrigin,
      orElse: () => widget.snapshot.nodes.first,
    );

    // Direct citation papers (incoming or outgoing)
    final citationNodeIds = <String>{};
    for (final e in widget.snapshot.citationEdges) {
      if (e.source == originId) citationNodeIds.add(e.target);
      if (e.target == originId) citationNodeIds.add(e.source);
    }
    final citationNodes =
        filteredNodes
            .where(
              (n) => !n.isOrigin && citationNodeIds.contains(n.canonicalId),
            )
            .toList()
          ..sort((a, b) => b.citationCount.compareTo(a.citationCount));

    // Similarity papers
    final simNodeIds = <String>{};
    for (final e in widget.snapshot.similarityEdges) {
      if (e.source == originId) simNodeIds.add(e.target);
      if (e.target == originId) simNodeIds.add(e.source);
    }
    final similarityNodes = filteredNodes
        .where(
          (n) =>
              !n.isOrigin &&
              simNodeIds.contains(n.canonicalId) &&
              !citationNodeIds.contains(n.canonicalId),
        )
        .toList();

    // Prior works
    final priorNodes = filteredNodes.where((n) {
      if (n.isOrigin) return false;
      if (citationNodeIds.contains(n.canonicalId)) return false;
      if (simNodeIds.contains(n.canonicalId)) return false;
      return n.year != null && n.year! < originYear;
    }).toList()..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));

    // Derivative works
    final derivativeNodes = filteredNodes.where((n) {
      if (n.isOrigin) return false;
      if (citationNodeIds.contains(n.canonicalId)) return false;
      if (simNodeIds.contains(n.canonicalId)) return false;
      return n.year != null && n.year! >= originYear;
    }).toList()..sort((a, b) => b.citationCount.compareTo(a.citationCount));

    return Column(
      children: [
        // Filter bar and category chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Search input
              TextField(
                controller: _filterController,
                onChanged: (val) => setState(() => _filterQuery = val.trim()),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Filter literature by title or author...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          onPressed: () {
                            _filterController.clear();
                            setState(() => _filterQuery = '');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),

              // Filter category chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      'All (${filteredNodes.length})',
                      'all',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      'Citations (${citationNodes.length})',
                      'citations',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      'Similar (${similarityNodes.length})',
                      'similarity',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      'Earlier (${priorNodes.length})',
                      'prior',
                      isDark,
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChip(
                      'Later (${derivativeNodes.length})',
                      'derivative',
                      isDark,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1, thickness: 1),

        // Grouped Results List
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              // Seed Origin Paper Section
              if (_selectedSection == 'all' &&
                  filteredNodes.any((n) => n.isOrigin)) ...[
                _buildSectionHeader(
                  'Starting paper',
                  1,
                  AppTheme.originGreen,
                  isDark,
                ),
                _buildPaperRow(originNode, isDark),
                const SizedBox(height: 16),
              ],

              // Direct Citations
              if ((_selectedSection == 'all' ||
                      _selectedSection == 'citations') &&
                  citationNodes.isNotEmpty) ...[
                _buildSectionHeader(
                  'DIRECT CITATIONS',
                  citationNodes.length,
                  AppTheme.citationBlue,
                  isDark,
                ),
                for (final node in citationNodes) _buildPaperRow(node, isDark),
                const SizedBox(height: 16),
              ],

              // Semantic Similarities
              if ((_selectedSection == 'all' ||
                      _selectedSection == 'similarity') &&
                  similarityNodes.isNotEmpty) ...[
                _buildSectionHeader(
                  'SIMILAR PAPERS',
                  similarityNodes.length,
                  AppTheme.similarityCyan,
                  isDark,
                ),
                for (final node in similarityNodes)
                  _buildPaperRow(node, isDark),
                const SizedBox(height: 16),
              ],

              // Foundational Prior Works
              if ((_selectedSection == 'all' || _selectedSection == 'prior') &&
                  priorNodes.isNotEmpty) ...[
                _buildSectionHeader(
                  'EARLIER WORKS',
                  priorNodes.length,
                  isDark ? AppTheme.darkTextSecondary : const Color(0xFF64748B),
                  isDark,
                ),
                for (final node in priorNodes) _buildPaperRow(node, isDark),
                const SizedBox(height: 16),
              ],

              // Derivative Subsequent Works
              if ((_selectedSection == 'all' ||
                      _selectedSection == 'derivative') &&
                  derivativeNodes.isNotEmpty) ...[
                _buildSectionHeader(
                  'LATER WORKS',
                  derivativeNodes.length,
                  isDark ? AppTheme.darkTextSecondary : const Color(0xFF64748B),
                  isDark,
                ),
                for (final node in derivativeNodes)
                  _buildPaperRow(node, isDark),
                const SizedBox(height: 16),
              ],

              if (filteredNodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No connected literature matches "$_filterQuery".',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark) {
    final isSelected = _selectedSection == value;
    final activeBg = isDark
        ? AppTheme.actionPurple.withAlpha(40)
        : const Color(0xFFEEF2FF);
    final activeText = isDark
        ? AppTheme.actionPurpleDark
        : AppTheme.actionPurple;
    final inactiveText = isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF64748B);

    return InkWell(
      onTap: () => setState(() => _selectedSection = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppTheme.actionPurpleDark : AppTheme.actionPurple)
                : (isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? activeText : inactiveText,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    Color accentColor,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '($count)',
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaperRow(GraphNode node, bool isDark) {
    final isSelected = widget.selectedNode?.canonicalId == node.canonicalId;
    final explanation = ConnectionReasonHelper.explainConnection(
      node: node,
      snapshot: widget.snapshot,
    );

    final authorsText = node.authors.isNotEmpty
        ? (node.authors.length > 2
              ? '${node.authors.first} et al.'
              : node.authors.join(', '))
        : 'Unknown Authors';

    Color badgeColor;
    switch (explanation.category) {
      case ConnectionCategory.origin:
        badgeColor = isDark ? AppTheme.originGreenDark : AppTheme.originGreen;
        break;
      case ConnectionCategory.citation:
        badgeColor = isDark ? AppTheme.citationBlueDark : AppTheme.citationBlue;
        break;
      case ConnectionCategory.similarity:
        badgeColor = isDark
            ? AppTheme.similarityCyanDark
            : AppTheme.similarityCyan;
        break;
      default:
        badgeColor = isDark
            ? AppTheme.darkTextSecondary
            : const Color(0xFF64748B);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDark
                  ? AppTheme.actionPurple.withAlpha(25)
                  : const Color(0xFFF5F3FF))
            : (isDark ? AppTheme.darkCard : Colors.white),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected
              ? (isDark ? AppTheme.actionPurpleDark : AppTheme.actionPurple)
              : (isDark ? AppTheme.darkBorder : const Color(0xFFE5E7EB)),
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () => widget.onNodeSelected(node),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title & Badges
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      node.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: isDark
                            ? AppTheme.darkTextPrimary
                            : const Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: badgeColor.withAlpha(90),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      explanation.badgeLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Metadata Row (Authors · Year · Citations)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$authorsText · ${node.year ?? 'N/A'} · ${node.citationCount} citations',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark
                            ? AppTheme.darkTextSecondary
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Connection reason note
              Text(
                explanation.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? AppTheme.darkTextSecondary.withAlpha(180)
                      : const Color(0xFF9CA3AF),
                ),
              ),
              const SizedBox(height: 8),

              // Action Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => widget.onFocusInGraph(node),
                    icon: const Icon(
                      Icons.center_focus_strong_rounded,
                      size: 14,
                    ),
                    label: const Text(
                      'View in Graph',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
                          ? AppTheme.actionPurpleDark
                          : AppTheme.actionPurple,
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
                    onPressed: () => widget.onOpenFullDetails(node),
                    icon: const Icon(Icons.menu_book_rounded, size: 14),
                    label: const Text(
                      'Details',
                      style: TextStyle(fontSize: 11),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      visualDensity: VisualDensity.compact,
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
}
