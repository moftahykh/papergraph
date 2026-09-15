import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/graph_models.dart';

class GraphCanvasPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> citationEdges;
  final List<GraphEdge> similarityEdges;
  final String? selectedNodeId;
  final bool isDark;
  final Map<String, Offset>? draggedPositions;

  // Cached year bounds for gradient mapping
  final int minYear;
  final int maxYear;
  final int maxCitations;

  GraphCanvasPainter({
    required this.nodes,
    required this.citationEdges,
    required this.similarityEdges,
    this.selectedNodeId,
    this.isDark = true,
    this.draggedPositions,
  })  : minYear = calcMinYear(nodes),
        maxYear = calcMaxYear(nodes),
        maxCitations = calcMaxCitations(nodes);

  static int calcMinYear(List<GraphNode> nodes) {
    int min = 3000;
    for (final n in nodes) {
      if (n.year != null && n.year! < min && n.year! > 1800) {
        min = n.year!;
      }
    }
    return min == 3000 ? 2000 : min;
  }

  static int calcMaxYear(List<GraphNode> nodes) {
    int max = 0;
    for (final n in nodes) {
      if (n.year != null && n.year! > max) {
        max = n.year!;
      }
    }
    return max == 0 ? DateTime.now().year : max;
  }

  static int calcMaxCitations(List<GraphNode> nodes) {
    int max = 0;
    for (final n in nodes) {
      if (n.citationCount > max) {
        max = n.citationCount;
      }
    }
    return math.max(10, max);
  }

  /// Bounded logarithmic citation radius: R in [14.0, 30.0]
  static double computeNodeRadius(int citationCount, int maxCitations) {
    const double minR = 14.0;
    const double maxR = 30.0;
    final logMax = math.log(1 + math.max(50, maxCitations));
    final logVal = math.log(1 + math.max(0, citationCount));
    final ratio = (logVal / logMax).clamp(0.0, 1.0);
    return minR + (maxR - minR) * ratio;
  }

  /// Resolves node position (either dragged override or canonical coordinate)
  Offset getNodePosition(GraphNode node) {
    if (draggedPositions != null && draggedPositions!.containsKey(node.canonicalId)) {
      return draggedPositions![node.canonicalId]!;
    }
    return Offset(node.x, node.y);
  }

  /// Color mapping by publication year (Mint-Teal for older -> Obsidian Blue for newer)
  Color getNodeColor(int? year) {
    if (year == null) return const Color(0xFF64748B);
    if (maxYear == minYear) return const Color(0xFF2563EB);

    final t = ((year - minYear) / (maxYear - minYear)).clamp(0.0, 1.0);
    // Gradient: Mint Teal (0xFF10B981) -> Sky Cyan (0xFF06B6D4) -> Electric Blue (0xFF2563EB)
    if (t < 0.5) {
      return Color.lerp(
        const Color(0xFF10B981),
        const Color(0xFF06B6D4),
        t * 2,
      )!;
    } else {
      return Color.lerp(
        const Color(0xFF06B6D4),
        const Color(0xFF2563EB),
        (t - 0.5) * 2,
      )!;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = <String, GraphNode>{};
    final positionMap = <String, Offset>{};
    final radiusMap = <String, double>{};

    for (final n in nodes) {
      nodeMap[n.canonicalId] = n;
      positionMap[n.canonicalId] = getNodePosition(n);
      radiusMap[n.canonicalId] = computeNodeRadius(n.citationCount, maxCitations);
    }

    final connectedNodeIds = <String>{};
    if (selectedNodeId != null) {
      connectedNodeIds.add(selectedNodeId!);
      for (final e in citationEdges) {
        if (e.source == selectedNodeId) connectedNodeIds.add(e.target);
        if (e.target == selectedNodeId) connectedNodeIds.add(e.source);
      }
      for (final e in similarityEdges) {
        if (e.source == selectedNodeId) connectedNodeIds.add(e.target);
        if (e.target == selectedNodeId) connectedNodeIds.add(e.source);
      }
    }

    // 1. Draw similarity edges (undirected, dashed cyan lines)
    _drawSimilarityEdges(canvas, positionMap, radiusMap, connectedNodeIds);

    // 2. Draw citation edges (directed, solid blue arrows)
    _drawCitationEdges(canvas, positionMap, radiusMap, connectedNodeIds);

    // 3. Draw nodes, halos, and selection rings
    _drawNodes(canvas, nodeMap, positionMap, radiusMap, connectedNodeIds);

    // 4. Draw smart, de-cluttered node labels
    _drawLabels(canvas, nodeMap, positionMap, radiusMap, connectedNodeIds);
  }

  void _drawSimilarityEdges(
    Canvas canvas,
    Map<String, Offset> posMap,
    Map<String, double> radiusMap,
    Set<String> connectedNodeIds,
  ) {
    for (final edge in similarityEdges) {
      final p1 = posMap[edge.source];
      final p2 = posMap[edge.target];
      if (p1 == null || p2 == null) continue;

      final isConnectedToSelected = selectedNodeId != null &&
          (edge.source == selectedNodeId || edge.target == selectedNodeId);

      final int alpha;
      final double width;
      if (selectedNodeId == null) {
        alpha = isDark ? 90 : 110;
        width = 1.3;
      } else if (isConnectedToSelected) {
        alpha = 230;
        width = 2.0;
      } else {
        alpha = 25; // Dimmed when focusing on selected node
        width = 0.9;
      }

      final simPaint = Paint()
        ..color = (isDark ? const Color(0xFF06B6D4) : const Color(0xFF0891B2)).withAlpha(alpha)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      _drawDashedLine(canvas, p1, p2, simPaint, dashLength: 6.0, spaceLength: 4.0);
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dashLength = 6.0,
    double spaceLength = 4.0,
  }) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0.001) return;

    final ux = dx / dist;
    final uy = dy / dist;

    double currentDist = 0.0;
    while (currentDist < dist) {
      final start = Offset(p1.dx + ux * currentDist, p1.dy + uy * currentDist);
      currentDist += dashLength;
      final end = Offset(
        p1.dx + ux * math.min(currentDist, dist),
        p1.dy + uy * math.min(currentDist, dist),
      );
      canvas.drawLine(start, end, paint);
      currentDist += spaceLength;
    }
  }

  void _drawCitationEdges(
    Canvas canvas,
    Map<String, Offset> posMap,
    Map<String, double> radiusMap,
    Set<String> connectedNodeIds,
  ) {
    for (final edge in citationEdges) {
      final p1 = posMap[edge.source];
      final p2 = posMap[edge.target];
      if (p1 == null || p2 == null) continue;

      final targetRadius = radiusMap[edge.target] ?? 16.0;
      final sourceRadius = radiusMap[edge.source] ?? 16.0;

      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= (sourceRadius + targetRadius)) continue;

      final isConnectedToSelected = selectedNodeId != null &&
          (edge.source == selectedNodeId || edge.target == selectedNodeId);

      final int alpha;
      final double width;
      if (selectedNodeId == null) {
        alpha = isDark ? 180 : 200;
        width = 1.8;
      } else if (isConnectedToSelected) {
        alpha = 255;
        width = 2.5;
      } else {
        alpha = 30; // Dimmed
        width = 1.0;
      }

      final edgePaint = Paint()
        ..color = (isDark ? const Color(0xFF3B82F6) : const Color(0xFF1D4ED8)).withAlpha(alpha)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      final arrowPaint = Paint()
        ..color = (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1E40AF)).withAlpha(alpha)
        ..style = PaintingStyle.fill;

      final ux = dx / dist;
      final uy = dy / dist;

      // Start just outside source node, end right at target node border
      final start = Offset(p1.dx + ux * sourceRadius, p1.dy + uy * sourceRadius);
      final tip = Offset(p2.dx - ux * targetRadius, p2.dy - uy * targetRadius);

      canvas.drawLine(start, tip, edgePaint);

      // Draw directional arrowhead at tip pointing to cited target
      const arrowLength = 9.0;
      const arrowWidth = 5.0;

      // Normal vector perpendicular to direction
      final nx = -uy;
      final ny = ux;

      final baseCenter = Offset(tip.dx - ux * arrowLength, tip.dy - uy * arrowLength);
      final corner1 = Offset(baseCenter.dx + nx * arrowWidth, baseCenter.dy + ny * arrowWidth);
      final corner2 = Offset(baseCenter.dx - nx * arrowWidth, baseCenter.dy - ny * arrowWidth);

      final arrowPath = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(corner1.dx, corner1.dy)
        ..lineTo(corner2.dx, corner2.dy)
        ..close();

      canvas.drawPath(arrowPath, arrowPaint);
    }
  }

  void _drawNodes(
    Canvas canvas,
    Map<String, GraphNode> nodeMap,
    Map<String, Offset> posMap,
    Map<String, double> radiusMap,
    Set<String> connectedNodeIds,
  ) {
    for (final node in nodes) {
      final pos = posMap[node.canonicalId]!;
      final radius = radiusMap[node.canonicalId]!;
      final isSelected = node.canonicalId == selectedNodeId;
      final isConnected = selectedNodeId != null && connectedNodeIds.contains(node.canonicalId);
      final isDimmed = selectedNodeId != null && !isConnected && !node.isOrigin;

      final nodeColor = getNodeColor(node.year);

      // 1. Origin Node Clean Double Ring
      if (node.isOrigin) {
        final originRingPaint = Paint()
          ..color = const Color(0xFFF59E0B)
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pos, radius + 4.0, originRingPaint);
      }

      // 2. Selection Ring
      if (isSelected) {
        final selRingPaint = Paint()
          ..color = isDark ? Colors.white : AppTheme.primaryBlue
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pos, radius + 4.5, selRingPaint);
      }

      // 3. Node Base Circle with Subtle Shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withAlpha(isDark ? (isDimmed ? 30 : 90) : (isDimmed ? 15 : 40))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
      canvas.drawCircle(Offset(pos.dx, pos.dy + 2.0), radius, shadowPaint);

      // 4. Node Fill with Year Gradient Tone
      final nodePaint = Paint()
        ..color = isDimmed ? nodeColor.withAlpha(75) : nodeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, radius, nodePaint);

      // 5. Border Accent Ring
      final borderPaint = Paint()
        ..color = isDark
            ? (isDimmed ? Colors.white.withAlpha(25) : Colors.white.withAlpha(80))
            : (isDimmed ? Colors.white.withAlpha(70) : Colors.white.withAlpha(200))
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pos, radius, borderPaint);

      // 6. Year Indicator Inside Node for all nodes with radius >= 13.0
      if (radius >= 13.0 && node.year != null) {
        final yearTextPainter = TextPainter(
          text: TextSpan(
            text: '${node.year}',
            style: TextStyle(
              color: isDimmed ? Colors.white.withAlpha(100) : Colors.white,
              fontSize: 10.0,
              fontWeight: FontWeight.bold,
              shadows: const [Shadow(color: Colors.black54, blurRadius: 2.0)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        yearTextPainter.paint(
          canvas,
          Offset(pos.dx - yearTextPainter.width / 2, pos.dy - yearTextPainter.height / 2),
        );
      }
    }
  }

  void _drawLabels(
    Canvas canvas,
    Map<String, GraphNode> nodeMap,
    Map<String, Offset> posMap,
    Map<String, double> radiusMap,
    Set<String> connectedNodeIds,
  ) {
    for (final node in nodes) {
      final isSelected = node.canonicalId == selectedNodeId;

      // Strict Anti-AI-Slop & Scientific Clutter Reduction:
      // Only show floating label for the actively selected node, or origin node when nothing is selected.
      // Never render dozens of simultaneous labels on mobile.
      final shouldShow = isSelected || (selectedNodeId == null && node.isOrigin);
      if (!shouldShow) continue;

      final pos = posMap[node.canonicalId]!;
      final radius = radiusMap[node.canonicalId]!;

      final labelText = node.displayTitle;
      final maxChars = isSelected ? 35 : 22;
      final truncated = labelText.length > maxChars ? '${labelText.substring(0, maxChars - 2)}...' : labelText;

      final textSpan = TextSpan(
        text: truncated,
        style: TextStyle(
          color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF0F172A),
          fontSize: isSelected ? 12.0 : 10.5,
          fontWeight: (isSelected || node.isOrigin) ? FontWeight.bold : FontWeight.w500,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 160);

      final textOffset = Offset(
        pos.dx - textPainter.width / 2,
        pos.dy + radius + 4.0,
      );

      // Background pill for contrast
      final pillRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          textOffset.dx - 5,
          textOffset.dy - 2,
          textPainter.width + 10,
          textPainter.height + 4,
        ),
        const Radius.circular(5.0),
      );

      final pillColor = isDark
          ? (isSelected
              ? const Color(0xFF2563EB)
              : (node.isOrigin ? const Color(0xFF92400E) : AppTheme.darkCard.withValues(alpha: 0.92)))
          : (isSelected
              ? const Color(0xFFDBEAFE)
              : (node.isOrigin ? const Color(0xFFFEF3C7) : const Color(0xF2FFFFFF)));

      final borderPillColor = isDark
          ? (isSelected ? Colors.white : AppTheme.darkBorder)
          : (isSelected ? const Color(0xFF2563EB) : const Color(0xFFCBD5E1));

      final pillPaint = Paint()
        ..color = pillColor
        ..style = PaintingStyle.fill;

      final borderPillPaint = Paint()
        ..color = borderPillColor
        ..strokeWidth = isSelected ? 1.5 : 1.0
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(pillRect, pillPaint);
      canvas.drawRRect(pillRect, borderPillPaint);
      textPainter.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant GraphCanvasPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.isDark != isDark ||
        oldDelegate.draggedPositions != draggedPositions ||
        oldDelegate.citationEdges != citationEdges ||
        oldDelegate.similarityEdges != similarityEdges;
  }
}
