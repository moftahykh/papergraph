import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_view.dart';
import '../widgets/paper_graph_mark.dart';

/// Minimalist, academic onboarding built around the PaperGraph identity.
/// Strictly adheres to the obsidian / paper-and-ink design language:
/// pure monochrome typography, geometric vector marks, and zero generic gradients.
class OnboardingView extends StatefulWidget {
  final VoidCallback? onFinish;
  final bool animatePulse;
  final Future<void> Function(bool completed)? persistCompletion;

  const OnboardingView({
    super.key,
    this.onFinish,
    this.animatePulse = true,
    this.persistCompletion,
  });

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _SlideContent {
  final String tag;
  final String title;
  final String subtitle;
  final bool isSerifTitle;

  const _SlideContent({
    required this.tag,
    required this.title,
    required this.subtitle,
    this.isSerifTitle = false,
  });
}

class _OnboardingViewState extends State<OnboardingView>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _pulseController;
  int _currentPage = 0;

  static const List<_SlideContent> _slides = [
    _SlideContent(
      tag: '01 / LITERATURE TOPOLOGY',
      title: 'PaperGraph',
      isSerifTitle: true,
      subtitle:
          'The living map of scientific literature. Discover foundational antecedents, emerging derivative works, and uncharted research connections.',
    ),
    _SlideContent(
      tag: '02 / CITATION LINEAGES',
      title: 'From one seed paper to an entire scientific field',
      subtitle:
          'Search any paper or paste its DOI. PaperGraph draws an interactive topological web of direct citations, co-citations, and conceptual bridges.',
    ),
    _SlideContent(
      tag: '03 / PRIVATE VAULT',
      title: 'Curate offline. Export citations.',
      subtitle:
          'Archive literature graphs and full papers directly on your device. Biometric privacy, zero telemetry, and instant BibTeX formatting in one tap.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.animatePulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onFinish() async {
    final persist =
        widget.persistCompletion ?? HiveService.setOnboardingCompleted;
    await persist(true);
    if (!mounted) {
      return;
    }
    if (widget.onFinish != null) {
      widget.onFinish!();
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final borderColor = isDark
        ? AppTheme.darkBorder
        : AppTheme.lightBorder;
    final buttonBg = isDark ? Colors.white : const Color(0xFF18181B);
    final buttonFg = isDark ? const Color(0xFF09090B) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Brand Mark + Name + Skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      PaperGraphMark(
                        size: 22,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'PaperGraph',
                        style: AppTheme.brandTitleStyle(
                          fontSize: 22,
                          color: textPrimary,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _onFinish,
                    style: TextButton.styleFrom(
                      foregroundColor: textSecondary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      'SKIP',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Slide Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 10),

                        // Eyebrow Tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withAlpha(8)
                                : Colors.black.withAlpha(6),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: borderColor,
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            slide.tag,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: textSecondary,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Hero Stage
                        if (index == 0)
                          _buildBrandHero(isDark)
                        else if (index == 1)
                          _buildTopologyHero(isDark)
                        else
                          _buildVaultHero(isDark),

                        const SizedBox(height: 36),

                        // Slide Title
                        if (slide.isSerifTitle)
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: AppTheme.brandTitleStyle(
                              fontSize: 44,
                              color: textPrimary,
                            ),
                          )
                        else
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.4,
                              height: 1.25,
                              color: textPrimary,
                            ),
                          ),

                        const SizedBox(height: 14),

                        // Subtitle
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: Text(
                            slide.subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              letterSpacing: 0.1,
                              color: textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Navigation: Indicator + Next / Finish Button
            Container(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: borderColor,
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Minimal Monoline Step Indicators
                  Row(
                    children: List.generate(
                      _slides.length,
                      (index) => GestureDetector(
                        onTap: () {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 6),
                          width: _currentPage == index ? 26 : 8,
                          height: 3,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(1.5),
                            color: _currentPage == index
                                ? textPrimary
                                : borderColor,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Actions: Back (if > 0) + Next
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentPage > 0) ...[
                        IconButton(
                          onPressed: () {
                            _pageController.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          color: textSecondary,
                          tooltip: 'Previous',
                        ),
                        const SizedBox(width: 8),
                      ],
                      ElevatedButton(
                        onPressed: () {
                          if (_currentPage < _slides.length - 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeInOut,
                            );
                          } else {
                            _onFinish();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: buttonBg,
                          foregroundColor: buttonFg,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _currentPage == _slides.length - 1
                                  ? 'Enter PaperGraph'
                                  : 'Next',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: buttonFg,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 15,
                              color: buttonFg,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Slide 1 Hero: The living architectural brand mark
  Widget _buildBrandHero(bool isDark) {
    return Container(
      width: 230,
      height: 230,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 10),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle outer dashed reference guide
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return CustomPaint(
                size: const Size(210, 210),
                painter: _DashedCirclePainter(
                  color: isDark
                      ? Colors.white.withAlpha(20)
                      : Colors.black.withAlpha(15),
                ),
              );
            },
          ),
          // Living architectural mark
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return PaperGraphMark(
                size: 140,
                isDark: isDark,
                pulse: _pulseController.value,
              );
            },
          ),
        ],
      ),
    );
  }

  /// Slide 2 Hero: Minimal academic citation topology diagram
  Widget _buildTopologyHero(bool isDark) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 230),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Coordinate corner badges
          Positioned(
            top: 10,
            left: 12,
            child: Text(
              'TOPOLOGY / CITATION_WEB',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 1.0,
                color: (isDark ? Colors.white : Colors.black).withAlpha(60),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            right: 12,
            child: Text(
              '24 NODES • 62 EDGES',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                letterSpacing: 0.8,
                color: (isDark ? Colors.white : Colors.black).withAlpha(60),
              ),
            ),
          ),
          // Vector graph painter
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return CustomPaint(
                painter: _MinimalGraphPainter(
                  pulse: _pulseController.value,
                  isDark: isDark,
                ),
                child: const SizedBox.expand(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Slide 3 Hero: Tactile academic vault & citation card
  Widget _buildVaultHero(bool isDark) {
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final cardBg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final textPrimary = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 8),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Status Pills
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 13,
                      color: textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'LOCAL VAULT',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9.0,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withAlpha(12)
                      : Colors.black.withAlpha(8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'BIBTEX READY',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Paper Title Mockup
          Text(
            'Attention Is All You Need',
            style: AppTheme.brandTitleStyle(
              fontSize: 20,
              color: textPrimary,
            ),
          ),

          const SizedBox(height: 4),

          // Paper Metadata
          Text(
            'Vaswani, Shazeer, Parmar et al. • arXiv:1706.03762 • 2017',
            style: TextStyle(
              fontSize: 11,
              color: textSecondary,
              letterSpacing: 0.1,
            ),
          ),

          const SizedBox(height: 12),

          // BibTeX Snippet Box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF09090B)
                  : const Color(0xFFECECEC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 0.8),
            ),
            child: Text(
              '@article{vaswani2017attention,\n'
              '  title={Attention Is All You Need},\n'
              '  author={Vaswani, Ashish and ...},\n'
              '  journal={NeurIPS}, year={2017}\n'
              '}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.5,
                height: 1.45,
                color: isDark
                    ? const Color(0xFFA1A1AA)
                    : const Color(0xFF52525B),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Bottom Verification Row
          Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 13,
                color: textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Graph topology & PDF stored on device',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Architectural dashed circle guide painter
class _DashedCirclePainter extends CustomPainter {
  final Color color;
  _DashedCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const dashCount = 48;
    const sweep = (math.pi * 2) / dashCount;
    for (int i = 0; i < dashCount; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Precision minimal academic graph painter.
/// Follows the HTML reference: monochrome obsidian/zinc nodes, architectural
/// concentric origin ring, subtle hairline vector connections, and directional indicators.
class _MinimalGraphPainter extends CustomPainter {
  final double pulse; // 0.0 .. 1.0
  final bool isDark;

  _MinimalGraphPainter({
    required this.pulse,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final cy = size.height * 0.52;

    final primaryColor = isDark ? Colors.white : const Color(0xFF18181B);
    final nodeSecondary = isDark ? const Color(0xFFD4D4D8) : const Color(0xFF3F3F46);
    final edgeColor = (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 45 : 35);
    final dashEdgeColor = (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 30 : 25);
    final ringColor = (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 25 : 18);

    // Nodes geometry relative to center
    final nodes = [
      Offset(cx, cy), // Origin / Root
      Offset(cx - 72, cy - 48), // Foundation 1
      Offset(cx + 80, cy - 42), // Derivative 1
      Offset(cx + 68, cy + 54), // Derivative 2
      Offset(cx - 78, cy + 50), // Foundation 2
      Offset(cx - 138, cy - 18), // Remote antecedent
      Offset(cx + 128, cy - 80), // Cross reference
      Offset(cx + 144, cy + 34), // Late derivative
      Offset(cx - 24, cy + 90), // Sub-cluster
    ];

    // Node radii
    final radii = [7.0, 4.5, 4.5, 4.0, 4.2, 3.2, 3.2, 3.0, 3.2];

    // Concentric dashed guide ring around origin
    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    _drawDashedCircle(canvas, Offset(cx, cy), 96.0, ringPaint);

    // Edges (solid citation links)
    final edges = [
      [0, 1],
      [0, 2],
      [0, 3],
      [0, 4],
      [1, 5],
      [2, 6],
      [3, 7],
      [4, 8],
    ];

    final edgePaint = Paint()
      ..color = edgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final edge in edges) {
      final p1 = nodes[edge[0]];
      final p2 = nodes[edge[1]];
      canvas.drawLine(p1, p2, edgePaint);
    }

    // Dashed similarity bridges
    final dashEdges = [
      [1, 2],
      [3, 4],
      [6, 7],
    ];

    final dashPaint = Paint()
      ..color = dashEdgeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (final edge in dashEdges) {
      _drawDashedLine(canvas, nodes[edge[0]], nodes[edge[1]], dashPaint);
    }

    // Satellite nodes
    for (int i = 1; i < nodes.length; i++) {
      final pos = nodes[i];
      final r = radii[i];

      // Subtle shadow
      canvas.drawCircle(
        pos + const Offset(0, 1.2),
        r,
        Paint()..color = Colors.black.withAlpha(isDark ? 50 : 20),
      );

      // Node body
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = nodeSecondary,
      );

      // Outer crisp stroke
      canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = (isDark ? Colors.white : Colors.black).withAlpha(50)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
      );
    }

    // Origin Root Node (Center) with architectural double ring
    final originPos = nodes[0];
    final originR = radii[0];

    // Living breathing architectural outer halo
    final haloPaint = Paint()
      ..color = primaryColor.withAlpha((18 * (1.0 - pulse * 0.3)).toInt())
      ..style = PaintingStyle.fill;
    canvas.drawCircle(originPos, 18.0 + pulse * 4.0, haloPaint);

    // Architectural outer ring
    final archRingPaint = Paint()
      ..color = primaryColor.withAlpha(isDark ? 80 : 60)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawCircle(originPos, 14.0, archRingPaint);

    // Inner origin solid node
    canvas.drawCircle(
      originPos,
      originR,
      Paint()..color = primaryColor,
    );

    // Center micro core
    canvas.drawCircle(
      originPos,
      2.0,
      Paint()..color = isDark ? const Color(0xFF09090B) : Colors.white,
    );
  }

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    int count = 40,
  }) {
    const sweep = (math.pi * 2) / 40;
    for (int i = 0; i < count; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep,
        false,
        paint,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dash = 4.0,
    double gap = 3.5,
  }) {
    final diff = p2 - p1;
    final dist = diff.distance;
    if (dist <= 0.001) return;
    final u = diff / dist;
    var covered = 0.0;
    while (covered < dist) {
      final start = p1 + u * covered;
      covered += dash;
      final end = p1 + u * (covered > dist ? dist : covered);
      canvas.drawLine(start, end, paint);
      covered += gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MinimalGraphPainter oldDelegate) {
    return oldDelegate.pulse != pulse || oldDelegate.isDark != isDark;
  }
}
