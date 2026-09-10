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

  const LibraryLoaded({
    this.savedPapers = const [],
    this.cachedGraphs = const [],
  });

  bool isPaperSaved(String canonicalId) {
    return savedPapers.any((p) => p.canonicalId == canonicalId);
  }

  bool isGraphCached(String graphId) {
    return cachedGraphs.any((g) => g.graphId == graphId);
  }

  LibraryLoaded copyWith({
    List<CanonicalPaper>? savedPapers,
    List<GraphSnapshot>? cachedGraphs,
  }) {
    return LibraryLoaded(
      savedPapers: savedPapers ?? this.savedPapers,
      cachedGraphs: cachedGraphs ?? this.cachedGraphs,
    );
  }
}

class LibraryError extends LibraryState {
  final String message;
  const LibraryError(this.message);
}
