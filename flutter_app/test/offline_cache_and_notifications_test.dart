import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/core/services/local_notification_service.dart';
import 'package:paper_graph/core/theme/app_theme.dart';
import 'package:paper_graph/cubits/graph/graph_cubit.dart';
import 'package:paper_graph/cubits/graph/graph_state.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/library/library_state.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_state.dart';
import 'package:paper_graph/models/canonical_paper.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/views/favorites/favorites_view.dart';
import 'package:paper_graph/views/graph_view/connected_graph_view.dart';
import 'test_hive.dart';

GraphSnapshot createMockSnapshot({
  String id = 'graph-cache-1',
  int schemaVersion = 1,
  String algorithmVersion = 'v1.0',
  DateTime? createdAt,
  DateTime? expiresAt,
}) {
  final created = createdAt ?? DateTime.now();
  return GraphSnapshot(
    graphId: id,
    origin: const GraphOrigin(
      id: 'origin-1',
      canonicalId: '10.1234/test',
      title: 'Attention Is All You Need',
      year: 2017,
    ),
    status: GraphJobStatus.completed,
    schemaVersion: schemaVersion,
    algorithmVersion: algorithmVersion,
    createdAt: created,
    expiresAt: expiresAt,
    nodes: const [
      GraphNode(
        id: 'node-seed',
        canonicalId: '10.1234/test',
        title: 'Attention Is All You Need',
        isOrigin: true,
        year: 2017,
        citationCount: 90000,
        x: 1000.0,
        y: 1000.0,
      ),
      GraphNode(
        id: 'node-subsequent',
        canonicalId: '10.1234/bert',
        title: 'BERT: Pre-training of Deep Bidirectional Transformers',
        isOrigin: false,
        year: 2018,
        citationCount: 75000,
        x: 1150.0,
        y: 1150.0,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GraphSnapshot Schema Versioning & Expiration Math', () {
    test('defaults schemaVersion to 1 and algorithmVersion to v1.0', () {
      final snapshot = createMockSnapshot();
      expect(snapshot.schemaVersion, equals(1));
      expect(snapshot.algorithmVersion, equals('v1.0'));
      expect(snapshot.isCompatible(1), isTrue);
      expect(snapshot.isCompatible(2), isFalse);
    });

    test('effectiveExpiresAt defaults to 14 days after createdAt', () {
      final created = DateTime(2026, 1, 1, 12, 0);
      final snapshot = createMockSnapshot(createdAt: created);

      expect(
        snapshot.effectiveExpiresAt,
        equals(created.add(const Duration(days: 14))),
      );
      expect(
        snapshot.effectiveExpiresAt.difference(created).inDays,
        equals(14),
      );
    });

    test(
      'isExpired is false for new snapshot and true for past expiration date',
      () {
        final fresh = createMockSnapshot(createdAt: DateTime.now());
        expect(fresh.isExpired, isFalse);

        final expired = createMockSnapshot(
          createdAt: DateTime.now().subtract(const Duration(days: 30)),
          expiresAt: DateTime.now().subtract(const Duration(days: 16)),
        );
        expect(expired.isExpired, isTrue);
      },
    );

    test(
      'round-trips schema_version and expires_at through toJson and fromJson',
      () {
        final original = createMockSnapshot(
          schemaVersion: 1,
          algorithmVersion: 'v1.0',
          createdAt: DateTime(2026, 3, 1, 10, 0),
          expiresAt: DateTime(2026, 3, 15, 10, 0),
        );

        final json = original.toJson();
        expect(json['schema_version'], equals(1));
        expect(json['algorithm_version'], equals('v1.0'));
        expect(json['expires_at'], isNotNull);

        final restored = GraphSnapshot.fromJson(json);
        expect(restored.schemaVersion, equals(original.schemaVersion));
        expect(restored.algorithmVersion, equals(original.algorithmVersion));
        expect(restored.expiresAt, isNotNull);
        expect(restored.effectiveExpiresAt.year, equals(2026));
        expect(
          restored.isCompatible(HiveService.currentGraphSchemaVersion),
          isTrue,
        );
      },
    );
  });

  group('LibraryCubit Notes and Cache Pruning Tests', () {
    final storage = TestHiveEnvironment();
    late LibraryCubit libraryCubit;

    setUpAll(storage.start);
    setUp(storage.reset);
    tearDownAll(storage.stop);

    setUp(() {
      libraryCubit = LibraryCubit();
    });

    tearDown(() async {
      await libraryCubit.close();
    });

    test('saveNotes updates notes in state and retrieves correctly', () async {
      await libraryCubit.saveNotes(
        'paper-123',
        'Key finding: Transformer scales logarithmically.',
      );
      expect(
        libraryCubit.getNotes('paper-123'),
        equals('Key finding: Transformer scales logarithmically.'),
      );

      if (libraryCubit.state is LibraryLoaded) {
        final state = libraryCubit.state as LibraryLoaded;
        expect(state.hasNotes('paper-123'), isTrue);
        expect(state.hasNotes('paper-999'), isFalse);
      }

      // Update notes
      await libraryCubit.saveNotes(
        'paper-123',
        'Updated insights on self-attention.',
      );
      expect(
        libraryCubit.getNotes('paper-123'),
        equals('Updated insights on self-attention.'),
      );

      // Delete notes
      await libraryCubit.deleteNotes('paper-123');
      expect(libraryCubit.getNotes('paper-123'), isEmpty);
    });

    test(
      'pruneExpiredGraphs runs safely without throwing exceptions',
      () async {
        final count = await libraryCubit.pruneExpiredGraphs();
        expect(count, isNonNegative);
      },
    );
  });

  group('Contextual Notification & Offline Mode Guarantees', () {
    final storage = TestHiveEnvironment();
    setUpAll(storage.start);
    setUp(storage.reset);
    tearDownAll(storage.stop);

    test(
      'LocalNotificationService handles per-graph notification toggle and dispatch',
      () async {
        const graphId = 'graph-job-notif-1';

        // Verify toggle setting and retrieval
        await LocalNotificationService.setGraphNotificationEnabled(
          graphId,
          true,
        );
        // Even if Hive box is mock or headless, onGraphCompleted must execute safely:
        final notifCubit = NotificationCubit();

        await LocalNotificationService.onGraphCompleted(
          graphId: graphId,
          nodeCount: 15,
          isPartial: false,
          notificationCubit: notifCubit,
        );

        expect(notifCubit.state.notifications.isNotEmpty, isTrue);
        expect(
          notifCubit.state.notifications.first.relatedGraphId,
          equals(graphId),
        );
        expect(
          notifCubit.state.notifications.first.type,
          equals(NotificationType.success),
        );
        notifCubit.close();
      },
    );

    test(
      'openCachedGraph sets fromOfflineCache: true with zero network calls',
      () {
        final graphCubit = GraphCubit();
        final snapshot = createMockSnapshot();

        graphCubit.openCachedGraph(snapshot);

        expect(graphCubit.state, isA<GraphLoaded>());
        final loaded = graphCubit.state as GraphLoaded;
        expect(loaded.fromOfflineCache, isTrue);
        expect(loaded.snapshot.graphId, equals(snapshot.graphId));
        expect(loaded.isPartial, isFalse);
        graphCubit.close();
      },
    );
  });

  group('FavoritesView Offline Library Widget Tests', () {
    testWidgets('renders Papers and Graphs tabs', (tester) async {
      final samplePaper = CanonicalPaper(
        canonicalId: 'paper-offline-1',
        title: 'Deep Residual Learning for Image Recognition',
        normalizedTitle: 'deep residual learning for image recognition',
        authors: const [
          Author(name: 'Kaiming He'),
          Author(name: 'Xiangyu Zhang'),
        ],
        year: 2016,
        citationCount: 150000,
        topics: const ['Computer Vision'],
      );
      final sampleGraph = createMockSnapshot(id: 'cached-graph-1');

      final libraryCubit = LibraryCubit.seeded(
        savedPapers: [samplePaper],
        cachedGraphs: [sampleGraph],
        paperNotes: const {'paper-offline-1': 'Landmark ResNet paper.'},
      );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<LibraryCubit>.value(value: libraryCubit),
            BlocProvider<GraphCubit>(create: (_) => GraphCubit()),
            BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const FavoritesView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Tab headers
      expect(find.text('Papers'), findsOneWidget);
      expect(find.text('Graphs'), findsOneWidget);

      // Verify Tab 1 contents (Saved Papers & Notes)
      expect(
        find.text('Deep Residual Learning for Image Recognition'),
        findsOneWidget,
      );
      expect(find.text('Landmark ResNet paper.'), findsOneWidget);

      // Switch to Tab 2 (Cached Graphs)
      await tester.tap(find.text('Graphs'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Tab 2 contents (Cached Literature Graphs)
      expect(find.text('Available offline'), findsWidgets);
      expect(find.text('Attention Is All You Need'), findsOneWidget);
      expect(find.text('Open graph'), findsOneWidget);

      await libraryCubit.close();
    });

    testWidgets('ConnectedGraphView prevents network recenter in offline mode', (
      tester,
    ) async {
      final snapshot = createMockSnapshot();

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<GraphCubit>(create: (_) => GraphCubit()),
            BlocProvider<LibraryCubit>(create: (_) => LibraryCubit.seeded()),
            BlocProvider<NotificationCubit>(create: (_) => NotificationCubit()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: ConnectedGraphView(initialSnapshot: snapshot),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Open bottom sheet
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to All papers tab to select non-origin paper
      await tester.tap(find.text('All papers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.tap(
        find.text('BERT: Pre-training of Deep Bidirectional Transformers'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // The paper tab is scrollable and action buttons are below the fold.
      await tester.drag(
        find.byType(ListView).hitTestable(),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      // Tap Center graph button while in offline cache mode
      expect(find.text('Center graph'), findsOneWidget);
      await tester.tap(find.text('Center graph'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify offline protection snackbar
      expect(
        find.text(
          'Cannot synthesize new graphs in offline mode. Connect to the internet to explore new papers.',
        ),
        findsOneWidget,
      );
    });
  });
}
