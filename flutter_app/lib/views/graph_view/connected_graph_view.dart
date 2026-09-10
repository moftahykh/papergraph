import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/paper_model.dart';
import '../../providers/papers_provider.dart';
import '../paper_details/paper_details_view.dart';

class ConnectedGraphView extends StatefulWidget {
  final PaperModel centerPaper;

  const ConnectedGraphView({super.key, required this.centerPaper});

  @override
  State<ConnectedGraphView> createState() => _ConnectedGraphViewState();
}

class _ConnectedGraphViewState extends State<ConnectedGraphView>
    with SingleTickerProviderStateMixin {
  late PaperModel _activePaper;
  late AnimationController _pulseController;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    _activePaper = widget.centerPaper;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _switchCenterPaper(PaperModel newCenter) {
    setState(() {
      _activePaper = newCenter;
    });
    _resetZoom();
  }

  void _showPaperPreviewModal(PaperModel paper) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    paper.category,
                    style: const TextStyle(
                      color: AppTheme.primaryLightBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${paper.year} • ${paper.citationsCount} citations',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              paper.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              paper.authors.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _switchCenterPaper(paper);
                    },
                    icon: const Icon(Icons.hub_rounded, size: 18),
                    label: const Text('Re-center Graph'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PaperDetailsView(paper: paper),
                        ),
                      );
                    },
                    icon: const Icon(Icons.menu_book_rounded, size: 18),
                    label: const Text('View Details'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showGraphInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppTheme.accentCyan),
            SizedBox(width: 10),
            Text('About Connected Graphs'),
          ],
        ),
        content: const Text(
          'PaperGraph builds a similarity graph inspired by Connected Papers.\n\n'
          '• Central Node: The origin research paper.\n'
          '• Orbiting Nodes: Relevant prior and derivative research papers.\n'
          '• Connecting Lines: Represent shared citations and semantic similarity.\n\n'
          'Tip: Pinch to zoom in/out, drag to explore, and tap any node to inspect or re-center the network.',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final papersProvider = Provider.of<PapersProvider>(context);
    final connectedPapers = papersProvider.getConnectedPapers(_activePaper);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected Papers Graph'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: 'Graph Info',
            onPressed: _showGraphInfoDialog,
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong_rounded),
            tooltip: 'Reset Zoom',
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Grid / Canvas
          Positioned.fill(
            child: Container(
              color: isDark ? AppTheme.darkBg : AppTheme.lightBg,
            ),
          ),

          // Interactive Graph Canvas
          InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: const EdgeInsets.all(500),
            minScale: 0.4,
            maxScale: 2.5,
            child: Center(
              child: SizedBox(
                width: 700,
                height: 700,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    return Stack(
                      children: [
                        // Graph Lines Painter
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GraphLinesPainter(
                              nodeCount: connectedPapers.length,
                              pulseValue: _pulseController.value,
                              isDark: isDark,
                            ),
                          ),
                        ),

                        // Center Node (Active Paper)
                        Center(
                          child: GestureDetector(
                            onTap: () => _showPaperPreviewModal(_activePaper),
                            child: _buildCenterNodeWidget(_activePaper, isDark),
                          ),
                        ),

                        // Orbiting Nodes (Connected Papers)
                        ...List.generate(connectedPapers.length, (index) {
                          final paper = connectedPapers[index];
                          final angle = (index * 2 * math.pi / connectedPapers.length) - (math.pi / 2);
                          const double radius = 220.0;
                          final double x = 350 + radius * math.cos(angle);
                          final double y = 350 + radius * math.sin(angle);

                          return Positioned(
                            left: x - 65,
                            top: y - 45,
                            child: GestureDetector(
                              onTap: () => _showPaperPreviewModal(paper),
                              child: _buildSatelliteNodeWidget(paper, isDark, index),
                            ),
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // Top Info Banner
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: (isDark ? AppTheme.darkSurface : Colors.white).withAlpha(230),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(20),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_rounded, color: AppTheme.accentCyan, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pinch & zoom to explore • Tap nodes to re-center',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accentEmerald.withAlpha(30),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${connectedPapers.length} Connected',
                      style: const TextStyle(
                        color: AppTheme.accentEmerald,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterNodeWidget(PaperModel paper, bool isDark) {
    return Container(
      width: 130,
      height: 130,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [AppTheme.primaryLightBlue, AppTheme.primaryBlue],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryLightBlue.withAlpha((100 + 50 * _pulseController.value).toInt()),
            blurRadius: 28,
            spreadRadius: 6 * _pulseController.value,
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
          const SizedBox(height: 4),
          Text(
            paper.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${paper.year}',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildSatelliteNodeWidget(PaperModel paper, bool isDark, int index) {
    final colors = [
      AppTheme.accentCyan,
      AppTheme.accentEmerald,
      AppTheme.accentAmber,
      AppTheme.primaryLightBlue,
    ];
    final color = colors[index % colors.length];

    return Container(
      width: 130,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(40),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                '${paper.year}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
              const Spacer(),
              const Icon(Icons.open_in_new_rounded, size: 12, color: AppTheme.darkTextSecondary),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            paper.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphLinesPainter extends CustomPainter {
  final int nodeCount;
  final double pulseValue;
  final bool isDark;

  _GraphLinesPainter({
    required this.nodeCount,
    required this.pulseValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const double radius = 220.0;

    final linePaint = Paint()
      ..color = (isDark ? AppTheme.accentCyan : AppTheme.primaryBlue).withAlpha((110 + 40 * pulseValue).toInt())
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    final crossLinePaint = Paint()
      ..color = (isDark ? AppTheme.darkBorder : AppTheme.lightBorder).withAlpha(140)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final List<Offset> satelliteOffsets = [];

    for (int i = 0; i < nodeCount; i++) {
      final angle = (i * 2 * math.pi / nodeCount) - (math.pi / 2);
      final offset = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      satelliteOffsets.add(offset);

      // Draw line from center to satellite
      canvas.drawLine(center, offset, linePaint);
    }

    // Draw cross connections between adjacent satellites
    for (int i = 0; i < satelliteOffsets.length; i++) {
      final nextOffset = satelliteOffsets[(i + 1) % satelliteOffsets.length];
      canvas.drawLine(satelliteOffsets[i], nextOffset, crossLinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphLinesPainter oldDelegate) => true;
}
