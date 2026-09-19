import '../../models/graph_models.dart';
import '../../models/metric_result.dart';

/// Produces factual, user-facing relationship explanations from evidence
/// already present in a graph snapshot. It never infers topical claims that
/// are not represented by an edge, score, archetype, or publication date.
class ConnectionReasonHelper {
  static ConnectionExplanation explainConnection({
    required GraphNode node,
    required GraphSnapshot snapshot,
    GraphNode? referenceNode,
  }) {
    if (node.isOrigin) {
      return const ConnectionExplanation(
        category: ConnectionCategory.origin,
        title: 'Starting paper',
        description: 'This is the paper used to build the graph.',
        badgeLabel: 'Starting paper',
      );
    }

    final reference = referenceNode ?? _originNode(snapshot);
    final referenceIds = <String>{
      snapshot.origin.id,
      snapshot.origin.canonicalId,
      if (reference != null) reference.id,
      if (reference != null) reference.canonicalId,
    }..removeWhere((value) => value.isEmpty);
    final nodeIds = <String>{node.id, node.canonicalId}
      ..removeWhere((value) => value.isEmpty);
    final referenceTitle = reference?.title ?? snapshot.origin.title;
    final referenceYear = reference?.year ?? snapshot.origin.year;

    final referenceCitesNode = _firstEdge(
      snapshot.citationEdges,
      sourceIds: referenceIds,
      targetIds: nodeIds,
    );
    final nodeCitesReference = _firstEdge(
      snapshot.citationEdges,
      sourceIds: nodeIds,
      targetIds: referenceIds,
    );
    final similarity = _firstUndirectedEdge(
      snapshot.similarityEdges,
      leftIds: referenceIds,
      rightIds: nodeIds,
    );

    final evidence = <ConnectionEvidence>[];
    if (referenceCitesNode != null) {
      evidence.add(
        ConnectionEvidence(
          label: 'Citation direction',
          value: 'The starting paper cites this paper',
        ),
      );
    } else if (nodeCitesReference != null) {
      evidence.add(
        ConnectionEvidence(
          label: 'Citation direction',
          value: 'This paper cites the starting paper',
        ),
      );
    }
    if (similarity != null) {
      evidence.add(
        ConnectionEvidence(
          label: 'Similarity',
          value: _formatScore(similarity.weight),
        ),
      );
    }

    if (referenceCitesNode != null) {
      return ConnectionExplanation(
        category: ConnectionCategory.citation,
        title: 'Cited by the starting paper',
        description:
            'A direct citation link connects this paper to “${_truncate(referenceTitle, 54)}”.',
        badgeLabel: 'DIRECT CITATION',
        evidence: evidence,
      );
    }
    if (nodeCitesReference != null) {
      return ConnectionExplanation(
        category: ConnectionCategory.citation,
        title: 'Cites the starting paper',
        description:
            'This paper directly references “${_truncate(referenceTitle, 54)}”.',
        badgeLabel: 'DIRECT CITATION',
        evidence: evidence,
      );
    }
    if (similarity != null) {
      return ConnectionExplanation(
        category: ConnectionCategory.similarity,
        title: 'Similar research',
        description:
            'This graph contains a similarity link to the starting paper.',
        badgeLabel: '${_formatScore(similarity.weight)} SIMILAR',
        evidence: evidence,
      );
    }

    final prior = node.scores?['prior_score'];
    if (_hasSignal(prior) || _isArchetype(node, {'foundational', 'prior'})) {
      final priorEvidence = <ConnectionEvidence>[
        if (_hasSignal(prior))
          ConnectionEvidence(
            label: 'Foundation signal',
            value: _formatScore(prior!.value!),
          ),
      ];
      return ConnectionExplanation(
        category: ConnectionCategory.prior,
        title: 'Classified as earlier foundation',
        description:
            'The graph data classifies this paper as foundational or prior work.',
        badgeLabel: 'FOUNDATION',
        evidence: priorEvidence,
      );
    }

    final derivative = node.scores?['derivative_score'];
    if (_hasSignal(derivative) ||
        _isArchetype(node, {'derivative', 'subsequent'})) {
      final derivativeEvidence = <ConnectionEvidence>[
        if (_hasSignal(derivative))
          ConnectionEvidence(
            label: 'Follow-up signal',
            value: _formatScore(derivative!.value!),
          ),
      ];
      return ConnectionExplanation(
        category: ConnectionCategory.derivative,
        title: 'Classified as later research',
        description:
            'The graph data classifies this paper as derivative or subsequent work.',
        badgeLabel: 'FOLLOW-UP',
        evidence: derivativeEvidence,
      );
    }

    if (node.year != null &&
        referenceYear != null &&
        node.year != referenceYear) {
      final earlier = node.year! < referenceYear;
      return ConnectionExplanation(
        category: earlier
            ? ConnectionCategory.prior
            : ConnectionCategory.derivative,
        title: earlier ? 'Published earlier' : 'Published later',
        description:
            'Published in ${node.year}, ${earlier ? 'before' : 'after'} the $referenceYear starting paper. No direct citation or similarity link is present in this snapshot.',
        badgeLabel: earlier ? 'EARLIER' : 'LATER',
        evidence: [
          ConnectionEvidence(label: 'Publication year', value: '${node.year}'),
        ],
        evidenceLimited: true,
      );
    }

    return const ConnectionExplanation(
      category: ConnectionCategory.related,
      title: 'Included in this graph',
      description:
          'No direct citation or similarity evidence for this paper is available in the current snapshot.',
      badgeLabel: 'RELATED',
      evidenceLimited: true,
    );
  }

  static GraphNode? _originNode(GraphSnapshot snapshot) {
    for (final node in snapshot.nodes) {
      if (node.isOrigin ||
          node.canonicalId == snapshot.origin.canonicalId ||
          node.id == snapshot.origin.id) {
        return node;
      }
    }
    return null;
  }

  static GraphEdge? _firstEdge(
    List<GraphEdge> edges, {
    required Set<String> sourceIds,
    required Set<String> targetIds,
  }) {
    for (final edge in edges) {
      if (sourceIds.contains(edge.source) && targetIds.contains(edge.target)) {
        return edge;
      }
    }
    return null;
  }

  static GraphEdge? _firstUndirectedEdge(
    List<GraphEdge> edges, {
    required Set<String> leftIds,
    required Set<String> rightIds,
  }) {
    for (final edge in edges) {
      final forward =
          leftIds.contains(edge.source) && rightIds.contains(edge.target);
      final reverse =
          rightIds.contains(edge.source) && leftIds.contains(edge.target);
      if (forward || reverse) return edge;
    }
    return null;
  }

  static bool _hasSignal(MetricResult? result) {
    return result?.isAvailable == true && result!.value! > 0;
  }

  static bool _isArchetype(GraphNode node, Set<String> values) {
    final archetype = node.archetype?.trim().toLowerCase();
    return archetype != null && values.contains(archetype);
  }

  static String _formatScore(double score) {
    if (score >= 0 && score <= 1) {
      return '${(score * 100).round()}%';
    }
    return score.toStringAsFixed(2);
  }

  static String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars - 1)}…';
  }
}

enum ConnectionCategory {
  origin,
  citation,
  similarity,
  prior,
  derivative,
  related,
}

class ConnectionEvidence {
  final String label;
  final String value;

  const ConnectionEvidence({required this.label, required this.value});
}

class ConnectionExplanation {
  final ConnectionCategory category;
  final String title;
  final String description;
  final String badgeLabel;
  final List<ConnectionEvidence> evidence;
  final bool evidenceLimited;

  const ConnectionExplanation({
    required this.category,
    required this.title,
    required this.description,
    required this.badgeLabel,
    this.evidence = const [],
    this.evidenceLimited = false,
  });
}
