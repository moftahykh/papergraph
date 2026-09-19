import 'dart:math' as math;

import '../../models/graph_models.dart';
import '../../models/research_monitoring_models.dart';

/// Applies a single monitoring result to an already-saved graph snapshot.
///
/// This is intentionally an incremental operation: existing nodes and their
/// positions are preserved, while the discovered paper is added once and
/// connected to the graph origin when the scanner supplied a usable relation.
class ResearchUpdateGraphService {
  const ResearchUpdateGraphService._();

  static GraphSnapshot addToSnapshot(
    GraphSnapshot snapshot,
    ResearchUpdate update,
  ) {
    final canonicalId = update.canonicalPaperId.trim();
    if (canonicalId.isEmpty) return snapshot;

    final normalizedDoi = _normalizeDoi(update.doi);
    final alreadyPresent = snapshot.nodes.any(
      (node) =>
          node.canonicalId == canonicalId ||
          (normalizedDoi != null &&
              _normalizeDoi(node.canonicalId.replaceFirst('doi:', '')) ==
                  normalizedDoi) ||
          (snapshot.origin.canonicalId == canonicalId &&
              (normalizedDoi == null ||
                  _normalizeDoi(snapshot.origin.doi) == normalizedDoi)),
    );
    if (alreadyPresent) return snapshot;

    final index = snapshot.nodes.length;
    final position = _nextPosition(snapshot, index);
    final relation = update.relationType.toLowerCase();
    final node = GraphNode(
      id: canonicalId,
      canonicalId: canonicalId,
      title: update.title,
      shortTitle: update.title.length > 40
          ? '${update.title.substring(0, 40)}...'
          : update.title,
      doi: update.doi,
      year: update.publishedAt?.year,
      citationCount: 0,
      isOrigin: false,
      radius: 12.0,
      x: position.$1,
      y: position.$2,
      finalScore: update.relevanceScore,
      confidence: ConfidenceLevel.medium,
      cluster: 5,
      archetype: relation == 'direct_citation' ? 'derivative_work' : 'similar',
    );

    final nodes = [...snapshot.nodes, node];
    final similarityEdges = [...snapshot.similarityEdges];
    final citationEdges = [...snapshot.citationEdges];
    final metadata = <String, dynamic>{
      'source': 'research_monitoring_update',
      'update_id': update.id,
      'relation_type': update.relationType,
      'explanation': update.explanation,
    };

    if (relation == 'direct_citation') {
      // The scanner discovers papers citing papers already in the graph.
      citationEdges.add(
        GraphEdge(
          source: canonicalId,
          target: snapshot.origin.canonicalId,
          type: EdgeType.citation,
          directed: true,
          weight: update.relevanceScore.clamp(0.0, 1.0),
          label: 'Direct citation',
          metadata: metadata,
        ),
      );
    } else if (relation == 'semantic_similarity' ||
        relation == 'related_recommendation' ||
        relation == 'shared_references' ||
        relation == 'same_topic') {
      similarityEdges.add(
        GraphEdge(
          source: snapshot.origin.canonicalId,
          target: canonicalId,
          type: EdgeType.similarity,
          directed: false,
          weight: update.relevanceScore.clamp(0.0, 1.0),
          label: 'Research update',
          metadata: metadata,
        ),
      );
    }

    return snapshot.copyWith(
      nodes: nodes,
      similarityEdges: similarityEdges,
      citationEdges: citationEdges,
    );
  }

  static (double, double) _nextPosition(GraphSnapshot snapshot, int index) {
    final origin = snapshot.nodes.where((node) => node.isOrigin).firstOrNull;
    var maxRadius = 180.0;
    for (final node in snapshot.nodes) {
      final radius = math.sqrt(node.x * node.x + node.y * node.y);
      if (radius > maxRadius) maxRadius = radius;
    }
    final baseRadius = maxRadius + 45.0;
    final angle = (index % 12) * (2 * math.pi / 12) + math.pi / 12;
    final originX = origin?.x ?? 0.0;
    final originY = origin?.y ?? 0.0;
    return (
      (originX + math.cos(angle) * baseRadius).roundToDouble(),
      (originY + math.sin(angle) * baseRadius).roundToDouble(),
    );
  }

  static String? _normalizeDoi(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    var doi = value.trim().toLowerCase();
    for (final prefix in ['https://doi.org/', 'http://doi.org/', 'doi:']) {
      if (doi.startsWith(prefix)) {
        doi = doi.substring(prefix.length);
        break;
      }
    }
    return doi;
  }
}
