import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_client.dart';
import '../../models/research_monitoring_models.dart';
import 'research_monitoring_state.dart';

class ResearchMonitoringCubit extends Cubit<ResearchMonitoringState> {
  final PaperGraphApiClient _apiClient;

  ResearchMonitoringCubit({
    required this.localGraphId,
    PaperGraphApiClient? apiClient,
  }) : _apiClient = apiClient ?? PaperGraphApiClient(),
       super(const ResearchMonitoringState());

  final String localGraphId;

  Future<void> load() async {
    emit(
      state.copyWith(
        isLoading: true,
        clearError: true,
        updates: const [],
      ),
    );
    try {
      final graphs = await _apiClient.listMonitoredGraphs();
      MonitoredGraphSummary? monitoring;
      for (final graph in graphs) {
        if (graph.localGraphId == localGraphId) {
          monitoring = graph;
          break;
        }
      }

      if (monitoring == null) {
        emit(
          state.copyWith(
            isLoading: false,
            clearMonitoring: true,
            updates: const [],
          ),
        );
        return;
      }

      final updates = await _apiClient.getResearchUpdates(monitoring.id);
      emit(
        state.copyWith(
          isLoading: false,
          monitoring: monitoring,
          updates: updates,
          clearError: true,
        ),
      );
    } on ApiException catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: error.message,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Research updates could not be loaded.',
        ),
      );
    }
  }

  Future<void> setPaused(bool paused) async {
    final monitoring = state.monitoring;
    if (monitoring == null) return;
    emit(state.copyWith(isActing: true, clearError: true));
    try {
      final updated = await _apiClient.updateMonitoredGraph(
        monitoring.id,
        status: paused ? 'paused' : 'active',
      );
      emit(state.copyWith(isActing: false, monitoring: updated));
    } on ApiException catch (error) {
      emit(state.copyWith(isActing: false, errorMessage: error.message));
    } catch (_) {
      emit(
        state.copyWith(
          isActing: false,
          errorMessage: 'Monitoring could not be updated.',
        ),
      );
    }
  }

  Future<bool> stopMonitoring() async {
    final monitoring = state.monitoring;
    if (monitoring == null) return true;
    emit(state.copyWith(isActing: true, clearError: true));
    try {
      await _apiClient.removeMonitoredGraph(localGraphId);
      emit(
        state.copyWith(
          isActing: false,
          clearMonitoring: true,
          updates: const [],
        ),
      );
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(isActing: false, errorMessage: error.message));
      return false;
    } catch (_) {
      emit(
        state.copyWith(
          isActing: false,
          errorMessage: 'Monitoring could not be stopped.',
        ),
      );
      return false;
    }
  }

  Future<void> markRead(ResearchUpdate update) async {
    final monitoring = state.monitoring;
    if (monitoring == null || update.isRead) return;
    try {
      final saved = await _apiClient.markResearchUpdateRead(
        monitoring.id,
        update.id,
      );
      _replaceUpdate(saved);
    } on ApiException catch (error) {
      emit(state.copyWith(errorMessage: error.message));
    }
  }

  Future<void> addToGraph(ResearchUpdate update) async {
    final monitoring = state.monitoring;
    if (monitoring == null || update.isAddedToGraph) return;
    try {
      final saved = await _apiClient.markResearchUpdateAdded(
        monitoring.id,
        update.id,
      );
      _replaceUpdate(saved);
    } on ApiException catch (error) {
      emit(state.copyWith(errorMessage: error.message));
    }
  }

  void _replaceUpdate(ResearchUpdate replacement) {
    final updated = state.updates
        .map((item) => item.id == replacement.id ? replacement : item)
        .toList();
    emit(state.copyWith(updates: updated, clearError: true));
  }
}