import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit() : super(const LibraryInitial()) {
    loadLibrary();
  }

  /// Loads saved papers and cached graphs from local persistent storage.
  void loadLibrary() {
    try {
      final papers = HiveService.getSavedCanonicalPapers();
      final graphs = HiveService.getCachedGraphs();
      emit(LibraryLoaded(savedPapers: papers, cachedGraphs: graphs));
    } catch (e) {
      emit(LibraryLoaded(savedPapers: const [], cachedGraphs: const []));
    }
  }

  /// Saves a canonical paper to the library.
  Future<void> savePaper(CanonicalPaper paper) async {
    try {
      await HiveService.saveCanonicalPaper(paper);
    } catch (_) {}

    final currentPapers = _getCurrentPapers();
    final updated = List<CanonicalPaper>.from(currentPapers);
    final idx = updated.indexWhere((p) => p.canonicalId == paper.canonicalId);
    if (idx >= 0) {
      updated[idx] = paper;
    } else {
      updated.insert(0, paper);
    }

    final currentGraphs = _getCurrentGraphs();
    emit(LibraryLoaded(savedPapers: updated, cachedGraphs: currentGraphs));
  }

  /// Removes a canonical paper from the library.
  Future<void> removePaper(String canonicalId) async {
    try {
      await HiveService.removeCanonicalPaper(canonicalId);
    } catch (_) {}

    final currentPapers = _getCurrentPapers();
    final updated = currentPapers.where((p) => p.canonicalId != canonicalId).toList();
    final currentGraphs = _getCurrentGraphs();
    emit(LibraryLoaded(savedPapers: updated, cachedGraphs: currentGraphs));
  }

  /// Toggles paper saved state.
  Future<void> toggleSavePaper(CanonicalPaper paper) async {
    if (isPaperSaved(paper.canonicalId)) {
      await removePaper(paper.canonicalId);
    } else {
      await savePaper(paper);
    }
  }

  /// Checks if a paper is already saved in the library.
  bool isPaperSaved(String canonicalId) {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).isPaperSaved(canonicalId);
    }
    return HiveService.isCanonicalPaperSaved(canonicalId);
  }

  /// Caches a graph snapshot for offline access.
  Future<void> cacheGraph(GraphSnapshot snapshot) async {
    try {
      await HiveService.saveCachedGraph(snapshot);
    } catch (_) {}

    final currentGraphs = _getCurrentGraphs();
    final updated = List<GraphSnapshot>.from(currentGraphs);
    final idx = updated.indexWhere((g) => g.graphId == snapshot.graphId);
    if (idx >= 0) {
      updated[idx] = snapshot;
    } else {
      updated.insert(0, snapshot);
    }

    final currentPapers = _getCurrentPapers();
    emit(LibraryLoaded(savedPapers: currentPapers, cachedGraphs: updated));
  }

  /// Removes a cached graph snapshot.
  Future<void> removeCachedGraph(String graphId) async {
    try {
      await HiveService.removeCachedGraph(graphId);
    } catch (_) {}

    final currentGraphs = _getCurrentGraphs();
    final updated = currentGraphs.where((g) => g.graphId != graphId).toList();
    final currentPapers = _getCurrentPapers();
    emit(LibraryLoaded(savedPapers: currentPapers, cachedGraphs: updated));
  }

  List<CanonicalPaper> _getCurrentPapers() {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).savedPapers;
    }
    return const [];
  }

  List<GraphSnapshot> _getCurrentGraphs() {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).cachedGraphs;
    }
    return const [];
  }
}
