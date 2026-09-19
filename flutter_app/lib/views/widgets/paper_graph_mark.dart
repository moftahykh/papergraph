import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Reusable vector mark for PaperGraph.
///
/// Implements the exact academic geometric graph layout from the brand spec,
/// with bold, crisp contrast, proper canvas filling (no dead whitespace),
/// and support for both initial unfolding and continuous living pulse cycles.
class PaperGraphMark extends StatelessWidget {
  final double size;
  final bool? isDark;
  final double progress; // 0.0 to 1.0 (unfold progression, 1.0 = fully drawn)
  final double
  pulse; // continuous breathing value (e.g. from a looping controller)

  const PaperGraphMark({
    super.key,
    this.size = 64,
    this.isDark,
    this.progress = 1.0,
    this.pulse = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveDark =
        isDark ?? (Theme.of(context).brightness == Brightness.dark);

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PaperGraphMarkPainter(
          isDark: effectiveDark,
          progress: progress.clamp(0.0, 1.0),
          pulse: pulse,
        ),
      ),
    );
  }
}

class _PaperGraphMarkPainter extends CustomPainter {
  final bool isDark;
  final double progress;
  final double pulse;

  _PaperGraphMarkPainter({
    required this.isDark,
    required this.progress,
    required this.pulse,
  });

  // Quartic easing curve matching the HTML reference: 1 - (1 - t)^4
  double _ease(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return 1.0 - math.pow(1.0 - clamped, 4).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Tighter bounding scale (310 instead of 520) removes excessive margin,
    // making the graph bold, prominent, and clearly visible at any widget size.
    final scale = size.width / 310.0;
    final cx = size.width / 2.0;
    final cy = size.height / 2.0;

    // High-contrast, sharp minimal palette tokens
    final rootColor = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF18181B);
    final nodeColor = isDark
        ? const Color(0xFFE4E4E7)
        : const Color(0xFF27272A);
    // Clear, visible edge lines (0.40 alpha on dark, 0.32 alpha on light)
    final edgeColor = isDark
        ? const Color(0x66FFFFFF) // 40% white
        : const Color(0x52000000); // 32% black
    final ringColor = isDark
        ? const Color(0x38FFFFFF) // 22% white for dashed reference circle
        : const Color(0x2E000000);
    final archRingColor = isDark
        ? const Color(0x99FFFFFF) // 60% white for center architectural ring
        : const Color(0x80000000);

    // Elapsed virtual time in seconds (0.0 to 2.2s for unfold)
    final elapsed = progress * 2.2;

    // Living pulse breathing multiplier (when pulse > 0)
    final breathe = pulse > 0
        ? (1.0 + 0.08 * math.sin(pulse * 2 * math.pi))
        : 1.0;

    // 1. Concentric reference guide circle (radius: 95 in 310 space)
    final guideRadius =
        95.0 *
        scale *
        (pulse > 0 ? (1.0 + 0.02 * math.sin(pulse * 2 * math.pi)) : 1.0);
    final ringAlpha = (elapsed * 0.9).clamp(0.0, 1.0);
    if (ringAlpha > 0) {
      final ringPaint = Paint()
        ..color = ringColor.withValues(alpha: ringColor.a * ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, 1.2 * scale);

      _drawDashedCircle(canvas, Offset(cx, cy), guideRadius, ringPaint, 72);
    }

    // Relative node coordinates (bold, well-proportioned radii)
    final nodeDefs = [
      _NodeDef(0, 0.0, 0.0, 8.5, true, 0.05),
      _NodeDef(1, -65.0, -60.0, 5.5, false, 0.30),
      _NodeDef(2, 75.0, -50.0, 6.0, false, 0.40),
      _NodeDef(3, 65.0, 65.0, 5.2, false, 0.50),
      _NodeDef(4, -70.0, 60.0, 5.6, false, 0.60),
      _NodeDef(5, -130.0, -30.0, 4.2, false, 0.80),
      _NodeDef(6, 120.0, -100.0, 4.2, false, 0.90),
      _NodeDef(7, 135.0, 45.0, 4.2, false, 1.00),
      _NodeDef(8, -20.0, 125.0, 4.5, false, 1.10),
    ];

    final edges = [
      _EdgeDef(0, 1, 0.25, 0.5),
      _EdgeDef(0, 2, 0.35, 0.5),
      _EdgeDef(0, 3, 0.45, 0.5),
      _EdgeDef(0, 4, 0.55, 0.5),
      _EdgeDef(1, 5, 0.75, 0.5),
      _EdgeDef(2, 6, 0.85, 0.5),
      _EdgeDef(3, 7, 0.95, 0.5),
      _EdgeDef(4, 8, 1.05, 0.5),
      _EdgeDef(1, 2, 1.25, 0.6),
      _EdgeDef(3, 4, 1.35, 0.6),
    ];

    // 2. Vector connections drawn outward with solid crisp strokes
    final edgePaint = Paint()
      ..color = edgeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.3, 1.6 * scale);

    for (final edge in edges) {
      if (elapsed < edge.start) continue;
      final p = ((elapsed - edge.start) / edge.dur).clamp(0.0, 1.0);
      final t = _ease(p);

      final n1 = nodeDefs[edge.from];
      final n2 = nodeDefs[edge.to];

      final p1 = Offset(cx + n1.dx * scale, cy + n1.dy * scale);
      final p2 = Offset(cx + n2.dx * scale, cy + n2.dy * scale);

      final currentEnd = Offset(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );

      canvas.drawLine(p1, currentEnd, edgePaint);
    }

    // 3. Crisp geometric nodes with living breathing dynamics
    for (int i = 0; i < nodeDefs.length; i++) {
      final node = nodeDefs[i];
      if (elapsed < node.appearTime) continue;
      final p = ((elapsed - node.appearTime) / 0.35).clamp(0.0, 1.0);
      final nodeScale = _ease(p);

      // Micro breathing fluctuation for satellite nodes
      final nodeBreathe = pulse > 0
          ? (1.0 + 0.05 * math.sin((pulse + i * 0.12) * 2 * math.pi))
          : 1.0;

      final pos = Offset(cx + node.dx * scale, cy + node.dy * scale);
      final currentRadius = node.radius * scale * nodeScale * nodeBreathe;

      final fillPaint = Paint()
        ..color = node.isRoot ? rootColor : nodeColor
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pos, currentRadius, fillPaint);

      // Architectural ring on the root center node with living breath
      if (node.isRoot) {
        final archPaint = Paint()
          ..color = archRingColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.4, 1.8 * scale);

        final ringRadius = 18.0 * scale * nodeScale * breathe;
        canvas.drawCircle(pos, ringRadius, archPaint);
      }
    }
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
    int dashCount,
  ) {
    const sweep = 2 * math.pi / 72;
    for (int i = 0; i < dashCount; i += 2) {
      final startAngle = i * sweep;
      final arcAngle = sweep * 0.6;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGraphMarkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.isDark != isDark;
  }
}

class _NodeDef {
  final int id;
  final double dx;
  final double dy;
  final double radius;
  final bool isRoot;
  final double appearTime;

  const _NodeDef(
    this.id,
    this.dx,
    this.dy,
    this.radius,
    this.isRoot,
    this.appearTime,
  );
}

class _EdgeDef {
  final int from;
  final int to;
  final double start;
  final double dur;

  const _EdgeDef(this.from, this.to, this.start, this.dur);
}
