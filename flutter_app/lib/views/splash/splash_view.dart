import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../auth/login_view.dart';
import '../main_nav_view.dart';
import '../onboarding/onboarding_view.dart';
import '../widgets/paper_graph_mark.dart';

class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _brandFade;
  late Animation<double> _footerFade;

  @override
  void initState() {
    super.initState();
    // Warm the backend in parallel with the branded startup animation.
    // This must remain non-blocking so the native/Flutter splash never waits
    // on Render or any remote provider.
    PaperGraphApiClient().checkHealth();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    );

    _brandFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.08, 0.35, curve: Curves.easeOutCubic),
      ),
    );

    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: 4500));
    if (!mounted) return;

    final onboardingCompleted = HiveService.isOnboardingCompleted();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (!onboardingCompleted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const OnboardingView(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      return;
    }

    if (!authProvider.isAuthenticated) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const LoginView(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MainNavigationView(
              requireInitialUnlock: HiveService.isBiometricsEnabled(),
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.darkBg : AppTheme.lightBg;
    final textPrimary = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textMuted = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;
    final barTrack = isDark ? const Color(0x14FFFFFF) : const Color(0x14000000);
    final barFill = isDark ? Colors.white : const Color(0xFF18181B);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final progress = _controller.value;
            // Unfold smoothly across the first 2.5s (0.55 of duration)
            final graphProgress = (progress / 0.55).clamp(0.0, 1.0);
            // Continuous living pulse that breathes for the rest of the splash
            final pulseProgress = progress > 0.40
                ? (progress - 0.40) * 3.5
                : 0.0;

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(height: 10),

                    // Central Connected Mark & Typography Lockup
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Prominent Geometric Vector Mark with Living Pulse
                        PaperGraphMark(
                          size: 280,
                          isDark: isDark,
                          progress: graphProgress,
                          pulse: pulseProgress,
                        ),
                        const SizedBox(height: 32),

                        // Brand Title in Instrument Serif Italic
                        FadeTransition(
                          opacity: _brandFade,
                          child: Column(
                            children: [
                              Text(
                                'PaperGraph',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.instrumentSerif(
                                  fontSize: 46,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w400,
                                  color: textPrimary,
                                  letterSpacing: -0.5,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'LITERATURE INTELLIGENCE',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w400,
                                  color: textMuted,
                                  letterSpacing: 2.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Monoline Hairline Status Line
                    FadeTransition(
                      opacity: _footerFade,
                      child: SizedBox(
                        width: 180,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1px hairline track
                            Container(
                              height: 1.5,
                              width: 180,
                              decoration: BoxDecoration(
                                color: barTrack,
                                borderRadius: BorderRadius.circular(1),
                              ),
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: progress.clamp(0.0, 1.0),
                                child: Container(
                                  height: 1.5,
                                  decoration: BoxDecoration(
                                    color: barFill,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'LOADING PAPERGRAPH',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                                letterSpacing: 1.5,
                                color: textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
