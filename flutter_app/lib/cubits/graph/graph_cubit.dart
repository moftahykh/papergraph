import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import 'graph_state.dart';

class GraphCubit extends Cubit<GraphState> {
  final PaperGraphApiClient _apiClient;
  CancelToken? _activeCancelToken;
  Timer? _pollingTimer;
  String? _lastOriginId;
  DateTime? _pollingStartedAt;
  Duration _pollInterval = _initialPollInterval;

  /// First poll delay after dispatching a graph job.
  static const Duration _initialPollInterval = Duration(milliseconds: 750);

  /// The poll interval grows by [_backoffFactor] each round up to this ceiling.
  static const Duration _maxPollInterval = Duration(seconds: 3);

  /// Hard stop: a job that is not finished within this window is reported
  /// as timed out instead of polling forever.
  static const Duration _maxPollingDuration = Duration(minutes: 4);

  static const double _backoffFactor = 1.4;
  static const int _maxConsecutivePollErrors = 8;
  int _consecutivePollErrors = 0;

  GraphCubit({PaperGraphApiClient? apiClient})
      : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const GraphInitial());

  /// Builds a new literature graph from a seed DOI or identifier.
  Future<void> buildGraphFromDoi(
    String identifier, {
    int maxNodes = 18,
    bool includePrior = true,
    bool includeDerivative = true,
    bool checkCacheFirst = true,
  }) async {
    cancel();
    final cleanId = identifier.trim();
    _lastOriginId = cleanId;

    // 0-second instant loading from local Hive cache
    if (checkCacheFirst) {
      final cached = HiveService.getCachedGraph(cleanId, allowExpired: true);
      if (cached != null) {
        emit(
          GraphLoaded(
            snapshot: cached,
            isPartial: cached.status == GraphJobStatus.partial,
            warnings: cached.warnings,
            dataCompleteness: cached.dataCompleteness,
            fromOfflineCache: true,
          ),
        );
        return;
      }
    }

    emit(GraphCreating(cleanId));

    _activeCancelToken = CancelToken();

    try {
      final req = CreateGraphRequest(
        originId: cleanId,
        maxNodes: maxNodes,
        includePriorWorks: includePrior,
        includeDerivativeWorks: includeDerivative,
      );

      final dispatchResponse = await _apiClient.createGraph(
        req,
        cancelToken: _activeCancelToken,
      );

      final graphId = dispatchResponse.graphId;
      _startPolling(graphId);
    } on ApiException catch (e) {
      if (e.message.contains('cancelled')) return;
      emit(GraphError(e.message));
    } catch (e) {
      emit(GraphError('Failed to dispatch graph job: $e'));
    }
  }

  void _startPolling(String graphId) {
    _pollingTimer?.cancel();
    _pollingStartedAt = DateTime.now();
    _pollInterval = _initialPollInterval;
    _scheduleNextPoll(graphId);
  }

  void _scheduleNextPoll(String graphId) {
    _pollingTimer = Timer(_pollInterval, () => _pollOnce(graphId));
  }

  Future<void> _pollOnce(String graphId) async {
    if (isClosed) return;

    // Hard timeout guard — never poll indefinitely.
    final startedAt = _pollingStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > _maxPollingDuration) {
      emit(GraphError(
        'Graph generation is taking longer than expected. Please try again.',
        graphId: graphId,
      ));
      return;
    }

    try {
      final statusRes = await _apiClient.pollGraph(
        graphId,
        cancelToken: _activeCancelToken,
      );

      if (isClosed) return;
      _consecutivePollErrors = 0; // Reset error counter on successful response

      if (statusRes.status == GraphJobStatus.completed ||
          statusRes.status == GraphJobStatus.partial) {
        if (statusRes.snapshot != null) {
          try {
            await HiveService.saveCachedGraph(statusRes.snapshot!);
          } catch (_) {}
          emit(
            GraphLoaded(
              snapshot: statusRes.snapshot!,
              isPartial: statusRes.status == GraphJobStatus.partial,
              warnings: statusRes.warnings,
              dataCompleteness:
                  statusRes.dataCompleteness ?? const DataCompleteness(),
            ),
          );
        } else {
          emit(const GraphError('Graph completed but snapshot was null.'));
        }
        return; // terminal state — stop polling
      }

      if (statusRes.status == GraphJobStatus.failed) {
        emit(GraphError(statusRes.error ?? 'Graph generation failed.',
            graphId: graphId));
        return; // terminal state — stop polling
      }

      // In progress: progressive updates across the 16 lifecycle stages
      emit(
        GraphPolling(
          graphId: graphId,
          status: statusRes.status,
          progress: statusRes.progress,
          currentStage: statusRes.currentStage,
          warnings: statusRes.warnings,
          dataCompleteness: statusRes.dataCompleteness,
        ),
      );

      // Exponential backoff with a ceiling, then schedule the next poll.
      final nextMs = (_pollInterval.inMilliseconds * _backoffFactor).round();
      _pollInterval = Duration(
        milliseconds: nextMs > _maxPollInterval.inMilliseconds
            ? _maxPollInterval.inMilliseconds
            : nextMs,
      );
      _scheduleNextPoll(graphId);
    } on ApiException catch (e) {
      if (e.message.contains('cancelled')) return; // user-initiated cancel
      if (!isClosed) {
        _consecutivePollErrors++;
        if (_consecutivePollErrors < _maxConsecutivePollErrors) {
          // Transient network hiccup or timeout: retry quietly after 2s
          _pollInterval = const Duration(seconds: 2);
          _scheduleNextPoll(graphId);
        } else {
          emit(GraphError(e.message, graphId: graphId));
        }
      }
    } catch (e) {
      if (!isClosed) {
        _consecutivePollErrors++;
        if (_consecutivePollErrors < _maxConsecutivePollErrors) {
          _pollInterval = const Duration(seconds: 2);
          _scheduleNextPoll(graphId);
        } else {
          emit(GraphError('Polling error: $e', graphId: graphId));
        }
      }
    }
  }

  /// Cancels any active network request or polling timer and resets state.
  void cancel() {
    _consecutivePollErrors = 0;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _pollingStartedAt = null;
    _pollInterval = _initialPollInterval;
    _activeCancelToken?.cancel('Cancelled by user.');
    _activeCancelToken = null;
    emit(const GraphInitial());
  }

  /// Retries generating the graph for the last requested origin paper.
  void retry() {
    if (_lastOriginId != null) {
      buildGraphFromDoi(_lastOriginId!);
    }
  }

  /// Opens a previously cached graph snapshot in offline mode.
  void openCachedGraph(GraphSnapshot snapshot) {
    cancel();
    emit(
      GraphLoaded(
        snapshot: snapshot,
        isPartial: snapshot.status == GraphJobStatus.partial,
        warnings: snapshot.warnings,
        dataCompleteness: snapshot.dataCompleteness,
        fromOfflineCache: true,
      ),
    );
  }

  @override
  Future<void> close() {
    cancel();
    return super.close();
  }
}
