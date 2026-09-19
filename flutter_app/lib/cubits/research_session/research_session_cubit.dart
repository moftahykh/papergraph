import 'package:flutter_bloc/flutter_bloc.dart';

import '../graph/graph_state.dart';
import '../search/search_state.dart';
import 'research_session_state.dart';

/// Keeps the user's active research context above the individual tabs.
///
/// Home owns the search controls, but it must not own the search session.
/// This cubit is intentionally small and UI-focused: it mirrors the active
/// search/job state so Explore, Library, and Settings can all surface it.
class ResearchSessionCubit extends Cubit<ResearchSessionState> {
  ResearchSessionCubit() : super(const ResearchSessionState());

  void syncSearch(SearchState next) {
    if (next is SearchLoading) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.searching,
          query: next.query,
          progress: 0,
          clearMessage: true,
        ),
      );
      return;
    }

    if (next is SearchLoaded) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.results,
          query: next.query,
          paperCount: next.items.length,
          progress: 1,
          clearMessage: true,
        ),
      );
      return;
    }

    if (next is SearchEmpty) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.error,
          query: next.query,
          message: 'No papers matched this search.',
          progress: 0,
        ),
      );
      return;
    }

    if (next is SearchError) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.error,
          query: next.query,
          message: next.message,
          progress: 0,
        ),
      );
      return;
    }

    // SearchCubit is cleared when a DOI/URL is submitted. Do not clear a
    // graph session that is already being built or is ready to reopen.
    if (state.status == ResearchSessionStatus.searching ||
        state.status == ResearchSessionStatus.results ||
        state.status == ResearchSessionStatus.error) {
      clear();
    }
  }

  void syncGraph(GraphState next) {
    if (next is GraphCreating) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.building,
          query: next.originId,
          progress: 0.05,
          clearMessage: true,
          clearGraph: true,
          clearTitle: true,
        ),
      );
      return;
    }

    if (next is GraphPolling) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.building,
          query: next.originId,
          graphId: next.graphId,
          progress: next.progress.clamp(0.0, 1.0).toDouble(),
          clearMessage: true,
        ),
      );
      return;
    }

    if (next is GraphLoaded) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.ready,
          query: next.snapshot.origin.title,
          graphId: next.snapshot.graphId,
          title: next.snapshot.origin.title,
          paperCount: next.snapshot.nodes.length,
          progress: 1,
          clearMessage: true,
        ),
      );
      return;
    }

    if (next is GraphError) {
      emit(
        state.copyWith(
          status: ResearchSessionStatus.error,
          graphId: next.graphId,
          message: next.message,
          progress: 0,
        ),
      );
    }
  }

  void clear() => emit(const ResearchSessionState());
}