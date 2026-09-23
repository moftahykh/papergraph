import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/main.dart';
import 'package:paper_graph/views/splash/splash_view.dart';

/// App-boot smoke test.
///
/// CI-safe version. The original test pumped the full app and then called
/// `pumpAndSettle()`, which never returns because the splash screen runs a
/// repeating Lottie animation — so the test always timed out. It also ran
/// without initializing Hive, which AuthProvider/ThemeCubit touch at startup.
///
/// This version boots Hive from a temp directory (path_provider has no
/// platform channel in tests, so Hive.initFlutter() cannot be used) and
/// advances the fake clock manually instead of pumpAndSettle().
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('papergraph_test_hive');
    Hive.init(dir.path);
    // Open every box the app touches during startup (mirrors HiveService.init,
    // which itself depends on path_provider and is therefore unusable here).
    await Hive.openBox(HiveService.favoritesBoxName);
    await Hive.openBox(HiveService.settingsBoxName);
    await Hive.openBox(HiveService.canonicalPapersBoxName);
    await Hive.openBox(HiveService.cachedGraphsBoxName);
    await Hive.openBox(HiveService.paperNotesBoxName);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  testWidgets('App boots into splash and navigates after the timer', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const PaperGraphApp());

    // First frame: the app and its splash screen are on stage.
    expect(find.byType(PaperGraphApp), findsOneWidget);
    expect(find.byType(SplashView), findsOneWidget);

    // Fire the splash's 2.4-second navigation timer. A plain pump(duration)
    // advances the fake clock without waiting for animations — unlike
    // pumpAndSettle(), which would hang forever on the looping Lottie.
    await tester.pump(const Duration(seconds: 6));
    // Run the 800ms fade transition to the next screen.
    await tester.pump(const Duration(seconds: 1));

    // Splash is gone — the app reached onboarding/home without crashing.
    expect(find.byType(SplashView), findsNothing);
  });
}
