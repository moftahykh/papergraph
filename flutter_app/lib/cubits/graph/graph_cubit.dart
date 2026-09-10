import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/network/api_client.dart';
import '../../models/graph_job_status.dart';
import '../../models/graph_models.dart';
import 'graph_state.dart';

class GraphCubit extends Cubit<GraphState> {
  final PaperGraphApiClient _apiClient;
  CancelToken? _activeCancelToken;
  Timer? _pollingTimer;
  String? _lastOriginId;

  GraphCubit({PaperGraphApiClient? apiClient})
      : _apiClient = apiClient ?? PaperGraphApiClient(),
        super(const GraphInitial());

  /// Builds a new literature graph from a seed DOI or identifier.
  Future<void> buildGraphFromDoi(
    String identifier, {
    int maxNodes = 40,
    bool includePrior = true,
    bool includeDerivative = true,
  }) async {
    cancel();
    _lastOriginId = identifier;
    emit(GraphCreating(identifier));

    _activeCancelToken = CancelToken();

    try {
      final req = CreateGraphRequest(
        originId: identifier,
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
      emit(GraphError(e.message));
    } catch (e) {
      emit(GraphError('Failed to dispatch graph job: $e'));
    }
  }

  void _startPolling(String graphId) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 750), (timer) async {
      try {
        final statusRes = await _apiClient.pollGraph(
          graphId,
          cancelToken: _activeCancelToken,
        );

        if (isClosed) {
          timer.cancel();
          return;
        }

        if (statusRes.status == GraphJobStatus.completed ||
            statusRes.status == GraphJobStatus.partial) {
          timer.cancel();
          if (statusRes.snapshot != null) {
            emit(
              GraphLoaded(
                snapshot: statusRes.snapshot!,
                isPartial: statusRes.status == GraphJobStatus.partial,
                warnings: statusRes.warnings,
                dataCompleteness: statusRes.dataCompleteness ?? const DataCompleteness(),
              ),
            );
          } else {
            emit(const GraphError('Graph completed but snapshot was null.'));
          }
        } else if (statusRes.status == GraphJobStatus.failed) {
          timer.cancel();
          emit(GraphError(statusRes.error ?? 'Graph generation failed.', graphId: graphId));
        } else {
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
        }
      } on ApiException catch (e) {
        timer.cancel();
        if (!isClosed) {
          emit(GraphError(e.message, graphId: graphId));
        }
      } catch (e) {
        timer.cancel();
        if (!isClosed) {
          emit(GraphError('Polling error: $e', graphId: graphId));
        }
      }
    });
  }

  /// Cancels any active network request or polling timer.
  void cancel() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _activeCancelToken?.cancel('Cancelled by user.');
    _activeCancelToken = null;
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
