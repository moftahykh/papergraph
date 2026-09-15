import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import '../../providers/auth_provider.dart';
import 'graph_state.dart';

class GraphCubit extends Cubit<GraphState> {
  final PaperGraphApiClient _apiClient;
  final bool _resumePendingJobs;
  CancelToken? _activeCancelToken;
  Timer? _pollingTimer;
  String? _activeGraphId;
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

  GraphCubit({PaperGraphApiClient? apiClient, bool resumePendingJob = false})
    : _apiClient = apiClient ?? PaperGraphApiClient(),
      _resumePendingJobs = resumePendingJob,
      super(const GraphInitial()) {
    AuthProvider.addAuthListener(_handleAuthChanged);
    if (resumePendingJob) {
      Future<void>.microtask(resumePendingGraphJob);
    }
  }

  bool get hasActiveJob => state is GraphCreating || state is GraphPolling;

  void _handleAuthChanged() {
    cancel();
    if (_resumePendingJobs) {
      Future<void>.microtask(resumePendingGraphJob);
    }
  }

  /// Restores polling for a job that was dispatched before the app process
  /// was closed. The backend job continues independently; the client only
  /// persists enough metadata to resume observing it.
  Future<void> resumePendingGraphJob() async {
    if (isClosed || hasActiveJob) return;
    final pending = HiveService.getPendingGraphJob();
    if (pending == null) return;

    final graphId = pending['graph_id']?.toString() ?? '';
    final originId = pending['origin_id']?.toString() ?? '';
    final startedAt = DateTime.tryParse(
      pending['started_at']?.toString() ?? '',
    );
    if (graphId.isEmpty || startedAt == null) return;

    if (DateTime.now().difference(startedAt) > _maxPollingDuration) {
      await HiveService.clearPendingGraphJob(graphId);
      if (!isClosed) {
        emit(
          GraphError(
            'The previous graph job expired before it could be restored.',
            graphId: graphId,
          ),
        );
      }
      return;
    }

    _lastOriginId = originId;
    _activeGraphId = graphId;
    _activeCancelToken = CancelToken();
    final savedProgress = (pending['progress'] as num?)?.toDouble() ?? 0.05;
    final savedStage = GraphJobStatus.fromString(
      pending['current_stage']?.toString(),
    );
    emit(
      GraphPolling(
        graphId: graphId,
        originId: originId,
        status: savedStage.isActive ? savedStage : GraphJobStatus.queued,
        progress: savedProgress.clamp(0.05, 0.98).toDouble(),
        currentStage: savedStage.isActive ? savedStage : GraphJobStatus.queued,
      ),
    );
    _startPolling(graphId, startedAt: startedAt);
  }

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
      final cached = HiveService.getCachedGraph(cleanId, allowExpired: false);
      if (cached != null) {
        emit(
          GraphLoaded(
            snapshot: cached,
            isPartial: cached.status == GraphJobStatus.partial,
            warnings: cached.warnings,
            dataCompleteness: cached.dataCompleteness,
            // This is a normal cache-first hit. Explicit offline-library opens
            // use [openCachedGraph] and remain protected from network actions.
            fromOfflineCache: false,
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
      _activeGraphId = graphId;
      final startedAt = DateTime.now();
      try {
        await HiveService.savePendingGraphJob(
          graphId: graphId,
          originId: cleanId,
          startedAt: startedAt,
          currentStage: GraphJobStatus.queued.value,
        );
      } catch (error, stackTrace) {
        // The backend accepted the job, so continue polling in memory while
        // recording that process-restart recovery is unavailable.
        debugPrint('Pending graph job could not be saved: $error\n$stackTrace');
      }
      _startPolling(graphId, startedAt: startedAt);
    } on ApiException catch (e) {
      if (e.message.contains('cancelled')) return;
      emit(GraphError(e.message));
    } catch (e) {
      emit(GraphError('Failed to dispatch graph job: $e'));
    }
  }

  void _startPolling(String graphId, {DateTime? startedAt}) {
    _pollingTimer?.cancel();
    _pollingStartedAt = startedAt ?? DateTime.now();
    _pollInterval = _initialPollInterval;
    _scheduleNextPoll(graphId);
  }

  void _scheduleNextPoll(String graphId) {
    _pollingTimer = Timer(_pollInterval, () => _pollOnce(graphId));
  }

  Future<void> _pollOnce(String graphId) async {
    if (isClosed || _activeGraphId != graphId) return;

    // Hard timeout guard — never poll indefinitely.
    final startedAt = _pollingStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) > _maxPollingDuration) {
      emit(
        GraphError(
          'Graph generation is taking longer than expected. Please try again.',
          graphId: graphId,
        ),
      );
      _finishActiveJob(graphId);
      return;
    }

    try {
      final statusRes = await _apiClient.pollGraph(
        graphId,
        cancelToken: _activeCancelToken,
      );

      if (isClosed || _activeGraphId != graphId) return;
      _consecutivePollErrors = 0; // Reset error counter on successful response

      if (statusRes.status == GraphJobStatus.completed ||
          statusRes.status == GraphJobStatus.partial) {
        if (statusRes.snapshot != null) {
          var isPersisted = true;
          String? persistenceWarning;
          try {
            await HiveService.saveCachedGraph(
              statusRes.snapshot!,
              markAsSaved: false,
            );
          } catch (error, stackTrace) {
            isPersisted = false;
            persistenceWarning =
                'The graph is ready, but it could not be saved on this device.';
            debugPrint(
              'Generated graph persistence failed: $error\n$stackTrace',
            );
          }
          emit(
            GraphLoaded(
              snapshot: statusRes.snapshot!,
              isPartial: statusRes.status == GraphJobStatus.partial,
              warnings: statusRes.warnings,
              dataCompleteness:
                  statusRes.dataCompleteness ?? const DataCompleteness(),
              isNewlyGenerated: true,
              isPersisted: isPersisted,
              persistenceWarning: persistenceWarning,
            ),
          );
          _finishActiveJob(graphId);
        } else {
          emit(
            GraphError(
              'Graph completed but snapshot was null.',
              graphId: graphId,
            ),
          );
          _finishActiveJob(graphId);
        }
        return; // terminal state — stop polling
      }

      if (statusRes.status == GraphJobStatus.failed) {
        emit(
          GraphError(
            statusRes.error ?? 'Graph generation failed.',
            graphId: graphId,
          ),
        );
        _finishActiveJob(graphId);
        return; // terminal state — stop polling
      }

      // In progress: progressive updates across the 16 lifecycle stages
      emit(
        GraphPolling(
          graphId: graphId,
          originId: _lastOriginId ?? '',
          status: statusRes.status,
          progress: statusRes.progress,
          currentStage: statusRes.currentStage,
          warnings: statusRes.warnings,
          dataCompleteness: statusRes.dataCompleteness,
        ),
      );
      unawaited(
        HiveService.savePendingGraphJob(
          graphId: graphId,
          originId: _lastOriginId ?? '',
          startedAt: _pollingStartedAt ?? DateTime.now(),
          progress: statusRes.progress,
          currentStage: statusRes.currentStage.value,
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
          _finishActiveJob(graphId);
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
          _finishActiveJob(graphId);
        }
      }
    }
  }

  void _finishActiveJob(String graphId) {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (_activeGraphId == graphId) {
      _activeGraphId = null;
    }
    _activeCancelToken = null;
    unawaited(HiveService.clearPendingGraphJob(graphId));
  }

  /// Cancels any active network request or polling timer and resets state.
  void cancel() {
    final graphId = _activeGraphId;
    _consecutivePollErrors = 0;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _pollingStartedAt = null;
    _pollInterval = _initialPollInterval;
    _activeCancelToken?.cancel('Cancelled by user.');
    _activeCancelToken = null;
    _activeGraphId = null;
    if (graphId != null) {
      unawaited(HiveService.clearPendingGraphJob(graphId));
    }
    if (!isClosed) emit(const GraphInitial());
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
    AuthProvider.removeAuthListener(_handleAuthChanged);
    cancel();
    return super.close();
  }
}
