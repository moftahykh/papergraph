import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/library/library_state.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/models/metric_result.dart';
import 'package:paper_graph/models/paper_model.dart';
import 'package:paper_graph/providers/favorites_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('multi_account_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.favoritesBoxName);
    await Hive.openBox(HiveService.settingsBoxName);
    await Hive.openBox(HiveService.canonicalPapersBoxName);
    await Hive.openBox(HiveService.cachedGraphsBoxName);
    await Hive.openBox(HiveService.paperNotesBoxName);
    HiveService.setActiveUserScope('anonymous');
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Multi-Account Data Isolation Tests', () {
    test(
      'Account A data is strictly invisible to Account B and Guest sessions',
      () async {
        // 1. Simulate Account A logged in
        await HiveService.saveUser({
          'id': 'user_account_A',
          'name': 'Researcher A',
          'email': 'userA@university.edu',
        });

        final favProvider = FavoritesProvider();
        final libraryCubit = LibraryCubit();

        final paperA = PaperModel(
          id: 'paper-account-A',
          title: 'Deep Learning with Account A',
          authors: ['Author A'],
          abstractText: 'Research paper for account A.',
          category: 'Artificial Intelligence',
          year: 2024,
          citationsCount: 120,
          influentialCitations: 10,
          connectedPaperIds: const [],
          pdfUrl: '',
          journal: 'Nature',
          doi: '10.1038/s41586-024-0001',
          keyTakeaways: const [],
          isFavorite: true,
        );

        await favProvider.toggleFavorite(paperA);
        await libraryCubit.saveNotes(
          'paper-account-A',
          'Exclusive notes for account A',
        );

        expect(favProvider.count, equals(1));
        expect(favProvider.isFavorite('paper-account-A'), isTrue);
        expect(
          libraryCubit.getNotes('paper-account-A'),
          equals('Exclusive notes for account A'),
        );

        // 2. Account A logs out
        await HiveService.clearUser();
        favProvider.loadFavorites();
        libraryCubit.loadLibrary();

        // Guest session should NOT see Account A's papers or notes
        expect(favProvider.count, equals(0));
        expect(favProvider.isFavorite('paper-account-A'), isFalse);
        final guestState = libraryCubit.state as LibraryLoaded;
        expect(guestState.savedPapers.isEmpty, isTrue);
        expect(guestState.paperNotes.isEmpty, isTrue);

        // 3. Account B logs in
        await HiveService.saveUser({
          'id': 'user_account_B',
          'name': 'Researcher B',
          'email': 'userB@mit.edu',
        });
        favProvider.loadFavorites();
        libraryCubit.loadLibrary();

        // Account B should NOT see Account A's papers
        expect(favProvider.count, equals(0));
        expect(favProvider.isFavorite('paper-account-A'), isFalse);
        final bState = libraryCubit.state as LibraryLoaded;
        expect(bState.savedPapers.isEmpty, isTrue);
        expect(bState.paperNotes.isEmpty, isTrue);

        // Account B saves their own paper
        final paperB = PaperModel(
          id: 'paper-account-B',
          title: 'Quantum Computing with Account B',
          authors: ['Author B'],
          abstractText: 'Research paper for account B.',
          category: 'Quantum Physics',
          year: 2025,
          citationsCount: 45,
          influentialCitations: 5,
          connectedPaperIds: const [],
          pdfUrl: '',
          journal: 'Science',
          doi: '10.1126/science.2025.0002',
          keyTakeaways: const [],
          isFavorite: true,
        );
        await favProvider.toggleFavorite(paperB);

        expect(favProvider.count, equals(1));
        expect(favProvider.isFavorite('paper-account-B'), isTrue);
        expect(favProvider.isFavorite('paper-account-A'), isFalse);

        // 4. Switch back to Account A
        await HiveService.saveUser({
          'id': 'user_account_A',
          'name': 'Researcher A',
          'email': 'userA@university.edu',
        });
        favProvider.loadFavorites();
        libraryCubit.loadLibrary();

        // Account A should see paper A and notes A, but NOT paper B
        expect(favProvider.count, equals(1));
        expect(favProvider.isFavorite('paper-account-A'), isTrue);
        expect(favProvider.isFavorite('paper-account-B'), isFalse);
        expect(
          libraryCubit.getNotes('paper-account-A'),
          equals('Exclusive notes for account A'),
        );

        favProvider.dispose();
        await libraryCubit.close();
      },
    );

    test(
      'Legacy migration securely assigns un-prefixed keys to first authenticated user',
      () async {
        // Simulate legacy un-prefixed data from old version
        final legacyMap = {
          'id': 'legacy-paper-99',
          'title': 'Legacy Unscoped Paper',
          'authors': ['Old Author'],
          'abstractText': 'Legacy content',
          'category': 'Computer Science',
          'year': 2020,
          'citationsCount': 10,
          'influentialCitations': 0,
          'connectedPaperIds': <String>[],
          'pdfUrl': '',
          'journal': '',
          'doi': '',
          'keyTakeaways': <String>[],
          'isFavorite': true,
        };

        await HiveService.favoritesBox.put('legacy-paper-99', legacyMap);
        await HiveService.paperNotesBox.put(
          'legacy-paper-99',
          'Old personal note',
        );

        // Guest / anonymous should not access it
        expect(HiveService.getFavoritePapers().isEmpty, isTrue);

        // Account A logs in and runs migration
        await HiveService.saveUser({
          'id': 'user_migrated_A',
          'name': 'Migrated User',
          'email': 'migrated@univ.edu',
        });
        await HiveService.migrateLegacyDataForUser('user_migrated_A');

        // Account A now owns the paper
        expect(HiveService.isPaperFavorite('legacy-paper-99'), isTrue);
        expect(HiveService.getFavoritePapers().length, equals(1));
        expect(
          HiveService.getPersonalNotes('legacy-paper-99'),
          equals('Old personal note'),
        );

        // Account B logs in
        await HiveService.saveUser({
          'id': 'user_unrelated_B',
          'name': 'Unrelated User',
          'email': 'other@univ.edu',
        });

        // Account B does NOT see Account A's migrated paper
        expect(HiveService.isPaperFavorite('legacy-paper-99'), isFalse);
        expect(HiveService.getFavoritePapers().isEmpty, isTrue);
        expect(HiveService.getPersonalNotes('legacy-paper-99'), isEmpty);
      },
    );

    test(
      'Clearing cache removes only the active user graphs and aliases',
      () async {
        final box = Hive.box(HiveService.cachedGraphsBoxName);

        await HiveService.saveUser({
          'id': 'cache_user_A',
          'name': 'Cache User A',
          'email': 'a@example.com',
        });
        await box.put('cache_user_A::graph-a', {
          '_owner_id': 'cache_user_A',
          'graph_id': 'graph-a',
        });
        await box.put('alias:cache_user_A:id:paper-a', 'cache_user_A::graph-a');

        await HiveService.saveUser({
          'id': 'cache_user_B',
          'name': 'Cache User B',
          'email': 'b@example.com',
        });
        await box.put('cache_user_B::graph-b', {
          '_owner_id': 'cache_user_B',
          'graph_id': 'graph-b',
        });
        await box.put('alias:cache_user_B:id:paper-b', 'cache_user_B::graph-b');

        final removed = await HiveService.clearCachedGraphsForActiveUser();

        expect(removed, 1);
        expect(box.containsKey('cache_user_B::graph-b'), isFalse);
        expect(box.containsKey('alias:cache_user_B:id:paper-b'), isFalse);
        expect(box.containsKey('cache_user_A::graph-a'), isTrue);
        expect(box.containsKey('alias:cache_user_A:id:paper-a'), isTrue);
      },
    );

    test(
      'Pending graph jobs are account scoped and clearable after logout',
      () async {
        await HiveService.saveUser({
          'id': 'pending_user_A',
          'name': 'Pending User A',
          'email': 'pending-a@example.com',
        });
        await HiveService.savePendingGraphJob(
          graphId: 'pending-graph-a',
          originId: '10.1000/pending-a',
          startedAt: DateTime(2026, 1, 1, 12),
          progress: 0.35,
          currentStage: 'enriching_metadata',
        );

        expect(
          HiveService.getPendingGraphJob()?['graph_id'],
          'pending-graph-a',
        );

        await HiveService.saveUser({
          'id': 'pending_user_B',
          'name': 'Pending User B',
          'email': 'pending-b@example.com',
        });
        expect(HiveService.getPendingGraphJob(), isNull);

        // GraphCubit may receive the logout event after saved_user was cleared,
        // so deletion searches scoped pending keys by graph ID.
        await HiveService.clearPendingGraphJob('pending-graph-a');

        await HiveService.saveUser({
          'id': 'pending_user_A',
          'name': 'Pending User A',
          'email': 'pending-a@example.com',
        });
        expect(HiveService.getPendingGraphJob(), isNull);
      },
    );

    test(
      'Cached graph survives Hive close and reopen for the same account',
      () async {
        await HiveService.saveUser({
          'id': 'persistent_user',
          'name': 'Persistent User',
          'email': 'persistent@example.com',
        });
        await HiveService.saveCachedGraph(
          GraphSnapshot(
            graphId: 'persistent-graph',
            origin: const GraphOrigin(
              id: 'persistent-origin',
              canonicalId: 'persistent-origin',
              title: 'Persistent Offline Graph',
            ),
            status: GraphJobStatus.completed,
            createdAt: DateTime(2026, 1, 1, 12),
            nodes: const [
              GraphNode(
                id: 'persistent-node',
                canonicalId: 'persistent-node',
                title: 'Persistent Scored Node',
                isOrigin: true,
                scores: {
                  'wbc': MetricResult(
                    value: 0.82,
                    availability: MetricAvailability.available,
                  ),
                },
              ),
            ],
          ),
        );
        expect(HiveService.getCachedGraphs().length, 1);

        await Hive.close();
        Hive.init(tempDir.path);
        await Hive.openBox(HiveService.favoritesBoxName);
        await Hive.openBox(HiveService.settingsBoxName);
        await Hive.openBox(HiveService.canonicalPapersBoxName);
        await Hive.openBox(HiveService.cachedGraphsBoxName);
        await Hive.openBox(HiveService.paperNotesBoxName);

        final restoredUser = HiveService.getSavedUser();
        expect(restoredUser?['id'], 'persistent_user');
        await HiveService.saveUser(Map<String, dynamic>.from(restoredUser!));

        final restoredGraphs = HiveService.getCachedGraphs();
        expect(restoredGraphs.length, 1);
        expect(restoredGraphs.single.graphId, 'persistent-graph');
        expect(restoredGraphs.single.nodes.length, 1);
        expect(restoredGraphs.single.nodes.single.scores?['wbc']?.value, 0.82);
      },
    );

    test('Automatic graphs stay in Recent until the user saves them', () async {
      final graph = GraphSnapshot(
        graphId: 'recent-only-graph',
        origin: const GraphOrigin(
          id: 'recent-origin',
          canonicalId: 'recent-origin',
          title: 'Recent Graph',
        ),
        status: GraphJobStatus.completed,
        createdAt: DateTime(2026, 1, 4),
      );

      await HiveService.saveCachedGraph(graph, markAsSaved: false);
      expect(HiveService.getCachedGraphs(), hasLength(1));
      expect(HiveService.getCachedGraphs(savedOnly: true), isEmpty);

      await HiveService.saveCachedGraph(graph, markAsSaved: true);
      expect(
        HiveService.getCachedGraphs(savedOnly: true).single.graphId,
        'recent-only-graph',
      );
    });

    test(
      'Automatic history is bounded without deleting saved graphs',
      () async {
        final pinned = GraphSnapshot(
          graphId: 'pinned-graph',
          origin: const GraphOrigin(
            id: 'pinned-origin',
            canonicalId: 'pinned-origin',
            title: 'Pinned Graph',
          ),
          status: GraphJobStatus.completed,
          createdAt: DateTime(2020, 1, 1),
        );
        await HiveService.saveCachedGraph(pinned, markAsSaved: true);

        for (
          var index = 0;
          index < HiveService.maxRecentGraphsPerUser + 2;
          index++
        ) {
          await HiveService.saveCachedGraph(
            GraphSnapshot(
              graphId: 'automatic-$index',
              origin: GraphOrigin(
                id: 'automatic-origin-$index',
                canonicalId: 'automatic-origin-$index',
                title: 'Automatic Graph $index',
              ),
              status: GraphJobStatus.completed,
              createdAt: DateTime(2026, 2, 1).add(Duration(minutes: index)),
            ),
            markAsSaved: false,
          );
        }

        final allGraphs = HiveService.getCachedGraphs();
        final savedGraphs = HiveService.getCachedGraphs(savedOnly: true);
        expect(allGraphs.length, HiveService.maxRecentGraphsPerUser + 1);
        expect(
          savedGraphs.map((graph) => graph.graphId),
          contains('pinned-graph'),
        );
        expect(savedGraphs, hasLength(1));
        expect(
          allGraphs.map((graph) => graph.graphId),
          isNot(contains('automatic-0')),
        );
      },
    );

    test(
      'Library does not claim a graph was saved when storage is unavailable',
      () async {
        final libraryCubit = LibraryCubit(logFailures: false);
        expect(libraryCubit.state, isA<LibraryLoaded>());

        await Hive.box(HiveService.cachedGraphsBoxName).close();
        final saved = await libraryCubit.cacheGraph(
          GraphSnapshot(
            graphId: 'must-not-appear-in-memory',
            origin: const GraphOrigin(
              id: 'storage-failure-origin',
              canonicalId: 'storage-failure-origin',
              title: 'Storage Failure Test',
            ),
            status: GraphJobStatus.completed,
            createdAt: DateTime(2026, 1, 3),
          ),
        );

        expect(saved, isFalse);
        final state = libraryCubit.state as LibraryLoaded;
        expect(state.cachedGraphs, isEmpty);

        await Hive.openBox(HiveService.cachedGraphsBoxName);
        await libraryCubit.close();
      },
    );

    test(
      'Library keeps known-good graphs when a refresh cannot read storage',
      () async {
        final libraryCubit = LibraryCubit(logFailures: false);
        final graph = GraphSnapshot(
          graphId: 'known-good-graph',
          origin: const GraphOrigin(
            id: 'known-good-origin',
            canonicalId: 'known-good-origin',
            title: 'Known Good Graph',
          ),
          status: GraphJobStatus.completed,
          createdAt: DateTime(2026, 1, 3),
        );
        expect(await libraryCubit.cacheGraph(graph), isTrue);
        expect(
          (libraryCubit.state as LibraryLoaded).cachedGraphs.single.graphId,
          'known-good-graph',
        );

        await Hive.box(HiveService.cachedGraphsBoxName).close();
        libraryCubit.loadLibrary();

        final state = libraryCubit.state as LibraryLoaded;
        expect(state.cachedGraphs.single.graphId, 'known-good-graph');

        await Hive.openBox(HiveService.cachedGraphsBoxName);
        await libraryCubit.close();
      },
    );

    test('Library keeps notes unchanged when their write fails', () async {
      final libraryCubit = LibraryCubit(logFailures: false);
      await Hive.box(HiveService.paperNotesBoxName).close();

      final saved = await libraryCubit.saveNotes(
        'paper-with-failed-note',
        'This must not appear as saved.',
      );

      expect(saved, isFalse);
      final state = libraryCubit.state as LibraryLoaded;
      expect(state.getNotes('paper-with-failed-note'), isEmpty);

      await Hive.openBox(HiveService.paperNotesBoxName);
      await libraryCubit.close();
    });

    test('Anonymous graph is adopted once when a user signs in', () async {
      HiveService.setActiveUserScope('anonymous');
      await HiveService.saveCachedGraph(
        GraphSnapshot(
          graphId: 'guest-graph',
          origin: const GraphOrigin(
            id: 'guest-origin',
            canonicalId: 'guest-origin',
            title: 'Guest Research Graph',
          ),
          status: GraphJobStatus.completed,
          createdAt: DateTime(2026, 1, 2, 12),
        ),
      );
      expect(HiveService.getCachedGraphs().length, 1);

      await HiveService.saveUser({
        'id': 'adopting_user',
        'name': 'Adopting User',
        'email': 'adopting@example.com',
      });
      await HiveService.migrateLegacyDataForUser('adopting_user');

      final adoptedGraphs = HiveService.getCachedGraphs();
      expect(adoptedGraphs.length, 1);
      expect(adoptedGraphs.single.graphId, 'guest-graph');

      HiveService.setActiveUserScope('anonymous');
      expect(HiveService.getCachedGraphs(), isEmpty);
    });
  });
}
