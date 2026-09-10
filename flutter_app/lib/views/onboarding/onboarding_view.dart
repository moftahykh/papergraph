import 'package:flutter/material.dart';
import '../../core/services/hive_service.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_view.dart';


class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});

  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends State<OnboardingView> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Visual Connected Research',
      'subtitle':
          'Explore visual relationship graphs between landmark research papers. Discover prior works and derivative papers at a glance.',
      'icon': Icons.hub_rounded,
      'gradient': [AppTheme.primaryBlue, AppTheme.accentCyan],
    },
    {
      'title': 'Smart Academic Citations',
      'subtitle':
          'Generate formatted APA, BibTeX, MLA, and Chicago citations instantly with one tap to paste straight into your bibliography.',
      'icon': Icons.format_quote_rounded,
      'gradient': [AppTheme.accentCyan, AppTheme.accentEmerald],
    },
    {
      'title': 'Offline Library & Biometric Vault',
      'subtitle':
          'Save your key literature offline with Hive and protect your private annotations and reading vault with fingerprint authentication.',
      'icon': Icons.fingerprint_rounded,
      'gradient': [AppTheme.accentEmerald, AppTheme.primaryLightBlue],
    },
  ];

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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppTheme.primaryBlue, AppTheme.accentCyan],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.hub_rounded, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'PaperGraph',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _onFinish,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Illustrated Icon Container
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: slide['gradient'],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (slide['gradient'][0] as Color).withAlpha(100),
                                blurRadius: 28,
                                spreadRadius: 4,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            slide['icon'],
                            size: 68,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 48),

                        // Title
                        Text(
                          slide['title'],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Subtitle
                        Text(
                          slide['subtitle'],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: isDark
                                ? AppTheme.darkTextSecondary
                                : AppTheme.lightTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Indicators & Buttons
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators
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
                              ? AppTheme.primaryLightBlue
                              : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                        ),
                      ),
                    ),
                  ),

                  // Next / Get Started Button
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
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == _slides.length - 1 ? 'Get Started' : 'Next',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
}
