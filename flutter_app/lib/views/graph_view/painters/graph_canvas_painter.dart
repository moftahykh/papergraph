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
  final double zoomScale;

  // Cached year and citation bounds
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
    this.zoomScale = 1.0,
  }) : minYear = calcMinYear(nodes),
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
    if (draggedPositions != null &&
        draggedPositions!.containsKey(node.canonicalId)) {
      return draggedPositions![node.canonicalId]!;
    }
    return Offset(node.x, node.y);
  }

  /// Color mapping by publication year (Refined monochrome/slate tonal ramp)
  Color getNodeColor(int? year) {
    if (year == null) {
      return isDark ? const Color(0xFF71717A) : const Color(0xFF94A3B8);
    }
    if (maxYear == minYear) {
      return isDark ? const Color(0xFFF4F4F5) : const Color(0xFF18181B);
    }

    final t = ((year - minYear) / (maxYear - minYear)).clamp(0.0, 1.0);
    if (isDark) {
      // Dark mode: Older (slate-600) -> Newer (zinc-100 crisp white)
      return Color.lerp(const Color(0xFF52525B), const Color(0xFFF4F4F5), t)!;
    } else {
      // Light mode: Older (slate-400 silver) -> Newer (zinc-900 deep ink)
      return Color.lerp(const Color(0xFF94A3B8), const Color(0xFF18181B), t)!;
    }
  }

  /// Semantic node coloring:
  /// - High-contrast focus for Selected node
  /// - Deep ink / White landmark for Seed Origin
  /// - Tonal slate gradient for literature nodes
  Color resolveNodeColor(GraphNode node, bool isSelected) {
    if (isSelected) {
      return isDark ? const Color(0xFFFFFFFF) : const Color(0xFF18181B);
    }
    if (node.isOrigin) {
      return isDark ? const Color(0xFFFFFFFF) : const Color(0xFF18181B);
    }
    return getNodeColor(node.year);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final nodeMap = <String, GraphNode>{};
    final positionMap = <String, Offset>{};
    final radiusMap = <String, double>{};

    for (final n in nodes) {
      nodeMap[n.canonicalId] = n;
      positionMap[n.canonicalId] = getNodePosition(n);
      radiusMap[n.canonicalId] = computeNodeRadius(
        n.citationCount,
        maxCitations,
      );
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

    // 4. Draw high-contrast, uncluttered node labels
    _drawLabels(canvas, nodeMap, positionMap, radiusMap, connectedNodeIds);
  }

  void _drawSimilarityEdges(
    Canvas canvas,
    Map<String, Offset> posMap,
    Map<String, double> radiusMap,
    Set<String> connectedNodeIds,
  ) {
    final cyanColor = isDark
        ? AppTheme.similarityCyanDark
        : AppTheme.similarityCyan;

    for (final edge in similarityEdges) {
      final p1 = posMap[edge.source];
      final p2 = posMap[edge.target];
      if (p1 == null || p2 == null) continue;
      final sourceRadius = radiusMap[edge.source] ?? 14.0;
      final targetRadius = radiusMap[edge.target] ?? 14.0;
      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance <= sourceRadius + targetRadius) continue;
      final ux = dx / distance;
      final uy = dy / distance;
      final start = Offset(
        p1.dx + ux * sourceRadius,
        p1.dy + uy * sourceRadius,
      );
      final end = Offset(p2.dx - ux * targetRadius, p2.dy - uy * targetRadius);

      final isConnectedToSelected =
          selectedNodeId != null &&
          (edge.source == selectedNodeId || edge.target == selectedNodeId);

      final int alpha;
      final double width;
      if (selectedNodeId == null) {
        alpha = isDark ? 115 : 135;
        width = 1.25;
      } else if (isConnectedToSelected) {
        alpha = 240;
        width = 2.2;
      } else {
        alpha = isDark ? 45 : 60;
        width = 0.9;
      }

      final simPaint = Paint()
        ..color = cyanColor.withAlpha(alpha)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      _drawDashedLine(
        canvas,
        start,
        end,
        simPaint,
        dashLength: 6.0,
        spaceLength: 4.0,
      );
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
    final blueColor = isDark
        ? AppTheme.citationBlueDark
        : AppTheme.citationBlue;

    for (final edge in citationEdges) {
      final p1 = posMap[edge.source];
      final p2 = posMap[edge.target];
      if (p1 == null || p2 == null) continue;

      final targetRadius = radiusMap[edge.target] ?? 14.0;
      final sourceRadius = radiusMap[edge.source] ?? 14.0;

      final dx = p2.dx - p1.dx;
      final dy = p2.dy - p1.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= (sourceRadius + targetRadius)) continue;

      final isConnectedToSelected =
          selectedNodeId != null &&
          (edge.source == selectedNodeId || edge.target == selectedNodeId);

      final int alpha;
      final double width;
      if (selectedNodeId == null) {
        alpha = isDark ? 175 : 195;
        width = 1.45;
      } else if (isConnectedToSelected) {
        alpha = 255;
        width = 2.4;
      } else {
        alpha = isDark ? 50 : 65;
        width = 0.9;
      }

      final edgePaint = Paint()
        ..color = blueColor.withAlpha(alpha)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke;

      final arrowPaint = Paint()
        ..color = blueColor.withAlpha(alpha)
        ..style = PaintingStyle.fill;

      final ux = dx / dist;
      final uy = dy / dist;

      // Start just outside source node, end right at target node border
      final start = Offset(
        p1.dx + ux * sourceRadius,
        p1.dy + uy * sourceRadius,
      );
      final tip = Offset(p2.dx - ux * targetRadius, p2.dy - uy * targetRadius);

      canvas.drawLine(start, tip, edgePaint);

      // Draw directional arrowhead at tip pointing to cited target
      const arrowLength = 9.0;
      const arrowWidth = 5.0;

      final nx = -uy;
      final ny = ux;

      final baseCenter = Offset(
        tip.dx - ux * arrowLength,
        tip.dy - uy * arrowLength,
      );
      final corner1 = Offset(
        baseCenter.dx + nx * arrowWidth,
        baseCenter.dy + ny * arrowWidth,
      );
      final corner2 = Offset(
        baseCenter.dx - nx * arrowWidth,
        baseCenter.dy - ny * arrowWidth,
      );

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
      final isConnected =
          selectedNodeId != null && connectedNodeIds.contains(node.canonicalId);
      final isDimmed = selectedNodeId != null && !isConnected && !node.isOrigin;

      final baseColor = resolveNodeColor(node, isSelected);

      // 1. Origin Node Architectural Outer Ring (mirrors the PaperGraph mark)
      if (node.isOrigin) {
        final originRingPaint = Paint()
          ..color = (isDark ? Colors.white : const Color(0xFF18181B)).withAlpha(
            isDimmed ? 60 : 180,
          )
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pos, radius + 6.0, originRingPaint);
      }

      // 2. Selection Ring
      if (isSelected) {
        final selOuterRingPaint = Paint()
          ..color = (isDark ? Colors.white : const Color(0xFF18181B))
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(pos, radius + 5.0, selOuterRingPaint);
      }

      // 3. Node Base Subtle Shadow
      final shadowPaint = Paint()
        ..color = Colors.black.withAlpha(
          isDark ? (isDimmed ? 20 : 60) : (isDimmed ? 10 : 30),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawCircle(Offset(pos.dx, pos.dy + 1.5), radius, shadowPaint);

      // 4. Node Fill
      final nodePaint = Paint()
        ..color = isDimmed ? baseColor.withAlpha(isDark ? 105 : 135) : baseColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, radius, nodePaint);

      // 5. Border Accent Ring
      final borderPaint = Paint()
        ..color = isDark
            ? (isDimmed
                  ? Colors.white.withAlpha(15)
                  : Colors.white.withAlpha(50))
            : (isDimmed
                  ? Colors.black.withAlpha(15)
                  : Colors.white.withAlpha(160))
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pos, radius, borderPaint);

      // 6. Years remain useful on the focused/seed node and at closer zoom.
      // Hiding tiny years when zoomed out avoids unreadable visual noise.
      final showYear = isSelected || node.isOrigin || zoomScale >= 1.15;
      if (showYear && radius * zoomScale >= 11.0 && node.year != null) {
        final yearFontSize =
            ((isSelected || node.isOrigin ? 10.0 : 9.0) / zoomScale)
                .clamp(7.5, 13.0)
                .toDouble();
        final yearTextPainter = TextPainter(
          text: TextSpan(
            text: '${node.year}',
            style: TextStyle(
              color: isDimmed ? Colors.white.withAlpha(155) : Colors.white,
              fontSize: yearFontSize,
              fontWeight: FontWeight.w600,
              shadows: const [Shadow(color: Colors.black45, blurRadius: 1.5)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        yearTextPainter.paint(
          canvas,
          Offset(
            pos.dx - yearTextPainter.width / 2,
            pos.dy - yearTextPainter.height / 2,
          ),
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
    final candidates = List<GraphNode>.from(nodes)
      ..sort(
        (a, b) => _labelPriority(
          b,
          connectedNodeIds,
        ).compareTo(_labelPriority(a, connectedNodeIds)),
      );

    final int maxLabels;
    if (zoomScale < 0.52) {
      maxLabels = 3;
    } else if (zoomScale < 0.95) {
      maxLabels = 7;
    } else if (zoomScale < 1.55) {
      maxLabels = 12;
    } else {
      maxLabels = math.min(nodes.length, 20);
    }

    final occupiedRects = <Rect>[];
    int labelsPainted = 0;

    for (final node in candidates) {
      if (labelsPainted >= maxLabels) break;

      final pos = posMap[node.canonicalId]!;
      final radius = radiusMap[node.canonicalId]!;
      final isSelected = node.canonicalId == selectedNodeId;
      final isEssential = isSelected || node.isOrigin;
      final screenFontSize = isSelected ? 12.5 : (node.isOrigin ? 12.0 : 11.0);
      final canvasFontSize = (screenFontSize / zoomScale)
          .clamp(8.0, 28.0)
          .toDouble();
      final maxLabelWidth = ((isEssential ? 190.0 : 150.0) / zoomScale)
          .clamp(120.0, 260.0)
          .toDouble();

      final textSpan = TextSpan(
        text: node.displayTitle,
        style: TextStyle(
          color: isDark ? AppTheme.darkTextPrimary : const Color(0xFF0F172A),
          fontSize: canvasFontSize,
          height: 1.18,
          fontWeight: (isSelected || node.isOrigin)
              ? FontWeight.w700
              : FontWeight.w600,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        maxLines: isEssential ? 2 : 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxLabelWidth);

      final horizontalPadding = 6.0 / zoomScale;
      final verticalPadding = 3.5 / zoomScale;
      final gap = 7.0 / zoomScale;
      final candidateOffsets = [
        Offset(pos.dx - textPainter.width / 2, pos.dy + radius + gap),
        Offset(
          pos.dx - textPainter.width / 2,
          pos.dy - radius - gap - textPainter.height,
        ),
        Offset(pos.dx + radius + gap, pos.dy - textPainter.height / 2),
        Offset(
          pos.dx - radius - gap - textPainter.width,
          pos.dy - textPainter.height / 2,
        ),
      ];

      Offset? textOffset;
      Rect? labelRect;
      for (final offset in candidateOffsets) {
        final rect = Rect.fromLTWH(
          offset.dx - horizontalPadding,
          offset.dy - verticalPadding,
          textPainter.width + horizontalPadding * 2,
          textPainter.height + verticalPadding * 2,
        );
        final collisionPadding = 4.0 / zoomScale;
        final collides = occupiedRects.any(
          (occupied) => occupied.overlaps(rect.inflate(collisionPadding)),
        );
        if (!collides) {
          textOffset = offset;
          labelRect = rect;
          break;
        }
      }

      if (textOffset == null || labelRect == null) {
        if (!isEssential) continue;
        textOffset = candidateOffsets.first;
        labelRect = Rect.fromLTWH(
          textOffset.dx - horizontalPadding,
          textOffset.dy - verticalPadding,
          textPainter.width + horizontalPadding * 2,
          textPainter.height + verticalPadding * 2,
        );
      }

      final pillRect = RRect.fromRectAndRadius(
        labelRect,
        Radius.circular(6.0 / zoomScale),
      );

      final pillColor = isDark
          ? (isSelected
                ? AppTheme.darkCard
                : (node.isOrigin ? AppTheme.darkSurface : AppTheme.darkBg))
          : (isSelected
                ? const Color(0xFFF4F4F5)
                : (node.isOrigin ? const Color(0xFFF4F4F5) : Colors.white));

      final borderPillColor = isDark
          ? (isSelected ? Colors.white : AppTheme.darkBorder)
          : (isSelected ? const Color(0xFF18181B) : const Color(0xFFE2E8F0));

      final pillPaint = Paint()
        ..color = pillColor
        ..style = PaintingStyle.fill;

      final borderPillPaint = Paint()
        ..color = borderPillColor
        ..strokeWidth = (isSelected ? 1.5 : 1.0) / zoomScale
        ..style = PaintingStyle.stroke;

      canvas.drawRRect(pillRect, pillPaint);
      canvas.drawRRect(pillRect, borderPillPaint);
      textPainter.paint(canvas, textOffset);
      occupiedRects.add(labelRect);
      labelsPainted++;
    }
  }

  double _labelPriority(GraphNode node, Set<String> connectedNodeIds) {
    if (node.canonicalId == selectedNodeId) return 1000000000;
    if (node.isOrigin) return 900000000;

    var score = 0.0;
    if (connectedNodeIds.contains(node.canonicalId)) {
      score += 10000000;
    }
    score += (node.finalScore ?? 0) * 1000000;
    score += math.log(node.citationCount + 1) * 10000;
    return score;
  }

  @override
  bool shouldRepaint(covariant GraphCanvasPainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.isDark != isDark ||
        oldDelegate.zoomScale != zoomScale ||
        oldDelegate.draggedPositions != draggedPositions ||
        oldDelegate.citationEdges != citationEdges ||
        oldDelegate.similarityEdges != similarityEdges;
  }
}
