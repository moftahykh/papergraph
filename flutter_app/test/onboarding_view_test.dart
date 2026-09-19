import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/views/onboarding/onboarding_view.dart';
import 'package:paper_graph/views/widgets/paper_graph_mark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tempDir = Directory.systemTemp.createTempSync(
      'papergraph_onboarding_test_',
    );
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.favoritesBoxName);
    await Hive.openBox(HiveService.settingsBoxName);
    await Hive.openBox(HiveService.canonicalPapersBoxName);
    await Hive.openBox(HiveService.cachedGraphsBoxName);
    await Hive.openBox(HiveService.paperNotesBoxName);
    HiveService.setActiveUserScope('test-user');
  });

  setUp(() async {
    await Hive.box(HiveService.settingsBoxName).clear();
    HiveService.setActiveUserScope('test-user');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget buildTestableOnboarding({
    VoidCallback? onFinish,
    Future<void> Function(bool completed)? persistCompletion,
  }) {
    return MaterialApp(
      home: OnboardingView(
        onFinish: onFinish,
        animatePulse: false,
        persistCompletion: persistCompletion,
      ),
    );
  }

  group('OnboardingView Redesign Tests', () {
    testWidgets('renders slide 1 with PaperGraph mark and brand title', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestableOnboarding());
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(PaperGraphMark), findsWidgets);
      expect(find.text('PaperGraph'), findsWidgets);
      expect(find.text('SKIP'), findsOneWidget);
      expect(find.text('01 / LITERATURE TOPOLOGY'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('advancing through slides renders topology and vault content', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestableOnboarding());
      await tester.pump(const Duration(milliseconds: 100));

      // Advance to Slide 2
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('02 / CITATION LINEAGES'), findsOneWidget);
      expect(
        find.text('From one seed paper to an entire scientific field'),
        findsOneWidget,
      );

      // Advance to Slide 3
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('03 / PRIVATE VAULT'), findsOneWidget);
      expect(find.text('Curate offline. Export citations.'), findsOneWidget);
      expect(find.text('Enter PaperGraph'), findsOneWidget);
      expect(find.text('BIBTEX READY'), findsOneWidget);
    });

    testWidgets('tapping Enter PaperGraph persists completion and finishes', (
      tester,
    ) async {
      var persisted = false;
      var finished = false;
      await tester.pumpWidget(
        buildTestableOnboarding(
          onFinish: () => finished = true,
          persistCompletion: (completed) async {
            persisted = completed;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Enter PaperGraph'), findsOneWidget);
      await tester.tap(find.text('Enter PaperGraph'));
      await tester.pump();

      expect(persisted, isTrue);
      expect(finished, isTrue);
    });

    testWidgets('tapping SKIP persists completion and finishes', (
      tester,
    ) async {
      var persisted = false;
      var finished = false;
      await tester.pumpWidget(
        buildTestableOnboarding(
          onFinish: () => finished = true,
          persistCompletion: (completed) async {
            persisted = completed;
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('SKIP'));
      await tester.pump();

      expect(persisted, isTrue);
      expect(finished, isTrue);
    });

    test(
      'Hive stores onboarding completion outside the widget test zone',
      () async {
        await HiveService.setOnboardingCompleted(true);
        expect(HiveService.isOnboardingCompleted(), isTrue);
      },
    );
  });
}
