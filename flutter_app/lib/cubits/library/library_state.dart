import 'package:flutter/foundation.dart';
import '../../models/canonical_paper.dart';
import '../../models/graph_models.dart';

@immutable
abstract class LibraryState {
  const LibraryState();
}

class LibraryInitial extends LibraryState {
  const LibraryInitial();
}

class LibraryLoading extends LibraryState {
  const LibraryLoading();
}

class LibraryLoaded extends LibraryState {
  final List<CanonicalPaper> savedPapers;
  final List<GraphSnapshot> cachedGraphs;
  final Map<String, String> paperNotes;

  const LibraryLoaded({
    this.savedPapers = const [],
    this.cachedGraphs = const [],
    this.paperNotes = const {},
  });

  bool isPaperSaved(String canonicalId) {
    return savedPapers.any((p) => p.canonicalId == canonicalId);
  }

  bool isGraphCached(String graphId) {
    return cachedGraphs.any((g) => g.graphId == graphId);
  }

  String getNotes(String paperId) {
    return paperNotes[paperId] ?? '';
  }

  bool hasNotes(String paperId) {
    return (paperNotes[paperId]?.trim().isNotEmpty) ?? false;
  }

  bool isGraphExpired(String graphId) {
    final graph = cachedGraphs.where((g) => g.graphId == graphId).firstOrNull;
    return graph?.isExpired ?? false;
  }

  LibraryLoaded copyWith({
    List<CanonicalPaper>? savedPapers,
    List<GraphSnapshot>? cachedGraphs,
    Map<String, String>? paperNotes,
  }) {
    return LibraryLoaded(
      savedPapers: savedPapers ?? this.savedPapers,
      cachedGraphs: cachedGraphs ?? this.cachedGraphs,
      paperNotes: paperNotes ?? this.paperNotes,
    );
  }
}

class LibraryError extends LibraryState {
  final String message;
  const LibraryError(this.message);
}
