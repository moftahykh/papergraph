import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import '../../models/api_schemas.dart';
import '../../providers/auth_provider.dart';
import 'discovery_state.dart';

class DiscoveryCubit extends Cubit<DiscoveryState> {
  final PaperGraphApiClient _apiClient;
  final bool listenToAuth;
  bool _hasLoaded = false;
  String? _lastLoadedUserIdScope;

  DiscoveryCubit({
    PaperGraphApiClient? apiClient,
    this.listenToAuth = true,
  })  : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const DiscoveryInitial()) {
    if (listenToAuth) {
      AuthProvider.addAuthListener(onAuthChanged);
    }
  }

  void onAuthChanged() {
    final currentScope = HiveService.activeUserId;
    if (_lastLoadedUserIdScope != null &&
        _lastLoadedUserIdScope != currentScope) {
      // User switched account or logged out: immediately clear the prior user's
      // recommendation to guarantee multi-account data isolation.
      if (state is DiscoveryLoaded) {
        final cur = state as DiscoveryLoaded;
        emit(DiscoveryLoaded(topics: cur.topics, recommendation: null));
      }
      _hasLoaded = false;
      load(force: true);
    }
  }

  @override
  Future<void> close() {
    if (listenToAuth) {
      AuthProvider.removeAuthListener(onAuthChanged);
    }
    return super.close();
  }

  Future<void> load({bool force = false}) async {
    if (_hasLoaded && !force && state is DiscoveryLoaded) return;

    List<DiscoveryTopic> currentTopics = const [];
    if (state is DiscoveryLoaded) {
      currentTopics = (state as DiscoveryLoaded).topics;
    } else {
      final cached = HiveService.getCachedDiscoveryTopics();
      if (cached != null && cached.isNotEmpty) {
        currentTopics = cached.map(DiscoveryTopic.fromJson).toList();
        emit(DiscoveryLoaded(topics: currentTopics, recommendation: null));
      } else {
        emit(const DiscoveryLoading());
      }
    }

    try {
      final response = await _apiClient.getDiscoveryHome();
      _hasLoaded = true;
      _lastLoadedUserIdScope = HiveService.activeUserId;

      final topics =
          response.topics.isNotEmpty ? response.topics : currentTopics;
      if (response.topics.isNotEmpty) {
        await HiveService.saveCachedDiscoveryTopics(
          response.topics.map((t) => t.toJson()).toList(),
        );
      }

      emit(
        DiscoveryLoaded(
          topics: topics,
          recommendation: response.recommendation,
        ),
      );
    } on ApiException catch (error) {
      if (currentTopics.isNotEmpty) {
        emit(DiscoveryLoaded(topics: currentTopics, recommendation: null));
      } else {
        emit(DiscoveryUnavailable(error.message));
      }
    } catch (_) {
      if (currentTopics.isNotEmpty) {
        emit(DiscoveryLoaded(topics: currentTopics, recommendation: null));
      } else {
        emit(const DiscoveryUnavailable(
          'Discovery is temporarily unavailable.',
        ));
      }
    }
  }
}
