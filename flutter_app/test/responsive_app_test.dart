import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/cubits/graph/graph_cubit.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/models/canonical_paper.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/models/metric_result.dart';
import 'package:paper_graph/views/favorites/favorites_view.dart';
import 'package:paper_graph/views/graph_view/widgets/graph_bottom_sheet.dart';

CanonicalPaper createSamplePaper({
  String id = 'nature-clofazimine-1',
  String title = 'Clofazimine broadly inhibits coronaviruses including SARS-CoV-2',
  List<String> authors = const ['S. Yuan', 'R. Wang', 'K. Y. Yuen'],
  int year = 2021,
  List<String> topics = const ['similar'],
}) {
  return CanonicalPaper(
    canonicalId: id,
    title: title,
    normalizedTitle: title.toLowerCase(),
    authors: authors.map((a) => Author(name: a)).toList(),
    year: year,
    citationCount: 184,
    topics: topics,
    venue: 'Nature',
    doi: '10.1038/s41586-021-03431-4',
  );
}

GraphSnapshot createSampleSnapshot({
  String id = 'cached-graph-1',
  String title = 'Deep Image Matting: A Comprehensive Survey',
}) {
  return GraphSnapshot(
    graphId: id,
    origin: GraphOrigin(
      id: 'origin-1',
      canonicalId: '10.1109/TPAMI.2023.1',
      title: title,
      year: 2023,
    ),
    status: GraphJobStatus.completed,
    schemaVersion: 1,
    algorithmVersion: 'v1.0-alpha',
    createdAt: DateTime.now(),
    expiresAt: DateTime.now().add(const Duration(days: 14)),
    nodes: [
      GraphNode(
        id: 'node-origin',
        canonicalId: '10.1109/TPAMI.2023.1',
        title: title,
        isOrigin: true,
        year: 2023,
        citationCount: 23,
        x: 1000.0,
        y: 1000.0,
        scores: const {
          'wbc': MetricResult(value: 0.95, availability: MetricAvailability.available),
          'ncc': MetricResult(value: 0.88, availability: MetricAvailability.available),
        },
        finalScore: 0.92,
      ),
      const GraphNode(
        id: 'node-connected',
        canonicalId: '10.1109/CVPR.2021.2',
        title: 'Deep Automatic Matting with Coarse Labels',
        isOrigin: false,
        year: 2021,
        citationCount: 88,
        x: 1150.0,
        y: 1100.0,
        scores: {
          'wbc': MetricResult(value: 0.75, availability: MetricAvailability.available),
          'ncc': MetricResult(value: 0.82, availability: MetricAvailability.available),
        },
        finalScore: 0.79,
      ),
    ],
    citationEdges: const [
      GraphEdge(source: 'node-connected', target: 'node-origin', type: EdgeType.citation),
    ],
    similarityEdges: const [
      GraphEdge(source: 'node-origin', target: 'node-connected', type: EdgeType.similarity, weight: 0.82),
    ],
  );
}

Widget buildTestableFavorites({
  required LibraryCubit libraryCubit,
  ThemeData? theme,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<LibraryCubit>.value(value: libraryCubit),
      BlocProvider<GraphCubit>(create: (_) => GraphCubit()),
      BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: const FavoritesView(),
    ),
  );
}

void main() {

  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoritesView Multi-Device Zero-Overflow Responsiveness Tests', () {
    const viewports = <String, Size>{
      'Ultra-Compact 320x568 (iPhone SE 1st gen)': Size(320, 568),
      'Compact Android 360x640 (Samsung Galaxy / Pixel 4a)': Size(360, 640),
      'Standard Mobile 390x844 (iPhone 13 / 14)': Size(390, 844),
      'Large Mobile 412x915 (Pixel 7 / Galaxy S23)': Size(412, 915),
      'Small Tablet / Foldable 600x960': Size(600, 960),
      'Tablet 800x1280': Size(800, 1280),
    };

    for (final entry in viewports.entries) {
      final name = entry.key;
      final size = entry.value;

      testWidgets('Renders saved papers with empty note with ZERO overflow on $name', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final paper1 = createSamplePaper(
          id: 'paper-1',
          title: 'Clofazimine broadly inhibits coronaviruses including SARS-CoV-2',
        );
        final paper2 = createSamplePaper(
          id: 'paper-2',
          title: 'Deep Image Matting: A Comprehensive Survey',
          year: 2023,
        );

        final libraryCubit = LibraryCubit.seeded(
          savedPapers: [paper1, paper2],
        );

        await tester.pumpWidget(buildTestableFavorites(libraryCubit: libraryCubit));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify title
        expect(find.text('Library'), findsOneWidget);

        // Verify top paper is visible
        expect(find.text('Clofazimine broadly inhibits coronaviruses including SARS-CoV-2'), findsOneWidget);

        // Verify all 4 action buttons exist
        expect(find.text('Explore graph'), findsWidgets);
        expect(find.byIcon(Icons.open_in_new_rounded), findsWidgets);

        // Crucial invariant: ZERO RenderFlex overflows thrown
        expect(tester.takeException(), isNull);
        await libraryCubit.close();
      });
    }

    testWidgets('Renders saved paper with existing note on compact 360x640 viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final paper = createSamplePaper();
      final libraryCubit = LibraryCubit.seeded(
        savedPapers: [paper],
        paperNotes: {
          paper.canonicalId: 'Crucial benchmark finding for antiviral efficacy.',
        },
      );

      await tester.pumpWidget(buildTestableFavorites(libraryCubit: libraryCubit));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Crucial benchmark finding for antiviral efficacy.'), findsOneWidget);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
      await libraryCubit.close();
    });

    testWidgets('Graphs tab renders on 320x568 & 360x640 viewports without overflow', (tester) async {
      for (final size in [const Size(320, 568), const Size(360, 640)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final snapshot = createSampleSnapshot();
        final libraryCubit = LibraryCubit.seeded(cachedGraphs: [snapshot]);

        await tester.pumpWidget(buildTestableFavorites(libraryCubit: libraryCubit));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Switch to Graphs tab and advance only the tab animation duration.
        await tester.tap(find.text('Graphs'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('Deep Image Matting: A Comprehensive Survey'), findsOneWidget);
        expect(find.text('Open graph'), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);

        // Zero overflow
        expect(tester.takeException(), isNull);
        await libraryCubit.close();
      }
    });
  });

  group('GraphBottomSheet Multi-Device Responsiveness Tests', () {
    testWidgets('Renders action bar and metrics with ZERO overflow on 320x568 and 360x640', (tester) async {
      for (final size in [const Size(320, 568), const Size(360, 640)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final snapshot = createSampleSnapshot();
        final nonOriginNode = snapshot.nodes[1]; // has Center graph button

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: GraphBottomSheet(
                snapshot: snapshot,
                selectedNode: nonOriginNode,
                onNodeSelected: (_) {},
                onRecenterGraph: (_) {},
                onOpenFullDetails: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final detailsList = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        );

        // The compact sheet lazily builds content below the fold. Scroll to
        // each section before asserting it exists.
        await tester.scrollUntilVisible(
          find.text('Shared references'),
          80,
          scrollable: detailsList,
        );
        await tester.pumpAndSettle();
        expect(find.text('Shared references'), findsOneWidget);
        expect(find.text('Co-citation'), findsOneWidget);
        expect(find.text('Overall relevance'), findsOneWidget);

        await tester.scrollUntilVisible(
          find.text('Paper details'),
          80,
          scrollable: detailsList,
        );
        await tester.pumpAndSettle();

        // Verify action buttons
        expect(find.text('Paper details'), findsOneWidget);
        expect(find.text('Center graph'), findsOneWidget);
        expect(find.byIcon(Icons.open_in_new_rounded), findsWidgets);

        // Zero overflow
        expect(tester.takeException(), isNull);
      }
    });
  });
}
