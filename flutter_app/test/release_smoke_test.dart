import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/cubits/graph/graph_cubit.dart';
import 'package:paper_graph/cubits/graph/graph_state.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/cubits/paper_details/paper_details_cubit.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/models/metric_result.dart';
import 'package:paper_graph/views/graph_view/connected_graph_view.dart';

class TestGraphCubit extends GraphCubit {
  TestGraphCubit(GraphState initial) : super() {
    emit(initial);
  }
}

GraphSnapshot createSmokeSnapshot({
  bool isPartial = false,
  bool isExpired = false,
}) {
  return GraphSnapshot(
    graphId: 'smoke-test-graph',
    origin: const GraphOrigin(
      id: 'origin-smoke',
      canonicalId: 'seed-smoke',
      title: 'Smoke Test Foundations of Deep Learning',
      year: 2018,
    ),
    status: isPartial ? GraphJobStatus.partial : GraphJobStatus.completed,
    createdAt: isExpired
        ? DateTime.now().subtract(const Duration(days: 20))
        : DateTime.now().subtract(const Duration(days: 1)),
    expiresAt: isExpired
        ? DateTime.now().subtract(const Duration(days: 6))
        : DateTime.now().add(const Duration(days: 13)),
    warnings: isPartial
        ? const [
            GraphWarning(
              code: 'DEGRADED_SOURCE',
              message: 'Semantic Scholar rate limited; degraded completeness.',
              severity: 'warning',
            )
          ]
        : const [],
    nodes: const [
      GraphNode(
        id: 'n-smoke-origin',
        canonicalId: 'seed-smoke',
        title: 'Smoke Test Foundations of Deep Learning',
        isOrigin: true,
        year: 2018,
        citationCount: 1500,
        x: 1000.0,
        y: 1000.0,
        archetype: 'seed',
        finalScore: 1.0,
        confidence: ConfidenceLevel.high,
        scores: {
          'wbc': MetricResult(value: 0.90, availability: MetricAvailability.available),
        },
      ),
      GraphNode(
        id: 'n-smoke-child',
        canonicalId: 'child-smoke',
        title: 'Deep Learning Scalability and Architecture',
        isOrigin: false,
        year: 2021,
        citationCount: 450,
        x: 1200.0,
        y: 1100.0,
        archetype: 'similar',
        finalScore: 0.85,
        confidence: ConfidenceLevel.medium,
        scores: {
          'wbc': MetricResult(value: 0.70, availability: MetricAvailability.available),
        },
      ),
    ],
    citationEdges: const [
      GraphEdge(
        source: 'child-smoke',
        target: 'seed-smoke',
        type: EdgeType.citation,
        directed: true,
        weight: 1.0,
      ),
    ],
    similarityEdges: const [],
  );
}

Widget createSmokeTestApp({
  required GraphCubit cubit,
  GraphSnapshot? initialSnapshot,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<GraphCubit>.value(value: cubit),
      BlocProvider<PaperDetailsCubit>(create: (_) => PaperDetailsCubit()),
      BlocProvider<LibraryCubit>(create: (_) => LibraryCubit()),
      BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: ConnectedGraphView(
          initialSnapshot: initialSnapshot,
        ),
      ),
    ),
  );
}

void main() {
  group('Release Smoke Tests: 4 Core UI States', () {
    testWidgets('1. Loading State renders progress bar, stage description, and cancel action', (tester) async {
      final cubit = TestGraphCubit(const GraphPolling(
        graphId: 'job-smoke-1',
        status: GraphJobStatus.computingWbc,
        currentStage: GraphJobStatus.computingWbc,
        progress: 0.55,
      ));

      await tester.pumpWidget(createSmokeTestApp(cubit: cubit));
      await tester.pump();

      // Verify progress indicators
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Verify stage description text
      expect(find.text('Computing Co-Citation (WBC) matrix...'), findsOneWidget);

      // Verify Cancel Job action button
      expect(find.text('Cancel Job'), findsOneWidget);

      // Verify Contextual "Notify me when done" opt-in button exists
      expect(find.text('Notify me when done'), findsOneWidget);
    });

    testWidgets('2. Error State renders error icon, error message, and retry button', (tester) async {
      final cubit = TestGraphCubit(const GraphError(
        'Could not connect to PaperGraph server. Connection refused.',
        canRetry: true,
        graphId: 'failed_job_1',
      ));

      await tester.pumpWidget(createSmokeTestApp(cubit: cubit));
      await tester.pump();

      // Verify error icon
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

      // Verify error title and message
      expect(find.text('Unable to Generate Graph'), findsOneWidget);
      expect(find.text('Could not connect to PaperGraph server. Connection refused.'), findsOneWidget);

      // Verify Retry button
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('3. Partial State renders graph canvas and persistent partial warning banner', (tester) async {
      final partialSnapshot = createSmokeSnapshot(isPartial: true);
      final cubit = TestGraphCubit(GraphLoaded(
        snapshot: partialSnapshot,
        isPartial: true,
        warnings: partialSnapshot.warnings,
      ));

      await tester.pumpWidget(createSmokeTestApp(
        cubit: cubit,
        initialSnapshot: partialSnapshot,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify CustomPaint graph canvas is rendered
      expect(find.byType(CustomPaint), findsWidgets);

      // Verify partial warning banner is present with warning message
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Semantic Scholar rate limited; degraded completeness.'), findsOneWidget);
    });

    testWidgets('4. Offline State renders cached snapshot with offline badge', (tester) async {
      final cachedSnapshot = createSmokeSnapshot(isPartial: false, isExpired: false);
      final cubit = TestGraphCubit(GraphLoaded(
        snapshot: cachedSnapshot,
        fromOfflineCache: true,
      ));

      await tester.pumpWidget(createSmokeTestApp(
        cubit: cubit,
        initialSnapshot: cachedSnapshot,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify offline cached badge is displayed
      expect(find.text('Offline Cached Graph Snapshot'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      // Verify canvas rendered
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
