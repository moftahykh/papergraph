import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/network/api_client.dart';
import '../../core/services/hive_service.dart';
import '../../core/services/research_update_graph_service.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';
import '../../models/research_monitoring_models.dart';
import '../../providers/auth_provider.dart';
import 'library_state.dart';

class LibraryCubit extends Cubit<LibraryState> {
  final bool listenToAuth;
  final bool logFailures;
  final PaperGraphApiClient _apiClient;

  LibraryCubit({
    LibraryState initialState = const LibraryInitial(),
    bool loadOnStart = true,
    this.listenToAuth = true,
    this.logFailures = true,
    PaperGraphApiClient? apiClient,
  }) : _apiClient = apiClient ?? PaperGraphApiClient(),
       super(initialState) {
    if (loadOnStart) loadLibrary();
    if (listenToAuth) AuthProvider.addAuthListener(loadLibrary);
  }

  factory LibraryCubit.seeded({
    List<CanonicalPaper> savedPapers = const [],
    List<GraphSnapshot> cachedGraphs = const [],
    List<GraphSnapshot>? recentGraphs,
    Map<String, String> paperNotes = const {},
  }) {
    return LibraryCubit(
      initialState: LibraryLoaded(
        savedPapers: savedPapers,
        cachedGraphs: cachedGraphs,
        recentGraphs: recentGraphs ?? cachedGraphs,
        paperNotes: paperNotes,
      ),
      loadOnStart: false,
      listenToAuth: false,
      logFailures: false,
    );
  }

  @override
  Future<void> close() {
    if (listenToAuth) AuthProvider.removeAuthListener(loadLibrary);
    return super.close();
  }

  /// Loads the active account's library without replacing known-good content
  /// with an empty list when storage is temporarily unavailable.
  void loadLibrary() {
    try {
      final papers = HiveService.getSavedCanonicalPapers();
      final savedGraphs = HiveService.getCachedGraphs(
        includeExpired: true,
        savedOnly: true,
      );
      final recentGraphs = HiveService.getCachedGraphs(includeExpired: true);
      final notes = HiveService.getAllPersonalNotes();
      emit(
        LibraryLoaded(
          savedPapers: papers,
          cachedGraphs: savedGraphs,
          recentGraphs: recentGraphs,
          paperNotes: notes,
        ),
      );
    } catch (error, stackTrace) {
      if (logFailures) {
        debugPrint('Library load failed: $error\n$stackTrace');
      }
      if (state is! LibraryLoaded) {
        emit(
          const LibraryError(
            'Your library could not be opened. Please try again.',
          ),
        );
      }
    }
  }

  Future<bool> saveNotes(String paperId, String notes) async {
    try {
      await HiveService.savePersonalNotes(paperId, notes);
      final currentNotes = Map<String, String>.from(_getCurrentNotes());
      if (notes.trim().isEmpty) {
        currentNotes.remove(paperId);
      } else {
        currentNotes[paperId] = notes;
      }
      _emitLoaded(paperNotes: currentNotes);
      return true;
    } catch (error, stackTrace) {
      _logWriteFailure('save notes', error, stackTrace);
      return false;
    }
  }

  Future<bool> deleteNotes(String paperId) async {
    try {
      await HiveService.deletePersonalNotes(paperId);
      final currentNotes = Map<String, String>.from(_getCurrentNotes())
        ..remove(paperId);
      _emitLoaded(paperNotes: currentNotes);
      return true;
    } catch (error, stackTrace) {
      _logWriteFailure('delete notes', error, stackTrace);
      return false;
    }
  }

  String getNotes(String paperId) {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).getNotes(paperId);
    }
    return HiveService.getPersonalNotes(paperId);
  }

  Future<bool> savePaper(CanonicalPaper paper) async {
    try {
      await HiveService.saveCanonicalPaper(paper);
      final updated = List<CanonicalPaper>.from(_getCurrentPapers());
      final index = updated.indexWhere(
        (item) => item.canonicalId == paper.canonicalId,
      );
      if (index >= 0) {
        updated[index] = paper;
      } else {
        updated.insert(0, paper);
      }
      _emitLoaded(savedPapers: updated);
      return true;
    } catch (error, stackTrace) {
      _logWriteFailure('save paper', error, stackTrace);
      return false;
    }
  }

  Future<bool> removePaper(String canonicalId) async {
    try {
      await HiveService.removeCanonicalPaper(canonicalId);
      final updated = _getCurrentPapers()
          .where((paper) => paper.canonicalId != canonicalId)
          .toList();
      _emitLoaded(savedPapers: updated);
      return true;
    } catch (error, stackTrace) {
      _logWriteFailure('remove paper', error, stackTrace);
      return false;
    }
  }

  Future<bool> toggleSavePaper(CanonicalPaper paper) {
    return isPaperSaved(paper.canonicalId)
        ? removePaper(paper.canonicalId)
        : savePaper(paper);
  }

  bool isPaperSaved(String canonicalId) {
    if (state is LibraryLoaded) {
      return (state as LibraryLoaded).isPaperSaved(canonicalId);
    }
    return HiveService.isCanonicalPaperSaved(canonicalId);
  }

  Future<bool> cacheGraph(GraphSnapshot snapshot) async {
    try {
      await HiveService.saveCachedGraph(snapshot, markAsSaved: true);
      final updated = List<GraphSnapshot>.from(_getCurrentGraphs());
      final index = updated.indexWhere(
        (graph) => graph.graphId == snapshot.graphId,
      );
      if (index >= 0) {
        updated[index] = snapshot;
      } else {
        updated.insert(0, snapshot);
      }
      updated.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final recent = List<GraphSnapshot>.from(_getRecentGraphs());
      final recentIndex = recent.indexWhere(
        (graph) => graph.graphId == snapshot.graphId,
      );
      if (recentIndex >= 0) {
        recent[recentIndex] = snapshot;
      } else {
        recent.insert(0, snapshot);
      }
      recent.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _emitLoaded(cachedGraphs: updated, recentGraphs: recent);
      // Local saving must never wait on Render, Semantic Scholar, or the
      // monitoring API. The graph is immediately usable offline; monitoring
      // registration continues independently and logs a retryable failure.
      unawaited(syncMonitoring(snapshot));
      return true;
    } catch (error, stackTrace) {
      _logWriteFailure('save graph', error, stackTrace);
      return false;
    }
  }

  /// Persists a monitoring result as an incremental graph node.
  ///
  /// This does not rebuild the graph or replace existing coordinates. The
  /// local snapshot is saved first; monitoring registration is then refreshed
  /// so future scans can treat the new paper as part of the graph.
  Future<GraphSnapshot?> addResearchUpdateToGraph(
    String graphId,
    ResearchUpdate update,
  ) async {
    final snapshot = getCachedGraph(graphId);
    if (snapshot == null) return null;

    final updated = ResearchUpdateGraphService.addToSnapshot(snapshot, update);
    if (updated == snapshot) return snapshot;

    final saved = await cacheGraph(updated);
    return saved ? updated : null;
  }

  Future<bool> removeCachedGraph(String graphId) async {
    try {
      await HiveService.removeCachedGraph(graphId);
      await _syncMonitoringAfterDelete(graphId);
      final updated = _getCurrentGraphs()
          .where((graph) => graph.graphId != graphId)
          .toList();
      final recent = _getRecentGraphs()
          .where((graph) => graph.graphId != graphId)
          .toList();
      _emitLoaded(cachedGraphs: updated, recentGraphs: recent);
      return true;
    } catch (error, stackTrace) {
      _logWriteFailure('remove graph', error, stackTrace);
      return false;
    }
  }

  Future<int> pruneExpiredGraphs() async {
    try {
      final count = await HiveService.cleanExpiredGraphs();
      loadLibrary();
      return count;
    } catch (error, stackTrace) {
      _logWriteFailure('remove outdated graphs', error, stackTrace);
      return 0;
    }
  }

  GraphSnapshot? getCachedGraph(String graphId) {
    if (state is LibraryLoaded) {
      final found = (state as LibraryLoaded).cachedGraphs
          .where((graph) => graph.graphId == graphId)
          .firstOrNull;
      if (found != null) return found;
    }
    return HiveService.getCachedGraph(graphId);
  }

  void _emitLoaded({
    List<CanonicalPaper>? savedPapers,
    List<GraphSnapshot>? cachedGraphs,
    List<GraphSnapshot>? recentGraphs,
    Map<String, String>? paperNotes,
  }) {
    final current = state is LibraryLoaded
        ? state as LibraryLoaded
        : const LibraryLoaded();
    emit(
      current.copyWith(
        savedPapers: savedPapers,
        cachedGraphs: cachedGraphs,
        recentGraphs: recentGraphs,
        paperNotes: paperNotes,
      ),
    );
  }

  void _logWriteFailure(String operation, Object error, StackTrace stackTrace) {
    if (logFailures) {
      debugPrint('Library failed to $operation: $error\n$stackTrace');
    }
  }

  /// Attempts to register a saved graph for remote research updates.
  ///
  /// Local persistence is deliberately independent from this network action.
  /// Callers that need an explicit retry can await this method.
  Future<bool> syncMonitoring(GraphSnapshot snapshot) async {
    if (!_apiClient.hasAuthenticatedFirebaseUser) return false;
    try {
      await _apiClient.registerMonitoredGraph(snapshot);
      return true;
    } catch (error, stackTrace) {
      // Local persistence remains the source of truth while offline. A
      // durable retry queue will be added before production monitoring ships.
      debugPrint(
        'Saved graph locally, but monitoring sync failed: $error\n$stackTrace',
      );
      return false;
    }
  }

  Future<void> _syncMonitoringAfterDelete(String graphId) async {
    if (!_apiClient.hasAuthenticatedFirebaseUser) return;
    try {
      await _apiClient.removeMonitoredGraph(graphId);
    } catch (error, stackTrace) {
      debugPrint(
        'Deleted graph locally, but monitoring removal failed: '
        '$error\n$stackTrace',
      );
    }
  }

  List<CanonicalPaper> _getCurrentPapers() {
    return state is LibraryLoaded
        ? (state as LibraryLoaded).savedPapers
        : const [];
  }

  List<GraphSnapshot> _getCurrentGraphs() {
    return state is LibraryLoaded
        ? (state as LibraryLoaded).cachedGraphs
        : const [];
  }

  List<GraphSnapshot> _getRecentGraphs() {
    return state is LibraryLoaded
        ? (state as LibraryLoaded).recentGraphs
        : const [];
  }

  Map<String, String> _getCurrentNotes() {
    return state is LibraryLoaded
        ? (state as LibraryLoaded).paperNotes
        : const {};
  }
}
