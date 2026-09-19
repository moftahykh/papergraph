import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/cubits/graph/graph_cubit.dart';
import 'package:paper_graph/cubits/graph/graph_state.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/cubits/search/search_cubit.dart';
import 'package:paper_graph/cubits/theme/theme_cubit.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/providers/auth_provider.dart';
import 'package:paper_graph/providers/favorites_provider.dart';
import 'package:paper_graph/views/graph_view/connected_graph_view.dart';
import 'package:paper_graph/views/home/recent_graphs_view.dart';
import 'package:paper_graph/views/widgets/notification_toast_overlay.dart';
import 'package:provider/provider.dart';
import 'test_hive.dart';

GraphSnapshot _mockSnapshot({
  String id = 'graph-test-1',
  String title = 'Quantum Computing in 2026',
}) {
  return GraphSnapshot(
    graphId: id,
    origin: GraphOrigin(
      id: 'origin-1',
      canonicalId: '10.1000/182',
      title: title,
      year: 2026,
    ),
    status: GraphJobStatus.completed,
    schemaVersion: 1,
    algorithmVersion: 'v1.0',
    createdAt: DateTime.now(),
    nodes: [
      GraphNode(
        id: 'node-seed',
        canonicalId: '10.1000/182',
        title: title,
        isOrigin: true,
        year: 2026,
        citationCount: 150,
        x: 1000,
        y: 1000,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveEnv = TestHiveEnvironment();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await hiveEnv.start();
  });

  tearDownAll(() async {
    await hiveEnv.stop();
  });

  tearDown(() async {
    await hiveEnv.reset();
  });

  Widget buildWidgetTree({
    required Widget child,
    GraphCubit? graphCubit,
    LibraryCubit? libraryCubit,
    NotificationCubit? notificationCubit,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<SearchCubit>(create: (_) => SearchCubit()),
        BlocProvider<LibraryCubit>.value(
          value: libraryCubit ?? LibraryCubit(listenToAuth: false),
        ),
        BlocProvider<NotificationCubit>.value(
          value: notificationCubit ?? NotificationCubit(),
        ),
        BlocProvider<GraphCubit>.value(
          value: graphCubit ?? GraphCubit(),
        ),
      ],
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: child,
          builder: (context, materialChild) {
            return NotificationToastOverlay(
              navigatorKey: navigatorKey,
              child: materialChild ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }

  group('UI/UX Improvements Verification', () {
    testWidgets('RecentGraphsView displays recent graphs, search filtering, and library actions', (
      tester,
    ) async {
      final snapshot1 = _mockSnapshot(
        id: 'graph-1',
        title: 'Quantum Computing in 2026',
      );
      final snapshot2 = _mockSnapshot(
        id: 'graph-2',
        title: 'Neural Radiance Fields Review',
      );
      final libraryCubit = LibraryCubit.seeded(
        recentGraphs: [snapshot1, snapshot2],
      );

      await tester.pumpWidget(
        buildWidgetTree(
          child: const RecentGraphsView(),
          libraryCubit: libraryCubit,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify both graphs appear
      expect(find.text('Recent Graphs'), findsOneWidget);
      expect(find.text('Quantum Computing in 2026'), findsOneWidget);
      expect(find.text('Neural Radiance Fields Review'), findsOneWidget);

      // Search filter
      await tester.enterText(find.byType(TextField), 'Quantum');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Quantum Computing in 2026'), findsOneWidget);
      expect(find.text('Neural Radiance Fields Review'), findsNothing);

      await libraryCubit.close();
    });

    testWidgets(
      'Opening cached snapshot provides scoped cubit and does not cancel root background job',
      (tester) async {
        final rootGraphCubit = GraphCubit();
        final libraryCubit = LibraryCubit.seeded();

        // Put root graph cubit into an active background polling state
        rootGraphCubit.emit(
          const GraphPolling(
            graphId: 'in-flight-graph',
            originId: '10.1000/in-flight',
            status: GraphJobStatus.queued,
            progress: 0.45,
            currentStage: GraphJobStatus.queued,
          ),
        );

        expect(rootGraphCubit.hasActiveJob, isTrue);

        final snapshot = _mockSnapshot(
          id: 'cached-graph-123',
          title: 'Cached Paper Old',
        );

        await tester.pumpWidget(
          buildWidgetTree(
            graphCubit: rootGraphCubit,
            libraryCubit: libraryCubit,
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ConnectedGraphView(initialSnapshot: snapshot),
                    ),
                  );
                },
                child: const Text('Open Cached'),
              ),
            ),
          ),
        );
        await tester.pump();

        // Tap to open the cached graph snapshot
        await tester.tap(find.text('Open Cached'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Verify cached graph screen is displayed
        expect(find.text('Cached Paper Old'), findsWidgets);

        // CRITICAL GUARANTEE: Root GraphCubit MUST STILL be in active GraphPolling state!
        expect(rootGraphCubit.state, isA<GraphPolling>());
        expect(
          (rootGraphCubit.state as GraphPolling).graphId,
          'in-flight-graph',
        );
        expect(rootGraphCubit.hasActiveJob, isTrue);

        await rootGraphCubit.close();
        await libraryCubit.close();
      },
    );

    testWidgets(
      'NotificationToastOverlay displays minimal iOS style, Open CTA, and navigates on tap',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final notificationCubit = NotificationCubit();
        final snapshot = _mockSnapshot(
          id: 'ready-graph-777',
          title: 'Deep Residual Learning for Image Recognition',
        );
        final libraryCubit = LibraryCubit.seeded(
          cachedGraphs: [snapshot],
          recentGraphs: [snapshot],
        );

        await tester.pumpWidget(
          buildWidgetTree(
            child: const Scaffold(body: Text('Home Screen')),
            notificationCubit: notificationCubit,
            libraryCubit: libraryCubit,
            navigatorKey: navKey,
          ),
        );
        await tester.pump();

        // Dispatch graph ready notification with paper title
        notificationCubit.notifyGraphReady(
          'ready-graph-777',
          19,
          paperTitle: 'Deep Residual Learning for Image Recognition',
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify notification appears with paper title, kicker, and Open action
        expect(find.text('LITERATURE GRAPH READY'), findsOneWidget);
        expect(
          find.textContaining('Deep Residual Learning for Image Recognition'),
          findsWidgets,
        );
        expect(find.text('Open'), findsOneWidget);

        // Tap Open button
        await tester.tap(find.text('Open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify that ConnectedGraphView was opened via Navigator
        expect(find.byType(ConnectedGraphView), findsOneWidget);
        expect(
          find.textContaining('Deep Residual Learning for Image Recognition'),
          findsWidgets,
        );

        notificationCubit.dismissToast();
        await tester.pump(const Duration(milliseconds: 400));

        await notificationCubit.close();
        await libraryCubit.close();
      },
    );
  });
}
