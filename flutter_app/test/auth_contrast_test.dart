import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/providers/auth_provider.dart';
import 'package:paper_graph/views/auth/login_view.dart';
import 'package:paper_graph/views/auth/register_view.dart';
import 'package:provider/provider.dart';

Widget _buildAuthTestApp({required Widget child, required bool isDark}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
    ],
    child: MaterialApp(
      theme: isDark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('Auth Views High-Contrast & Anti-AI-Slop Tests', () {
    testWidgets('LoginView text buttons have high contrast in Light Mode', (tester) async {
      await tester.pumpWidget(_buildAuthTestApp(child: const LoginView(), isDark: false));
      await tester.pump();

      // Verify "Forgot Password?" text color is dark zinc in light mode (NOT white)
      final forgotTextFinder = find.text('Forgot Password?');
      expect(forgotTextFinder, findsOneWidget);
      final forgotWidget = tester.widget<Text>(forgotTextFinder);
      expect(forgotWidget.style?.color, isNotNull);
      expect((forgotWidget.style!.color!.r * 255).round(), lessThan(120));

      // Verify "Create Account" text color is ink black in light mode (NOT white)
      final createAccountFinder = find.text('Create Account');
      expect(createAccountFinder, findsOneWidget);
      final createAccountWidget = tester.widget<Text>(createAccountFinder);
      expect(createAccountWidget.style?.color, isNotNull);
      expect(createAccountWidget.style!.color, const Color(0xFF18181B));
    });

    testWidgets('LoginView text buttons have high contrast in Dark Mode', (tester) async {
      await tester.pumpWidget(_buildAuthTestApp(child: const LoginView(), isDark: true));
      await tester.pump();

      // Verify "Forgot Password?" is light gray in dark mode
      final forgotTextFinder = find.text('Forgot Password?');
      expect(forgotTextFinder, findsOneWidget);
      final forgotWidget = tester.widget<Text>(forgotTextFinder);
      expect(forgotWidget.style?.color, const Color(0xFFA1A1AA));

      // Verify "Create Account" is crisp white in dark mode
      final createAccountFinder = find.text('Create Account');
      expect(createAccountFinder, findsOneWidget);
      final createAccountWidget = tester.widget<Text>(createAccountFinder);
      expect(createAccountWidget.style?.color, Colors.white);
    });

    testWidgets('RegisterView "Sign In" text button has high contrast in Light Mode', (tester) async {
      await tester.pumpWidget(_buildAuthTestApp(child: const RegisterView(), isDark: false));
      await tester.pump();

      // Verify "Sign In" link is ink black in light mode (NOT invisible white)
      final signInFinder = find.text('Sign In');
      expect(signInFinder, findsOneWidget);
      final signInWidget = tester.widget<Text>(signInFinder);
      expect(signInWidget.style?.color, const Color(0xFF18181B));
    });

    testWidgets('RegisterView "Sign In" text button has high contrast in Dark Mode', (tester) async {
      await tester.pumpWidget(_buildAuthTestApp(child: const RegisterView(), isDark: true));
      await tester.pump();

      // Verify "Sign In" link is crisp white in dark mode
      final signInFinder = find.text('Sign In');
      expect(signInFinder, findsOneWidget);
      final signInWidget = tester.widget<Text>(signInFinder);
      expect(signInWidget.style?.color, Colors.white);
    });
  });
}
