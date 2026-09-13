import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/network/api_client.dart';
import 'package:paper_graph/cubits/graph/graph_cubit.dart';
import 'package:paper_graph/cubits/graph/graph_state.dart';
import 'package:paper_graph/cubits/library/library_cubit.dart';
import 'package:paper_graph/cubits/library/library_state.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_state.dart';
import 'package:paper_graph/cubits/paper_details/paper_details_cubit.dart';
import 'package:paper_graph/cubits/paper_details/paper_details_state.dart';
import 'package:paper_graph/cubits/search/search_cubit.dart';
import 'package:paper_graph/cubits/search/search_state.dart';
import 'package:paper_graph/cubits/theme/theme_cubit.dart';
import 'package:paper_graph/models/api_schemas.dart';
import 'package:paper_graph/models/canonical_paper.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';

class FakePaperGraphApiClient extends PaperGraphApiClient {
  SearchResponse? mockSearchResponse;
  ApiException? mockSearchException;
  CreateGraphResponse? mockCreateResponse;
  ApiException? mockCreateException;
  GraphStatusResponse? mockStatusResponse;
  List<GraphStatusResponse> mockPollSequence = [];
  PaperDetailsResponse? mockDetailsResponse;
  ApiException? mockDetailsException;

  @override
  Future<SearchResponse> search(
    String query, {
    int limit = 10,
    int offset = 0,
    String? provider,
    CancelToken? cancelToken,
  }) async {
    if (mockSearchException != null) throw mockSearchException!;
    return mockSearchResponse ?? const SearchResponse(query: 'test');
  }

  @override
  Future<CreateGraphResponse> createGraph(
    CreateGraphRequest request, {
    CancelToken? cancelToken,
  }) async {
    if (mockCreateException != null) throw mockCreateException!;
    return mockCreateResponse ??
        CreateGraphResponse(
          graphId: 'graph-123',
          pollUrl: '/graphs/graph-123',
          createdAt: DateTime.now(),
        );
  }

  @override
  Future<GraphStatusResponse> pollGraph(
    String graphId, {
    CancelToken? cancelToken,
  }) async {
    if (mockPollSequence.isNotEmpty) {
      return mockPollSequence.removeAt(0);
    }
    return mockStatusResponse ??
        GraphStatusResponse(
          graphId: graphId,
          status: GraphJobStatus.completed,
          progress: 1.0,
          currentStage: GraphJobStatus.completed,
          pollUrl: '/graphs/$graphId',
        );
  }

  @override
  Future<PaperDetailsResponse> getPaperDetails(
    String paperId, {
    CancelToken? cancelToken,
  }) async {
    if (mockDetailsException != null) throw mockDetailsException!;
    return mockDetailsResponse ??
        PaperDetailsResponse(
          paper: CanonicalPaper(
            canonicalId: paperId,
            title: 'Test Paper',
            normalizedTitle: 'test paper',
            authors: const [],
          ),
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SearchCubit Tests', () {
    late FakePaperGraphApiClient fakeApi;
    late SearchCubit cubit;

    setUp(() {
      fakeApi = FakePaperGraphApiClient();
      cubit = SearchCubit(apiClient: fakeApi);
    });

    tearDown(() {
      cubit.close();
    });

    test('Short query resets to SearchInitial', () async {
      await cubit.search('a');
      expect(cubit.state, isA<SearchInitial>());
    });

    test('Successful search emits SearchLoaded with results', () async {
      fakeApi.mockSearchResponse = const SearchResponse(
        query: 'attention',
        total: 1,
        items: [
          SearchResultItem(
            canonicalId: 'paper-1',
            title: 'Attention Is All You Need',
            citationCount: 95000,
          ),
        ],
      );

      final future = cubit.search('attention', immediate: true);
      expect(cubit.state, isA<SearchLoading>());
      await future;

      expect(cubit.state, isA<SearchLoaded>());
      final loaded = cubit.state as SearchLoaded;
      expect(loaded.items.length, 1);
      expect(loaded.items.first.title, 'Attention Is All You Need');
    });

    test('Empty results emit SearchEmpty', () async {
      fakeApi.mockSearchResponse = const SearchResponse(
        query: 'nonexistent query 12345',
        total: 0,
        items: [],
      );

      await cubit.search('nonexistent query 12345', immediate: true);
      expect(cubit.state, isA<SearchEmpty>());
      final empty = cubit.state as SearchEmpty;
      expect(empty.query, 'nonexistent query 12345');
    });

    test('ApiException emits SearchError with message', () async {
      fakeApi.mockSearchException = const ApiException(
        'Backend connection refused',
        statusCode: 503,
      );

      await cubit.search('transformer', immediate: true);
      expect(cubit.state, isA<SearchError>());
      final err = cubit.state as SearchError;
      expect(err.message, 'Backend connection refused');
    });

    test('clear resets to SearchInitial', () async {
      fakeApi.mockSearchResponse = const SearchResponse(
        query: 'test',
        total: 1,
        items: [SearchResultItem(canonicalId: '1', title: 'Test')],
      );
      await cubit.search('test', immediate: true);
      expect(cubit.state, isA<SearchLoaded>());

      cubit.clear();
      expect(cubit.state, isA<SearchInitial>());
    });
  });

  group('GraphCubit Tests', () {
    late FakePaperGraphApiClient fakeApi;
    late GraphCubit cubit;

    setUp(() {
      fakeApi = FakePaperGraphApiClient();
      cubit = GraphCubit(apiClient: fakeApi);
    });

    tearDown(() {
      cubit.close();
    });

    test('buildGraphFromDoi dispatches job and polls to completion', () async {
      final sampleSnapshot = GraphSnapshot(
        graphId: 'graph-999',
        origin: const GraphOrigin(
          id: 'origin-1',
          canonicalId: '10.1000/182',
          title: 'Seed',
        ),
        status: GraphJobStatus.completed,
        nodes: const [
          GraphNode(
            id: 'node-seed',
            canonicalId: 'seed',
            title: 'Origin Paper',
            isOrigin: true,
          ),
          GraphNode(
            id: 'node-p1',
            canonicalId: 'p1',
            title: 'Related Paper 1',
          ),
        ],
        createdAt: DateTime.now(),
      );

      fakeApi.mockCreateResponse = CreateGraphResponse(
        graphId: 'graph-999',
        pollUrl: '/graphs/graph-999',
        createdAt: DateTime.now(),
      );

      fakeApi.mockPollSequence = [
        const GraphStatusResponse(
          graphId: 'graph-999',
          status: GraphJobStatus.resolvingOrigin,
          progress: 0.15,
          currentStage: GraphJobStatus.resolvingOrigin,
          pollUrl: '/graphs/graph-999',
        ),
        GraphStatusResponse(
          graphId: 'graph-999',
          status: GraphJobStatus.completed,
          progress: 1.0,
          currentStage: GraphJobStatus.completed,
          pollUrl: '/graphs/graph-999',
          snapshot: sampleSnapshot,
        ),
      ];

      await cubit.buildGraphFromDoi('10.1000/182');
      expect(cubit.state, isA<GraphCreating>());

      // First poll fires after the initial 750ms interval
      await Future.delayed(const Duration(milliseconds: 900));
      expect(cubit.state, isA<GraphPolling>());
      var pollingState = cubit.state as GraphPolling;
      expect(pollingState.currentStage, GraphJobStatus.resolvingOrigin);

      // Later polls back off exponentially (750ms * 1.4 = ~1050ms), so wait
      // generously for the second poll delivering the completed snapshot.
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (cubit.state is! GraphLoaded && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      expect(cubit.state, isA<GraphLoaded>());
      final loadedState = cubit.state as GraphLoaded;
      expect(loadedState.snapshot.nodes.length, 2);
      expect(loadedState.isPartial, false);
      expect(loadedState.fromOfflineCache, false);
    });

    test('Failed graph job emits GraphError', () async {
      fakeApi.mockCreateResponse = CreateGraphResponse(
        graphId: 'graph-err',
        pollUrl: '/graphs/graph-err',
        createdAt: DateTime.now(),
      );

      fakeApi.mockPollSequence = [
        const GraphStatusResponse(
          graphId: 'graph-err',
          status: GraphJobStatus.failed,
          progress: 0.2,
          currentStage: GraphJobStatus.enrichingMetadata,
          pollUrl: '/graphs/graph-err',
          error: 'Rate limit exceeded on external gateway',
        ),
      ];

      await cubit.buildGraphFromDoi('10.1000/error');
      await Future.delayed(const Duration(milliseconds: 900));

      expect(cubit.state, isA<GraphError>());
      final err = cubit.state as GraphError;
      expect(err.message, 'Rate limit exceeded on external gateway');
    });

    test('openCachedGraph loads snapshot in offline mode', () {
      final snapshot = GraphSnapshot(
        graphId: 'offline-graph-1',
        origin: const GraphOrigin(
          id: 'offline-origin',
          canonicalId: 'seed-offline',
          title: 'Offline Title',
        ),
        status: GraphJobStatus.completed,
        nodes: const [
          GraphNode(
            id: 'node-offline',
            canonicalId: 'seed-offline',
            title: 'Offline Title',
            isOrigin: true,
          ),
        ],
        createdAt: DateTime.now(),
      );

      cubit.openCachedGraph(snapshot);
      expect(cubit.state, isA<GraphLoaded>());
      final loaded = cubit.state as GraphLoaded;
      expect(loaded.fromOfflineCache, true);
      expect(loaded.snapshot.graphId, 'offline-graph-1');
    });

    test('cancel stops active polling timer', () async {
      fakeApi.mockCreateResponse = CreateGraphResponse(
        graphId: 'graph-cancel',
        pollUrl: '/graphs/graph-cancel',
        createdAt: DateTime.now(),
      );

      await cubit.buildGraphFromDoi('10.1000/cancel');
      cubit.cancel();

      // Ensure timer does not fire further updates
      await Future.delayed(const Duration(milliseconds: 900));
      expect(cubit.state, isA<GraphCreating>());
    });
  });

  group('PaperDetailsCubit Tests', () {
    late FakePaperGraphApiClient fakeApi;
    late PaperDetailsCubit cubit;

    setUp(() {
      fakeApi = FakePaperGraphApiClient();
      cubit = PaperDetailsCubit(apiClient: fakeApi);
    });

    tearDown(() {
      cubit.close();
    });

    test('loadDetails emits PaperDetailsLoaded on success', () async {
      fakeApi.mockDetailsResponse = const PaperDetailsResponse(
        paper: CanonicalPaper(
          canonicalId: 'paper-details-1',
          title: 'Deep Residual Learning for Image Recognition',
          normalizedTitle: 'deep residual learning for image recognition',
          year: 2016,
          citationCount: 160000,
          authors: [Author(name: 'Kaiming He')],
        ),
        tldr: 'Presents deep residual learning framework.',
        affiliations: ['Microsoft Research'],
        isSaved: false,
      );

      final future = cubit.loadDetails('paper-details-1');
      expect(cubit.state, isA<PaperDetailsLoading>());
      await future;

      expect(cubit.state, isA<PaperDetailsLoaded>());
      final loaded = cubit.state as PaperDetailsLoaded;
      expect(loaded.details.paper.title, 'Deep Residual Learning for Image Recognition');
      expect(loaded.isSaved, false);

      cubit.toggleSaved();
      expect((cubit.state as PaperDetailsLoaded).isSaved, true);
    });

    test('loadDetails emits PaperDetailsError on failure', () async {
      fakeApi.mockDetailsException = const ApiException(
        'Paper ID not found',
        statusCode: 404,
      );

      await cubit.loadDetails('invalid-id');
      expect(cubit.state, isA<PaperDetailsError>());
      final err = cubit.state as PaperDetailsError;
      expect(err.message, 'Paper ID not found');
    });
  });

  group('LibraryCubit Tests', () {
    late LibraryCubit cubit;

    setUp(() {
      cubit = LibraryCubit();
    });

    tearDown(() {
      cubit.close();
    });

    test('savePaper and removePaper manage local library state', () async {
      const paper = CanonicalPaper(
        canonicalId: 'saved-1',
        title: 'Foundations of Science',
        normalizedTitle: 'foundations of science',
        authors: [Author(name: 'Author One')],
      );

      await cubit.savePaper(paper);
      expect(cubit.isPaperSaved('saved-1'), true);

      var state = cubit.state as LibraryLoaded;
      expect(state.savedPapers.length, 1);
      expect(state.savedPapers.first.title, 'Foundations of Science');

      await cubit.toggleSavePaper(paper);
      expect(cubit.isPaperSaved('saved-1'), false);
      state = cubit.state as LibraryLoaded;
      expect(state.savedPapers.isEmpty, true);
    });

    test('cacheGraph and removeCachedGraph manage snapshot cache', () async {
      final snapshot = GraphSnapshot(
        graphId: 'cache-g-1',
        origin: const GraphOrigin(
          id: 'origin-cache',
          canonicalId: 'seed',
          title: 'Seed',
        ),
        status: GraphJobStatus.completed,
        createdAt: DateTime.now(),
      );

      await cubit.cacheGraph(snapshot);
      var state = cubit.state as LibraryLoaded;
      expect(state.isGraphCached('cache-g-1'), true);
      expect(state.cachedGraphs.length, 1);

      await cubit.removeCachedGraph('cache-g-1');
      state = cubit.state as LibraryLoaded;
      expect(state.isGraphCached('cache-g-1'), false);
      expect(state.cachedGraphs.isEmpty, true);
    });
  });

  group('ThemeCubit Tests', () {
    late ThemeCubit cubit;

    setUp(() {
      cubit = ThemeCubit();
    });

    tearDown(() {
      cubit.close();
    });

    test('toggleTheme alternates between dark and light mode', () async {
      final initialMode = cubit.state.themeMode;
      await cubit.toggleTheme();
      expect(cubit.state.themeMode, isNot(initialMode));

      await cubit.toggleTheme();
      expect(cubit.state.themeMode, initialMode);
    });

    test('setThemeMode updates theme directly', () async {
      await cubit.setThemeMode(ThemeMode.light);
      expect(cubit.state.themeMode, ThemeMode.light);
      expect(cubit.state.isDark, false);

      await cubit.setThemeMode(ThemeMode.dark);
      expect(cubit.state.themeMode, ThemeMode.dark);
      expect(cubit.state.isDark, true);
    });
  });

  group('NotificationCubit Tests', () {
    late NotificationCubit cubit;

    setUp(() {
      cubit = NotificationCubit();
    });

    tearDown(() {
      cubit.close();
    });

    test('notify creates in-app notification and toast', () {
      cubit.notify(
        title: 'Test Notification',
        message: 'This is a test notification message.',
        type: NotificationType.info,
      );

      expect(cubit.state.notifications.length, 1);
      expect(cubit.state.latestToast, isNotNull);
      expect(cubit.state.latestToast?.title, 'Test Notification');
      expect(cubit.state.unreadCount, 1);
    });

    test('notifyGraphReady generates specialized completion notice', () {
      cubit.notifyGraphReady('graph-456', 38, isPartial: false);
      expect(cubit.state.notifications.first.type, NotificationType.success);
      expect(cubit.state.notifications.first.title, 'Literature Graph Ready');

      cubit.notifyGraphReady('graph-partial', 22, isPartial: true);
      expect(cubit.state.notifications.first.type, NotificationType.warning);
      expect(cubit.state.notifications.first.title, 'Graph Ready (Partial)');
    });

    test('dismissToast clears active toast without removing notification history', () {
      cubit.notify(title: 'Alert', message: 'Something happened');
      expect(cubit.state.latestToast, isNotNull);

      cubit.dismissToast();
      expect(cubit.state.latestToast, isNull);
      expect(cubit.state.notifications.length, 1);
    });

    test('markAsRead updates isRead state and unreadCount', () {
      cubit.notify(title: 'Notice', message: 'Hello');
      final notifId = cubit.state.notifications.first.id;
      expect(cubit.state.unreadCount, 1);

      cubit.markAsRead(notifId);
      expect(cubit.state.unreadCount, 0);
      expect(cubit.state.notifications.first.isRead, true);
    });

    test('clearAll wipes notifications and toast', () {
      cubit.notify(title: 'N1', message: 'M1');
      cubit.notify(title: 'N2', message: 'M2');
      expect(cubit.state.notifications.length, 2);

      cubit.clearAll();
      expect(cubit.state.notifications.isEmpty, true);
      expect(cubit.state.latestToast, isNull);
    });
  });
}
