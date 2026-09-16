import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/views/graph_view/connected_graph_view.dart';
import 'package:paper_graph/views/graph_view/painters/graph_canvas_painter.dart';

void main() {
  group('Phase 1: Graph Enhancement & Anti-AI-Slop Tests', () {
    test(
      'GraphCanvasPainter shouldRepaint returns false when state is unchanged',
      () {
        const nodes = [
          GraphNode(
            id: '1',
            canonicalId: '1',
            title: 'Origin Paper',
            year: 2023,
            citationCount: 100,
            isOrigin: true,
          ),
          GraphNode(
            id: '2',
            canonicalId: '2',
            title: 'Connected Paper',
            year: 2024,
            citationCount: 50,
            isOrigin: false,
          ),
        ];

        final painter1 = GraphCanvasPainter(
          nodes: nodes,
          citationEdges: const [],
          similarityEdges: const [],
          selectedNodeId: '1',
          isDark: true,
        );

        final painter2 = GraphCanvasPainter(
          nodes: nodes,
          citationEdges: const [],
          similarityEdges: const [],
          selectedNodeId: '1',
          isDark: true,
        );

        expect(painter1.shouldRepaint(painter2), isFalse);

        final zoomedPainter = GraphCanvasPainter(
          nodes: nodes,
          citationEdges: const [],
          similarityEdges: const [],
          selectedNodeId: '1',
          isDark: true,
          zoomScale: 1.5,
        );
        expect(painter1.shouldRepaint(zoomedPainter), isTrue);
      },
    );

    testWidgets(
      'ConnectedGraphView includes dedicated zoom in and zoom out buttons and InteractiveViewer',
      (tester) async {
        final snapshot = GraphSnapshot(
          graphId: 'test-graph',
          origin: const GraphOrigin(
            id: 'o1',
            canonicalId: 'o1',
            title: 'Seed Paper',
            year: 2023,
          ),
          status: GraphJobStatus.completed,
          createdAt: DateTime.now(),
          nodes: const [
            GraphNode(
              id: 'o1',
              canonicalId: 'o1',
              title: 'Seed Paper',
              year: 2023,
              citationCount: 10,
              isOrigin: true,
            ),
          ],
          citationEdges: const [],
          similarityEdges: const [],
        );

        await tester.pumpWidget(
          MaterialApp(
            home: MultiBlocProvider(
              providers: [
                BlocProvider<LibraryCubit>(create: (_) => LibraryCubit.seeded()),
                BlocProvider<NotificationCubit>(
                  create: (_) => NotificationCubit(),
                ),
              ],
              child: ConnectedGraphView(initialSnapshot: snapshot),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify zoom controls exist
        expect(find.byIcon(Icons.add_rounded), findsOneWidget);
        expect(find.byIcon(Icons.remove_rounded), findsOneWidget);
        expect(find.byIcon(Icons.center_focus_strong_rounded), findsOneWidget);

        // Verify InteractiveViewer exists with proper bounds
        final viewerFinder = find.byType(InteractiveViewer);
        expect(viewerFinder, findsOneWidget);
        final viewer = tester.widget<InteractiveViewer>(viewerFinder);
        expect(viewer.minScale, 0.20);
        expect(viewer.maxScale, 4.0);
      },
    );

    test(
      'HiveService multi-key indexing allows 0-second offline graph retrieval by DOI, CanonicalId, URL, or Title',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'hive_graph_offline_test_',
        );
        Hive.init(tempDir.path);
        await Hive.openBox(HiveService.cachedGraphsBoxName);

        final snapshot = GraphSnapshot(
          graphId: 'graph-job-999',
          origin: const GraphOrigin(
            id: 'doi:10.1038/nature12373',
            canonicalId: 'doi:10.1038/nature12373',
            doi: '10.1038/nature12373',
            title: 'Quantum Teleportation Across 143 km',
            year: 2012,
          ),
          status: GraphJobStatus.completed,
          createdAt: DateTime.now(),
          nodes: const [
            GraphNode(
              id: 'doi:10.1038/nature12373',
              canonicalId: 'doi:10.1038/nature12373',
              title: 'Quantum Teleportation Across 143 km',
              year: 2012,
              citationCount: 450,
              isOrigin: true,
            ),
          ],
          citationEdges: const [],
          similarityEdges: const [],
        );

        // Save graph
        await HiveService.saveCachedGraph(snapshot);
        await HiveService.saveCachedGraph(
          GraphSnapshot(
            graphId: 'graph-job-older',
            origin: const GraphOrigin(
              id: 'older-origin',
              canonicalId: 'older-origin',
              title: 'Older Cached Graph',
            ),
            status: GraphJobStatus.completed,
            createdAt: snapshot.createdAt.subtract(const Duration(days: 1)),
          ),
        );

        // Recent Graphs must be ordered by creation time, not Hive insertion.
        final recentGraphs = HiveService.getCachedGraphs();
        expect(recentGraphs.first.graphId, equals('graph-job-999'));

        // 1. Retrieve by exact graphId
        final byGraphId = HiveService.getCachedGraph('graph-job-999');
        expect(byGraphId, isNotNull);
        expect(byGraphId!.graphId, equals('graph-job-999'));

        // 2. Retrieve by raw DOI
        final byDoi = HiveService.getCachedGraph('10.1038/nature12373');
        expect(byDoi, isNotNull);
        expect(
          byDoi!.origin.title,
          equals('Quantum Teleportation Across 143 km'),
        );

        // 3. Retrieve by prefixed DOI 'doi:10.1038/nature12373'
        final byPrefixedDoi = HiveService.getCachedGraph(
          'doi:10.1038/nature12373',
        );
        expect(byPrefixedDoi, isNotNull);

        // 4. Retrieve by full URL 'https://doi.org/10.1038/nature12373'
        final byUrl = HiveService.getCachedGraph(
          'https://doi.org/10.1038/nature12373',
        );
        expect(byUrl, isNotNull);

        // 5. Retrieve by Title
        final byTitle = HiveService.getCachedGraph(
          'Quantum Teleportation Across 143 km',
        );
        expect(byTitle, isNotNull);

        await Hive.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      },
    );
  });
}
