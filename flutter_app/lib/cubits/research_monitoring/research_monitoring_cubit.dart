import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_client.dart';
import '../library/library_cubit.dart';
import '../../models/research_monitoring_models.dart';
import 'research_monitoring_state.dart';

class ResearchMonitoringCubit extends Cubit<ResearchMonitoringState> {
  final PaperGraphApiClient _apiClient;
  final LibraryCubit? libraryCubit;

  ResearchMonitoringCubit({
    required this.localGraphId,
    PaperGraphApiClient? apiClient,
    this.libraryCubit,
  }) : _apiClient = apiClient ?? PaperGraphApiClient(),
       super(const ResearchMonitoringState());

  final String localGraphId;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true, updates: const []));
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
      emit(state.copyWith(isLoading: false, errorMessage: error.message));
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

  Future<bool> requestCheckNow() async {
    final monitoring = state.monitoring;
    if (monitoring == null || monitoring.isPaused) return false;
    emit(state.copyWith(isActing: true, clearError: true));
    try {
      final updated = await _apiClient.requestMonitoringScan(monitoring.id);
      emit(state.copyWith(isActing: false, monitoring: updated));
      return true;
    } on ApiException catch (error) {
      emit(state.copyWith(isActing: false, errorMessage: error.message));
      return false;
    } catch (_) {
      emit(
        state.copyWith(
          isActing: false,
          errorMessage: 'A check could not be requested right now.',
        ),
      );
      return false;
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

  Future<bool> addToGraph(ResearchUpdate update) async {
    final monitoring = state.monitoring;
    if (monitoring == null || update.isAddedToGraph) return false;
    if (libraryCubit == null) {
      emit(
        state.copyWith(
          errorMessage: 'The saved graph is not available on this device.',
        ),
      );
      return false;
    }

    emit(state.copyWith(isActing: true, clearError: true));
    try {
      final snapshot = await libraryCubit!.addResearchUpdateToGraph(
        localGraphId,
        update,
      );
      if (snapshot == null) {
        emit(
          state.copyWith(
            isActing: false,
            errorMessage: 'The paper could not be added to this graph.',
          ),
        );
        return false;
      }

      final saved = await _apiClient.markResearchUpdateAdded(
        monitoring.id,
        update.id,
      );
      _replaceUpdate(saved);
      emit(state.copyWith(isActing: false, clearError: true));
      return true;
    } on ApiException catch (error) {
      // The graph is already safely persisted locally. Keep the card marked
      // as added so a transient API failure cannot create a duplicate node.
      _replaceUpdate(update.copyWith(isAddedToGraph: true));
      emit(
        state.copyWith(
          isActing: false,
          errorMessage:
              'Added to this device, but sync is pending: ${error.message}',
        ),
      );
      return true;
    }
  }

  void _replaceUpdate(ResearchUpdate replacement) {
    final updated = state.updates
        .map((item) => item.id == replacement.id ? replacement : item)
        .toList();
    emit(state.copyWith(updates: updated, clearError: true));
  }
}
