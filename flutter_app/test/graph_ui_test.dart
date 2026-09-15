import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/core/utils/connection_reason_helper.dart';
import 'package:paper_graph/cubits/graph/graph_cubit.dart';
import 'package:paper_graph/cubits/graph/graph_state.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/cubits/paper_details/paper_details_cubit.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/models/metric_result.dart';
import 'package:paper_graph/views/graph_view/connected_graph_view.dart';
import 'package:paper_graph/views/graph_view/painters/graph_canvas_painter.dart';
import 'package:paper_graph/views/graph_view/widgets/graph_bottom_sheet.dart';
import 'package:paper_graph/views/graph_view/widgets/graph_year_legend.dart';

GraphSnapshot createSampleSnapshot({
  bool isPartial = false,
}) {
  return GraphSnapshot(
    graphId: 'test-graph-101',
    origin: const GraphOrigin(
      id: 'origin-seed',
      canonicalId: 'seed-paper',
      title: 'Attention Is All You Need',
      year: 2017,
    ),
    status: isPartial ? GraphJobStatus.partial : GraphJobStatus.completed,
    warnings: isPartial
        ? const [
            GraphWarning(
              code: 'PROVIDER_TIMEOUT',
              message: 'Crossref provider timed out; partial completeness.',
              severity: 'warning',
            )
          ]
        : const [],
    nodes: [
      const GraphNode(
        id: 'n-seed',
        canonicalId: 'seed-paper',
        title: 'Attention Is All You Need',
        isOrigin: true,
        year: 2017,
        citationCount: 95000,
        x: 1000.0,
        y: 1000.0,
        archetype: 'seed',
        finalScore: 1.0,
        confidence: ConfidenceLevel.high,
        scores: {
          'wbc': MetricResult(value: 0.95, availability: MetricAvailability.available),
          'ncc': MetricResult(value: 0.90, availability: MetricAvailability.available),
        },
      ),
      const GraphNode(
        id: 'n-prior',
        canonicalId: 'prior-paper-1',
        title: 'Neural Machine Translation by Jointly Learning to Align and Translate',
        year: 2014,
        citationCount: 28000,
        x: 850.0,
        y: 850.0,
        archetype: 'foundational',
        finalScore: 0.88,
        confidence: ConfidenceLevel.high,
        scores: {
          'prior_score': MetricResult(value: 0.92, availability: MetricAvailability.available),
          'wbc': MetricResult(value: 0.82, availability: MetricAvailability.available),
          'ncc': MetricResult(value: 0.78, availability: MetricAvailability.available),
        },
      ),
      const GraphNode(
        id: 'n-deriv',
        canonicalId: 'deriv-paper-1',
        title: 'BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding',
        year: 2018,
        citationCount: 75000,
        x: 1150.0,
        y: 1150.0,
        archetype: 'subsequent',
        finalScore: 0.94,
        confidence: ConfidenceLevel.high,
        scores: {
          'derivative_score': MetricResult(value: 0.96, availability: MetricAvailability.available),
          'wbc': MetricResult(value: 0.89, availability: MetricAvailability.available),
          'ncc': MetricResult(value: 0.85, availability: MetricAvailability.available),
        },
      ),
      const GraphNode(
        id: 'n-sim',
        canonicalId: 'sim-paper-1',
        title: 'Language Models are Few-Shot Learners (GPT-3)',
        year: 2020,
        citationCount: 42000,
        x: 1180.0,
        y: 880.0,
        archetype: 'subsequent',
        finalScore: 0.86,
        confidence: ConfidenceLevel.medium,
      ),
    ],
    citationEdges: const [
      GraphEdge(
        source: 'deriv-paper-1',
        target: 'seed-paper',
        type: EdgeType.citation,
        directed: true,
        weight: 0.95,
      ),
      GraphEdge(
        source: 'seed-paper',
        target: 'prior-paper-1',
        type: EdgeType.citation,
        directed: true,
        weight: 0.88,
      ),
    ],
    similarityEdges: const [
      GraphEdge(
        source: 'seed-paper',
        target: 'sim-paper-1',
        type: EdgeType.similarity,
        directed: false,
        weight: 0.76,
      ),
    ],
    createdAt: DateTime.now(),
  );
}

Widget createTestGraphApp({
  required GraphState graphState,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1.0,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<GraphCubit>(create: (_) => GraphCubit()),
      BlocProvider<LibraryCubit>(create: (_) => LibraryCubit.seeded()),
      BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
      BlocProvider<PaperDetailsCubit>(create: (_) => PaperDetailsCubit()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) => Directionality(
          textDirection: direction,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: ConnectedGraphView(
              initialSnapshot: graphState is GraphLoaded ? graphState.snapshot : null,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {

  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectionReasonHelper evidence tests', () {
    test('reports citation direction from snapshot edges', () {
      final snapshot = createSampleSnapshot();

      final citedByStart = ConnectionReasonHelper.explainConnection(
        node: snapshot.nodes[1],
        snapshot: snapshot,
      );
      final citesStart = ConnectionReasonHelper.explainConnection(
        node: snapshot.nodes[2],
        snapshot: snapshot,
      );

      expect(citedByStart.title, 'Cited by the starting paper');
      expect(citedByStart.evidence.single.value,
          'The starting paper cites this paper');
      expect(citesStart.title, 'Cites the starting paper');
      expect(citesStart.evidence.single.value,
          'This paper cites the starting paper');
    });

    test('shows the similarity value supplied by the graph snapshot', () {
      final snapshot = createSampleSnapshot();
      final explanation = ConnectionReasonHelper.explainConnection(
        node: snapshot.nodes[3],
        snapshot: snapshot,
      );

      expect(explanation.category, ConnectionCategory.similarity);
      expect(explanation.badgeLabel, '76% SIMILAR');
      expect(explanation.evidence.single.value, '76%');
      expect(explanation.evidenceLimited, isFalse);
    });

    test('labels date-only classification as limited evidence', () {
      final snapshot = createSampleSnapshot();
      const dateOnlyNode = GraphNode(
        id: 'date-only',
        canonicalId: 'date-only',
        title: 'Older paper without a recorded edge',
        year: 2010,
      );
      final explanation = ConnectionReasonHelper.explainConnection(
        node: dateOnlyNode,
        snapshot: snapshot,
      );

      expect(explanation.title, 'Published earlier');
      expect(explanation.evidenceLimited, isTrue);
      expect(explanation.description, contains('No direct citation'));
    });

    testWidgets('distinguishes a real zero score from missing data',
        (tester) async {
      final snapshot = createSampleSnapshot();
      const node = GraphNode(
        id: 'metric-test',
        canonicalId: 'metric-test',
        title: 'Metric availability test',
        year: 2017,
        finalScore: 0.5,
        scores: {
          'wbc': MetricResult(
            value: 0,
            availability: MetricAvailability.available,
          ),
          'ncc': MetricResult(
            availability: MetricAvailability.unavailable,
          ),
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphBottomSheet(
              snapshot: snapshot,
              selectedNode: node,
              onNodeSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Not enough data'), findsOneWidget);
    });
  });

  group('GraphCanvasPainter Mathematical & Visual Tests', () {
    test('computeNodeRadius bounds radius between 14.0 and 30.0', () {
      final rZero = GraphCanvasPainter.computeNodeRadius(0, 100000);
      final rMid = GraphCanvasPainter.computeNodeRadius(5000, 100000);
      final rMax = GraphCanvasPainter.computeNodeRadius(100000, 100000);
      final rSuperMax = GraphCanvasPainter.computeNodeRadius(500000, 100000);

      expect(rZero, equals(14.0));
      expect(rMid, greaterThan(14.0));
      expect(rMid, lessThan(30.0));
      expect(rMax, closeTo(30.0, 0.01));
      expect(rSuperMax, lessThanOrEqualTo(30.0));
    });

    test('calcMinYear and calcMaxYear calculate proper bounds', () {
      final snapshot = createSampleSnapshot();
      final minYear = GraphCanvasPainter.calcMinYear(snapshot.nodes);
      final maxYear = GraphCanvasPainter.calcMaxYear(snapshot.nodes);

      expect(minYear, equals(2014));
      expect(maxYear, equals(2020));
    });

    test('getNodeColor produces gradient transition from older to newer years', () {
      final snapshot = createSampleSnapshot();
      final painter = GraphCanvasPainter(
        nodes: snapshot.nodes,
        citationEdges: snapshot.citationEdges,
        similarityEdges: snapshot.similarityEdges,
      );

      final olderColor = painter.getNodeColor(2014);
      final newerColor = painter.getNodeColor(2020);

      expect(olderColor, isNot(equals(newerColor)));
      // Older should be near Mint Teal (green channel prominent)
      expect(olderColor.g, greaterThan(0.6));
      // Newer should be near Electric Blue (blue channel prominent)
      expect(newerColor.b, greaterThan(0.8));
    });
  });

  group('GraphYearLegend Widget Tests', () {
    testWidgets('renders year bounds and both edge type indicators', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GraphYearLegend(minYear: 2012, maxYear: 2024, isDark: true),
          ),
        ),
      );

      expect(find.text('2012'), findsOneWidget);
      expect(find.text('2024'), findsOneWidget);
      expect(find.text('Citation'), findsOneWidget);
      expect(find.text('Similarity'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_right_alt), findsOneWidget);
    });
  });

  group('GraphBottomSheet 4-Tab Navigation Tests', () {
    testWidgets('renders all 4 tabs and displays paper details', (tester) async {
      final snapshot = createSampleSnapshot();
      GraphNode? selectedNode = snapshot.nodes.first;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GraphBottomSheet(
              snapshot: snapshot,
              selectedNode: selectedNode,
              onNodeSelected: (n) => selectedNode = n,
            ),
          ),
        ),
      );

      // Verify all 4 tabs exist
      expect(find.text('Paper'), findsOneWidget);
      expect(find.text('Earlier works'), findsOneWidget);
      expect(find.text('Later works'), findsOneWidget);
      expect(find.text('All papers'), findsOneWidget);

      // Verify paper details
      expect(find.text('Attention Is All You Need'), findsOneWidget);
      expect(find.text('STARTING PAPER'), findsOneWidget);
      expect(find.text('Shared references'), findsOneWidget);
      expect(find.text('Co-citation'), findsOneWidget);
      expect(find.text('Overall relevance'), findsOneWidget);

      // Switch to Earlier works tab
      await tester.tap(find.text('Earlier works'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Neural Machine Translation'),
        findsOneWidget,
      );

      // Switch to Later works tab
      await tester.tap(find.text('Later works'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('BERT: Pre-training'),
        findsOneWidget,
      );

      // Switch to All papers tab
      await tester.tap(find.text('All papers'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Citations'), findsOneWidget);

      // Test paper list filtering
      await tester.enterText(find.byType(TextField), 'GPT-3');
      await tester.pumpAndSettle();
      expect(find.text('Language Models are Few-Shot Learners (GPT-3)'), findsOneWidget);
      expect(find.textContaining('BERT'), findsNothing);
    });
  });

  group('ConnectedGraphView Lifecycle & Interaction Tests', () {
    testWidgets('renders interactive canvas and year legend in loaded state', (tester) async {
      final snapshot = createSampleSnapshot();

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(snapshot: snapshot),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(GraphYearLegend), findsOneWidget);
      expect(find.text('Attention Is All You Need'), findsOneWidget);
      expect(
        find.textContaining(
          '4 papers · 2 citation links · 1 similarity link',
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays partial graph warning banner when isPartial is true', (tester) async {
      final partialSnapshot = createSampleSnapshot(isPartial: true);

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(
            snapshot: partialSnapshot,
            isPartial: true,
            warnings: partialSnapshot.warnings,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        find.textContaining('Crossref provider timed out; partial completeness.'),
        findsOneWidget,
      );
    });

    testWidgets('displays offline cached badge when fromOfflineCache is true', (tester) async {
      final snapshot = createSampleSnapshot();

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(
            snapshot: snapshot,
            fromOfflineCache: true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.text('Available offline'), findsOneWidget);
    });

    testWidgets('toggles bottom sheet details visibility via floating button', (tester) async {
      final snapshot = createSampleSnapshot();

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(snapshot: snapshot),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(GraphBottomSheet), findsNothing);

      // Tap floating button to open bottom sheet
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(GraphBottomSheet), findsOneWidget);

      // Tap close button in bottom sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(GraphBottomSheet), findsNothing);
    });
  });

  group('Arabic RTL & Small Screen Responsiveness Tests', () {
    testWidgets('renders Arabic RTL directionality without overflow', (tester) async {
      final snapshot = createSampleSnapshot();

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(snapshot: snapshot),
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('renders on compact small screen (320x568) without overflow', (tester) async {
      final snapshot = createSampleSnapshot();

      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(snapshot: snapshot),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('renders with 2.0x large accessibility text scaling without overflow', (tester) async {
      final snapshot = createSampleSnapshot();

      await tester.pumpWidget(
        createTestGraphApp(
          graphState: GraphLoaded(snapshot: snapshot),
          textScale: 2.0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}
