import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../main_nav_view.dart';
import '../onboarding/onboarding_view.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _scaleAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeIn),
      ),
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    _controller.forward();

    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;

    final onboardingCompleted = HiveService.isOnboardingCompleted();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (onboardingCompleted || authProvider.isAuthenticated) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (context, animation, secondaryAnimation) => const MainNavigationView(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 800),
          pageBuilder: (context, animation, secondaryAnimation) => const OnboardingView(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: isDark
                ? [
                    const Color(0xFF1E293B),
                    AppTheme.darkBg,
                  ]
                : [
                    const Color(0xFFE2E8F0),
                    AppTheme.lightBg,
                  ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Custom Built Animated Connected Graph Logo
                SizedBox(
                  width: 180,
                  height: 180,
                  child: CustomPaint(
                    painter: _SplashGraphPainter(
                      progress: _controller.value,
                      rotation: _rotationAnimation.value,
                      primaryColor: AppTheme.primaryLightBlue,
                      accentColor: AppTheme.accentCyan,
                      emeraldColor: AppTheme.accentEmerald,
                    ),
                    child: Center(
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [AppTheme.primaryBlue, AppTheme.accentCyan],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryLightBlue.withAlpha(120),
                                blurRadius: 20,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.hub_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // Title with Fade & Scale
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [
                            AppTheme.primaryLightBlue,
                            AppTheme.accentCyan,
                            AppTheme.accentEmerald,
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          'PaperGraph',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Visual Connected Research & Literature Explorer',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Loading Indicator
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.accentCyan.withAlpha(200),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SplashGraphPainter extends CustomPainter {
  final double progress;
  final double rotation;
  final Color primaryColor;
  final Color accentColor;
  final Color emeraldColor;

  _SplashGraphPainter({
    required this.progress,
    required this.rotation,
    required this.primaryColor,
    required this.accentColor,
    required this.emeraldColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.42;

    const int nodeCount = 5;
    final linePaint = Paint()
      ..color = accentColor.withAlpha((180 * progress).toInt())
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..style = PaintingStyle.fill;

    for (int i = 0; i < nodeCount; i++) {
      final angle = (i * 2 * math.pi / nodeCount) + (rotation * 0.3);
      final currentRadius = radius * progress;
      final nodeOffset = Offset(
        center.dx + currentRadius * math.cos(angle),
        center.dy + currentRadius * math.sin(angle),
      );

      // Draw connecting lines from center to satellite nodes
      canvas.drawLine(center, nodeOffset, linePaint);

      // Draw cross connecting edges
      if (i > 0) {
        final prevAngle = ((i - 1) * 2 * math.pi / nodeCount) + (rotation * 0.3);
        final prevNodeOffset = Offset(
          center.dx + currentRadius * math.cos(prevAngle),
          center.dy + currentRadius * math.sin(prevAngle),
        );
        final crossPaint = Paint()
          ..color = primaryColor.withAlpha((100 * progress).toInt())
          ..strokeWidth = 1.2;
        canvas.drawLine(nodeOffset, prevNodeOffset, crossPaint);
      }

      // Draw satellite node with pulse
      nodePaint.color = (i % 2 == 0 ? emeraldColor : accentColor)
          .withAlpha((220 * progress).toInt());
      canvas.drawCircle(nodeOffset, 8 * progress, nodePaint);

      // Node glow
      final glowPaint = Paint()
        ..color = accentColor.withAlpha((60 * progress).toInt())
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawCircle(nodeOffset, 12 * progress, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplashGraphPainter oldDelegate) => true;
}
