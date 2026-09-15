import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import '../../providers/auth_provider.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit() : super(const LibraryInitial()) {
    loadLibrary();
    AuthProvider.addAuthListener(loadLibrary);
  }

  @override
  Future<void> close() {
    AuthProvider.removeAuthListener(loadLibrary);
    return super.close();
  }

  /// Loads saved papers, cached graphs, and notes from local persistent storage.
  void loadLibrary() {
    try {
      final papers = HiveService.getSavedCanonicalPapers();
      final graphs = HiveService.getCachedGraphs(includeExpired: true);
      final notes = HiveService.getAllPersonalNotes();
      emit(LibraryLoaded(
        savedPapers: papers,
        cachedGraphs: graphs,
        paperNotes: notes,
      ));
    } catch (e) {
      emit(const LibraryLoaded());
    }
  }

  /// Saves personal study notes for a research paper.
  Future<void> saveNotes(String paperId, String notes) async {
    try {
      await HiveService.savePersonalNotes(paperId, notes);
    } catch (_) {}

    final currentNotes = Map<String, String>.from(_getCurrentNotes());
    if (notes.trim().isEmpty) {
      currentNotes.remove(paperId);
    } else {
      currentNotes[paperId] = notes;
    }

    if (state is LibraryLoaded) {
      emit((state as LibraryLoaded).copyWith(paperNotes: currentNotes));
    } else {
      emit(LibraryLoaded(paperNotes: currentNotes));
    }
  }

  /// Deletes personal notes for a paper.
  Future<void> deleteNotes(String paperId) async {
    try {
      await HiveService.deletePersonalNotes(paperId);
    } catch (_) {}

    final currentNotes = Map<String, String>.from(_getCurrentNotes());
    currentNotes.remove(paperId);

    if (state is LibraryLoaded) {
      emit((state as LibraryLoaded).copyWith(paperNotes: currentNotes));
    } else {
      emit(LibraryLoaded(paperNotes: currentNotes));
    }
  }

  /// Retrieves saved personal notes for a given paper.
  String getNotes(String paperId) {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).getNotes(paperId);
    }
    return HiveService.getPersonalNotes(paperId);
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

    if (state is LibraryLoaded) {
      emit((state as LibraryLoaded).copyWith(savedPapers: updated));
    } else {
      emit(LibraryLoaded(savedPapers: updated));
    }
  }

  /// Removes a canonical paper from the library.
  Future<void> removePaper(String canonicalId) async {
    try {
      await HiveService.removeCanonicalPaper(canonicalId);
    } catch (_) {}

    final currentPapers = _getCurrentPapers();
    final updated = currentPapers.where((p) => p.canonicalId != canonicalId).toList();

    if (state is LibraryLoaded) {
      emit((state as LibraryLoaded).copyWith(savedPapers: updated));
    } else {
      emit(LibraryLoaded(savedPapers: updated));
    }
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

    if (state is LibraryLoaded) {
      emit((state as LibraryLoaded).copyWith(cachedGraphs: updated));
    } else {
      emit(LibraryLoaded(cachedGraphs: updated));
    }
  }

  /// Removes a cached graph snapshot.
  Future<void> removeCachedGraph(String graphId) async {
    try {
      await HiveService.removeCachedGraph(graphId);
    } catch (_) {}

    final currentGraphs = _getCurrentGraphs();
    final updated = currentGraphs.where((g) => g.graphId != graphId).toList();

    if (state is LibraryLoaded) {
      emit((state as LibraryLoaded).copyWith(cachedGraphs: updated));
    } else {
      emit(LibraryLoaded(cachedGraphs: updated));
    }
  }

  /// Purges all expired graph snapshots from local cache.
  Future<int> pruneExpiredGraphs() async {
    final count = await HiveService.cleanExpiredGraphs();
    loadLibrary();
    return count;
  }

  /// Looks up a cached graph snapshot by ID.
  GraphSnapshot? getCachedGraph(String graphId) {
    if (state is LibraryLoaded) {
      final found = (state as LibraryLoaded)
          .cachedGraphs
          .where((g) => g.graphId == graphId)
          .firstOrNull;
      if (found != null) return found;
    }
    return HiveService.getCachedGraph(graphId);
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

  Map<String, String> _getCurrentNotes() {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).paperNotes;
    }
    return const {};
  }
}
