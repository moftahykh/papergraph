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

  /// Graphs explicitly saved by the user and shown in Library.
  final List<GraphSnapshot> cachedGraphs;

  /// Automatically retained graph history shown on Explore.
  final List<GraphSnapshot> recentGraphs;
  final Map<String, String> paperNotes;

  const LibraryLoaded({
    this.savedPapers = const [],
    this.cachedGraphs = const [],
    this.recentGraphs = const [],
    this.paperNotes = const {},
  });

  bool isPaperSaved(String canonicalId) {
    return savedPapers.any((paper) => paper.canonicalId == canonicalId);
  }

  bool isGraphCached(String graphId) {
    return cachedGraphs.any((graph) => graph.graphId == graphId);
  }

  String getNotes(String paperId) => paperNotes[paperId] ?? '';

  bool hasNotes(String paperId) {
    return (paperNotes[paperId]?.trim().isNotEmpty) ?? false;
  }

  bool isGraphExpired(String graphId) {
    final graph = cachedGraphs
        .where((item) => item.graphId == graphId)
        .firstOrNull;
    return graph?.isExpired ?? false;
  }

  LibraryLoaded copyWith({
    List<CanonicalPaper>? savedPapers,
    List<GraphSnapshot>? cachedGraphs,
    List<GraphSnapshot>? recentGraphs,
    Map<String, String>? paperNotes,
  }) {
    return LibraryLoaded(
      savedPapers: savedPapers ?? this.savedPapers,
      cachedGraphs: cachedGraphs ?? this.cachedGraphs,
      recentGraphs: recentGraphs ?? this.recentGraphs,
      paperNotes: paperNotes ?? this.paperNotes,
    );
  }
}

class LibraryError extends LibraryState {
  final String message;
  const LibraryError(this.message);
}
