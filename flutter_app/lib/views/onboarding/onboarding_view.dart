import 'package:flutter/material.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_view.dart';

/// Onboarding built around the app's real identity: the PaperGraph logo and a
/// small hand-built graph motif that mirrors the actual graph canvas
/// (teal→blue year colors, amber origin ring, dashed similarity links).
/// No stock icon-in-a-gradient-circle slides.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _SlideData {
  final bool showLogo;
  final int variant;
  final String title;
  final String subtitle;
  const _SlideData({
    required this.showLogo,
    required this.variant,
    required this.title,
    required this.subtitle,
  });
}

class _OnboardingViewState extends State<OnboardingView>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _pulseController;
  int _currentPage = 0;

  static const List<_SlideData> _slides = [
    _SlideData(
      showLogo: true,
      variant: 0,
      title: 'PaperGraph',
      subtitle: 'See how research connects.',
    ),
    _SlideData(
      showLogo: false,
      variant: 0,
      title: 'From one paper to the whole field',
      subtitle:
          'Search any paper or paste its DOI. PaperGraph draws an interactive map of the works it builds on and the works that build on it.',
    ),
    _SlideData(
      showLogo: false,
      variant: 1,
      title: 'Save it. Read it offline. Cite it.',
      subtitle:
          'Keep papers and graphs in your on-device library, unlock them with your fingerprint, and copy a ready citation in one tap.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onFinish() async {
    await HiveService.setOnboardingCompleted(true);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginView()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: brand + skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        isDark
                            ? 'assets/images/logo_dark.png'
                            : 'assets/images/logo_light.png',
                        width: 26,
                        height: 26,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'PaperGraph',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _onFinish,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (slide.showLogo)
                          _buildLogoHero(isDark)
                        else
                          _buildGraphCard(slide.variant, isDark),
                        const SizedBox(height: 44),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: slide.showLogo ? 34 : 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          slide.subtitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Indicators + next button
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      _slides.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.only(right: 8),
                        width: _currentPage == index ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: _currentPage == index
                              ? AppTheme.primaryBlue
                              : (isDark
                                    ? AppTheme.darkBorder
                                    : AppTheme.lightBorder),
                        ),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (_currentPage < _slides.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _onFinish();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 16,
                      ),
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == _slides.length - 1
                              ? 'Get Started'
                              : 'Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Slide 1: the app's own logo as the hero — no stock illustrations.
  Widget _buildLogoHero(bool isDark) {
    return Container(
      width: 148,
      height: 148,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppTheme.darkCard : Colors.white,
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 60 : 18),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Center(
        child: Image.asset(
          isDark
              ? 'assets/images/logo_dark.png'
              : 'assets/images/logo_light.png',
          width: 92,
          height: 92,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// Slides 2-3: a hand-built mini graph in the same visual language as the
  /// real graph canvas (year colors, amber origin ring, dashed similarity).
  Widget _buildGraphCard(int variant, bool isDark) {
    return Container(
      height: 230,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, _) {
          return CustomPaint(
            painter: _MiniGraphPainter(
              variant: variant,
              pulse: _pulseController.value,
              isDark: isDark,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

/// Small decorative graph painter for onboarding — deliberately echoes the
/// real GraphCanvasPainter look so the intro honestly previews the product.
class _MiniGraphPainter extends CustomPainter {
  final int variant;
  final double pulse; // 0.0 .. 1.0
  final bool isDark;

  _MiniGraphPainter({
    required this.variant,
    required this.pulse,
    required this.isDark,
  });

  static const _yearColors = [
    Color(0xFF10B981), // teal — older
    Color(0xFF06B6D4), // cyan
    Color(0xFF2563EB), // blue — newer
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rel = variant == 0
        ? const [
            Offset(0.50, 0.50), // origin
            Offset(0.22, 0.28),
            Offset(0.42, 0.16),
            Offset(0.68, 0.22),
            Offset(0.82, 0.45),
            Offset(0.72, 0.72),
            Offset(0.30, 0.78),
            Offset(0.16, 0.55),
          ]
        : const [
            Offset(0.50, 0.44), // origin
            Offset(0.25, 0.30),
            Offset(0.50, 0.15),
            Offset(0.75, 0.30),
            Offset(0.68, 0.68),
            Offset(0.32, 0.68),
          ];
    final pts = rel
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();

    final citationTargets = variant == 0 ? [1, 2, 3, 4] : [1, 2, 3];
    final similarityPairs = variant == 0
        ? [
            [1, 2],
            [3, 4],
            [5, 6],
            [4, 5],
          ]
        : [
            [1, 2],
            [2, 3],
            [4, 5],
          ];

    final base = size.shortestSide;
    final originR = base * 0.070;
    double nodeR(int i) => i == 0 ? originR : base * (0.045 + 0.008 * (i % 3));

    // Similarity edges: dashed cyan (same meaning as the real canvas).
    final simPaint = Paint()
      ..color = const Color(0xFF06B6D4).withAlpha(isDark ? 120 : 150)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final pair in similarityPairs) {
      _drawDashedLine(canvas, pts[pair[0]], pts[pair[1]], simPaint);
    }

    // Citation edges: solid indigo from origin outward.
    final citPaint = Paint()
      ..color = (isDark ? const Color(0xFF4AC6E3) : AppTheme.primaryBlue)
          .withAlpha(isDark ? 170 : 190)
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (final t in citationTargets) {
      final p1 = pts[0];
      final p2 = pts[t];
      final d = (p2 - p1).distance;
      if (d <= originR + nodeR(t)) continue;
      final u = (p2 - p1) / d;
      canvas.drawLine(p1 + u * originR, p2 - u * nodeR(t), citPaint);
    }

    // Nodes colored by "year" position, origin last with amber ring + pulse.
    for (var i = 1; i < pts.length; i++) {
      final color = _yearColors[i % _yearColors.length];
      final r = nodeR(i);
      final shadow = Paint()
        ..color = Colors.black.withAlpha(isDark ? 70 : 30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
      canvas.drawCircle(pts[i] + const Offset(0, 1.5), r, shadow);
      canvas.drawCircle(pts[i], r, Paint()..color = color);
      canvas.drawCircle(
        pts[i],
        r,
        Paint()
          ..color = Colors.white.withAlpha(isDark ? 60 : 170)
          ..strokeWidth = 1.1
          ..style = PaintingStyle.stroke,
      );
    }

    final origin = pts[0];
    final halo = Paint()
      ..color = const Color(
        0xFFF59E0B,
      ).withAlpha((60 * (1.0 - pulse * 0.4)).toInt());
    canvas.drawCircle(origin, originR + 5.0 + pulse * 5.0, halo);
    canvas.drawCircle(
      origin,
      originR,
      Paint()..color = const Color(0xFF2563EB),
    );
    canvas.drawCircle(
      origin,
      originR + 2.5,
      Paint()
        ..color = const Color(0xFFF59E0B)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint, {
    double dash = 5.0,
    double gap = 4.0,
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
  bool shouldRepaint(covariant _MiniGraphPainter oldDelegate) {
    return oldDelegate.pulse != pulse ||
        oldDelegate.variant != variant ||
        oldDelegate.isDark != isDark;
  }
}
