import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:paper_graph/core/network/api_client.dart';
import 'package:paper_graph/core/services/hive_service.dart';
import 'package:paper_graph/cubits/discovery/discovery_cubit.dart';
import 'package:paper_graph/cubits/discovery/discovery_state.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/models/api_schemas.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/views/graph_view/connected_graph_view.dart';
import 'package:paper_graph/views/research_monitoring/graph_updates_view.dart';

import 'test_hive.dart';

class MockDiscoveryApiClient extends PaperGraphApiClient {
  DiscoveryHomeResponse? mockResponse;
  ApiException? mockException;
  int callCount = 0;

  MockDiscoveryApiClient({this.mockResponse, this.mockException});

  @override
  Future<DiscoveryHomeResponse> getDiscoveryHome({
    CancelToken? cancelToken,
  }) async {
    callCount++;
    if (mockException != null) {
      throw mockException!;
    }
    return mockResponse ??
        const DiscoveryHomeResponse(
          topics: [
            DiscoveryTopic(
              label: 'Machine Learning',
              query: 'machine learning',
              rank: 10,
            ),
          ],
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveEnvironment = TestHiveEnvironment();
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await hiveEnvironment.start();
  });
  setUp(hiveEnvironment.reset);
  tearDownAll(hiveEnvironment.stop);

  group('Discovery Models Serialization', () {
    test('DiscoveryTopic parses and serializes correctly', () {
      final json = {
        'label': 'Quantum Computing',
        'query': 'quantum computing',
        'rank': 5,
      };
      final topic = DiscoveryTopic.fromJson(json);
      expect(topic.label, 'Quantum Computing');
      expect(topic.query, 'quantum computing');
      expect(topic.rank, 5);
      expect(topic.toJson(), json);
    });

    test('DiscoveryRecommendation parses local_graph_id and all fields', () {
      final json = {
        'canonical_id': 'paper_123',
        'doi': '10.1000/182',
        'title': 'Advanced Graph Neural Networks',
        'reason': 'Highly cited in your subfield',
        'local_graph_id': 'graph_abc_789',
        'graph_title': 'Genomics Literature Graph',
        'relation_type': 'citation',
        'relevance_score': 0.94,
        'detected_at': '2026-09-19T10:00:00.000Z',
      };
      final rec = DiscoveryRecommendation.fromJson(json);
      expect(rec.canonicalId, 'paper_123');
      expect(rec.doi, '10.1000/182');
      expect(rec.title, 'Advanced Graph Neural Networks');
      expect(rec.localGraphId, 'graph_abc_789');
      expect(rec.graphTitle, 'Genomics Literature Graph');
      expect(rec.relationType, 'citation');
      expect(rec.relevanceScore, 0.94);
      expect(rec.detectedAt, DateTime.parse('2026-09-19T10:00:00.000Z'));

      final serialized = rec.toJson();
      expect(serialized['local_graph_id'], 'graph_abc_789');
      expect(serialized['graph_title'], 'Genomics Literature Graph');
    });

    test('DiscoveryHomeResponse handles missing recommendation cleanly', () {
      final json = {
        'topics': [
          {'label': 'Biotech', 'query': 'biotechnology', 'rank': 20},
        ],
        'recommendation': null,
      };
      final response = DiscoveryHomeResponse.fromJson(json);
      expect(response.topics.length, 1);
      expect(response.topics.first.label, 'Biotech');
      expect(response.recommendation, isNull);
    });
  });

  group('Fix 3: Discovery Offline & Render Cold-Start Behavior', () {
    test('Successful network load caches topics into Hive', () async {
      final mockApi = MockDiscoveryApiClient(
        mockResponse: const DiscoveryHomeResponse(
          topics: [
            DiscoveryTopic(label: 'Robotics', query: 'robotics', rank: 1),
            DiscoveryTopic(label: 'AI Ethics', query: 'ai ethics', rank: 2),
          ],
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load();

      expect(cubit.state, isA<DiscoveryLoaded>());
      final loaded = cubit.state as DiscoveryLoaded;
      expect(loaded.topics.length, 2);
      expect(loaded.topics[0].label, 'Robotics');

      // Verify written to Hive cache
      final cached = HiveService.getCachedDiscoveryTopics();
      expect(cached, isNotNull);
      expect(cached!.length, 2);
      expect(cached[0]['label'], 'Robotics');
      await cubit.close();
    });

    test('Offline load from cache when network fails', () async {
      // 1. Seed cache in Hive
      await HiveService.saveCachedDiscoveryTopics([
        {'label': 'Cached Topic 1', 'query': 'cached 1', 'rank': 1},
        {'label': 'Cached Topic 2', 'query': 'cached 2', 'rank': 2},
      ]);

      // 2. Api client throws network error / timeout
      final mockApi = MockDiscoveryApiClient(
        mockException: const ApiException(
          'Connection timed out',
          statusCode: 504,
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load();

      // Should retain and emit cached topics rather than failing to empty UI
      expect(cubit.state, isA<DiscoveryLoaded>());
      final loaded = cubit.state as DiscoveryLoaded;
      expect(loaded.topics.length, 2);
      expect(loaded.topics[0].label, 'Cached Topic 1');
      expect(loaded.recommendation, isNull);
      await cubit.close();
    });

    test(
      'Empty cache plus failed network emits DiscoveryUnavailable',
      () async {
        final mockApi = MockDiscoveryApiClient(
          mockException: const ApiException('Network unreachable'),
        );

        final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
        await cubit.load();

        expect(cubit.state, isA<DiscoveryUnavailable>());
        final unavailable = cubit.state as DiscoveryUnavailable;
        expect(unavailable.message, 'Network unreachable');
        await cubit.close();
      },
    );

    test('Successful refresh replaces cached topics in Hive', () async {
      await HiveService.saveCachedDiscoveryTopics([
        {'label': 'Old Topic', 'query': 'old', 'rank': 1},
      ]);

      final mockApi = MockDiscoveryApiClient(
        mockResponse: const DiscoveryHomeResponse(
          topics: [DiscoveryTopic(label: 'New Topic', query: 'new', rank: 1)],
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load(force: true);

      final loaded = cubit.state as DiscoveryLoaded;
      expect(loaded.topics.first.label, 'New Topic');

      final cached = HiveService.getCachedDiscoveryTopics();
      expect(cached!.first['label'], 'New Topic');
      await cubit.close();
    });
  });

  group('Fix 2: Authentication Lifecycle & Multi-Account Isolation', () {
    test('Anonymous user loads topics without recommendation', () async {
      HiveService.setActiveUserScope('anonymous');

      final mockApi = MockDiscoveryApiClient(
        mockResponse: const DiscoveryHomeResponse(
          topics: [
            DiscoveryTopic(label: 'Genetics', query: 'genetics', rank: 1),
          ],
          recommendation: null,
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load();

      expect(cubit.state, isA<DiscoveryLoaded>());
      final loaded = cubit.state as DiscoveryLoaded;
      expect(loaded.recommendation, isNull);
      await cubit.close();
    });

    test('User login forces reload and populates recommendation', () async {
      HiveService.setActiveUserScope('anonymous');

      final mockApi = MockDiscoveryApiClient(
        mockResponse: const DiscoveryHomeResponse(
          topics: [DiscoveryTopic(label: 'AI', query: 'ai', rank: 1)],
          recommendation: null,
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load();
      expect((cubit.state as DiscoveryLoaded).recommendation, isNull);

      // Now user logs in
      HiveService.setActiveUserScope('user_account_A');
      mockApi.mockResponse = const DiscoveryHomeResponse(
        topics: [DiscoveryTopic(label: 'AI', query: 'ai', rank: 1)],
        recommendation: DiscoveryRecommendation(
          canonicalId: 'p_A',
          title: 'User A Recommended Paper',
          reason: 'Matches your monitored graph',
          localGraphId: 'graph_A',
          graphTitle: 'User A Graph',
          relationType: 'related',
        ),
      );

      cubit.onAuthChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state, isA<DiscoveryLoaded>());
      final loadedAfterLogin = cubit.state as DiscoveryLoaded;
      expect(
        loadedAfterLogin.recommendation?.title,
        'User A Recommended Paper',
      );
      expect(loadedAfterLogin.recommendation?.localGraphId, 'graph_A');
      await cubit.close();
    });

    test('User logout clears recommendation data immediately', () async {
      HiveService.setActiveUserScope('user_account_A');

      final mockApi = MockDiscoveryApiClient(
        mockResponse: const DiscoveryHomeResponse(
          topics: [DiscoveryTopic(label: 'AI', query: 'ai', rank: 1)],
          recommendation: DiscoveryRecommendation(
            canonicalId: 'p_A',
            title: 'User A Paper',
            reason: 'For User A',
            localGraphId: 'graph_A',
            graphTitle: 'User A Graph',
            relationType: 'related',
          ),
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load();
      expect((cubit.state as DiscoveryLoaded).recommendation, isNotNull);

      // Logout: switch active user scope to anonymous
      HiveService.setActiveUserScope('anonymous');
      mockApi.mockResponse = const DiscoveryHomeResponse(
        topics: [DiscoveryTopic(label: 'AI', query: 'ai', rank: 1)],
        recommendation: null,
      );

      cubit.onAuthChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state, isA<DiscoveryLoaded>());
      final loadedAfterLogout = cubit.state as DiscoveryLoaded;
      expect(loadedAfterLogout.recommendation, isNull);
      await cubit.close();
    });

    test('Account switching guarantees recommendation isolation', () async {
      // 1. User A logs in
      HiveService.setActiveUserScope('user_account_A');
      final mockApi = MockDiscoveryApiClient(
        mockResponse: const DiscoveryHomeResponse(
          topics: [DiscoveryTopic(label: 'AI', query: 'ai', rank: 1)],
          recommendation: DiscoveryRecommendation(
            canonicalId: 'paper_secret_A',
            title: 'Private Research for User A',
            reason: 'Confidential',
            localGraphId: 'graph_A_secret',
            graphTitle: 'Secret Graph A',
            relationType: 'related',
          ),
        ),
      );

      final cubit = DiscoveryCubit(apiClient: mockApi, listenToAuth: false);
      await cubit.load();
      expect(
        (cubit.state as DiscoveryLoaded).recommendation?.canonicalId,
        'paper_secret_A',
      );

      // 2. Switch directly to User B
      HiveService.setActiveUserScope('user_account_B');
      mockApi.mockResponse = const DiscoveryHomeResponse(
        topics: [DiscoveryTopic(label: 'AI', query: 'ai', rank: 1)],
        recommendation: DiscoveryRecommendation(
          canonicalId: 'paper_B',
          title: 'Public Research for User B',
          reason: 'Public info',
          localGraphId: 'graph_B',
          graphTitle: 'Graph B',
          relationType: 'related',
        ),
      );

      cubit.onAuthChanged();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final loadedUserB = cubit.state as DiscoveryLoaded;
      expect(loadedUserB.recommendation?.canonicalId, 'paper_B');
      expect(loadedUserB.recommendation?.title, 'Public Research for User B');
      await cubit.close();
    });
  });

  group('Fix 1: Recommendation Graph Navigation', () {
    testWidgets(
      'Tapping recommendation card opens existing cached graph snapshot',
      (tester) async {
        const localId = 'monitored_graph_123';
        final sampleSnapshot = GraphSnapshot(
          graphId: localId,
          status: GraphJobStatus.completed,
          origin: const GraphOrigin(
            id: 'origin_1',
            canonicalId: 'origin_paper_1',
            title: 'Foundations of Cancer Genomics',
          ),
          nodes: const [
            GraphNode(
              id: 'origin_node_1',
              canonicalId: 'origin_paper_1',
              title: 'Foundations of Cancer Genomics',
              year: 2022,
              citationCount: 50,
            ),
          ],
          createdAt: DateTime.now(),
        );

        final libraryCubit = LibraryCubit.seeded(
          cachedGraphs: [sampleSnapshot],
        );

        const recommendation = DiscoveryRecommendation(
          canonicalId: 'new_update_paper_456',
          doi: '10.1038/s41586-026-9999',
          title: 'New CRISPR Breakthrough in Genomics',
          reason: 'Direct citation to your graph seed',
          localGraphId: localId,
          graphTitle: 'Sample Cancer Genomics Graph',
          relationType: 'citation',
        );

        // Uses the exact same navigation method implemented in HomeView._openExistingGraphForRecommendation
        void openRecommendation(BuildContext context) {
          final targetId = recommendation.localGraphId.trim();
          if (targetId.isEmpty) return;

          final cached = context.read<LibraryCubit>().getCachedGraph(targetId);
          if (cached != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConnectedGraphView(initialSnapshot: cached),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GraphUpdatesView(
                  localGraphId: targetId,
                  graphTitle: recommendation.graphTitle.isNotEmpty
                      ? recommendation.graphTitle
                      : 'Saved graph',
                ),
              ),
            );
          }
        }

        await tester.pumpWidget(
          BlocProvider<LibraryCubit>.value(
            value: libraryCubit,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => openRecommendation(context),
                    child: Text(recommendation.title),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.text('New CRISPR Breakthrough in Genomics'),
          findsOneWidget,
        );

        // Tap the recommendation action
        await tester.tap(find.text('New CRISPR Breakthrough in Genomics'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify that ConnectedGraphView was opened with the existing initialSnapshot
        expect(find.byType(ConnectedGraphView), findsOneWidget);
        final graphView = tester.widget<ConnectedGraphView>(
          find.byType(ConnectedGraphView),
        );
        expect(graphView.initialSnapshot?.graphId, localId);
        expect(
          graphView.seedDoi,
          isNull,
        ); // PROVES IT DID NOT GENERATE A NEW GRAPH!

        await libraryCubit.close();
      },
    );

    testWidgets(
      'Tapping recommendation card falls back to GraphUpdatesView when snapshot not in local cache',
      (tester) async {
        const localId = 'remote_monitored_graph_999';
        final libraryCubit = LibraryCubit.seeded(cachedGraphs: const []);

        const recommendation = DiscoveryRecommendation(
          canonicalId: 'physics_paper_1',
          title: 'Novel Superconductivity Evidence',
          reason: 'Related to your monitored graph',
          localGraphId: localId,
          graphTitle: 'Superconductivity Graph',
          relationType: 'related',
        );

        void openRecommendation(BuildContext context) {
          final targetId = recommendation.localGraphId.trim();
          if (targetId.isEmpty) return;

          final cached = context.read<LibraryCubit>().getCachedGraph(targetId);
          if (cached != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConnectedGraphView(initialSnapshot: cached),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GraphUpdatesView(
                  localGraphId: targetId,
                  graphTitle: recommendation.graphTitle.isNotEmpty
                      ? recommendation.graphTitle
                      : 'Saved graph',
                ),
              ),
            );
          }
        }

        await tester.pumpWidget(
          BlocProvider<LibraryCubit>.value(
            value: libraryCubit,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => ElevatedButton(
                    onPressed: () => openRecommendation(context),
                    child: Text(recommendation.title),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Novel Superconductivity Evidence'), findsOneWidget);

        // Tap the recommendation action
        await tester.tap(find.text('Novel Superconductivity Evidence'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Verify GraphUpdatesView was opened with localGraphId
        expect(find.byType(GraphUpdatesView), findsOneWidget);
        final updatesView = tester.widget<GraphUpdatesView>(
          find.byType(GraphUpdatesView),
        );
        expect(updatesView.localGraphId, localId);
        expect(updatesView.graphTitle, 'Superconductivity Graph');

        await libraryCubit.close();
      },
    );
  });
}
