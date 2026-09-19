import 'package:flutter/foundation.dart';
import 'graph_job_status.dart';
import 'metric_result.dart';

enum EdgeType {
  citation,
  similarity;

  static EdgeType fromString(String? raw) {
    if (raw?.toLowerCase() == 'citation') return EdgeType.citation;
    return EdgeType.similarity;
  }

  String get value => this == EdgeType.citation ? 'citation' : 'similarity';
}

enum ConfidenceLevel {
  high,
  medium,
  low,
  insufficient;

  static ConfidenceLevel fromString(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'high':
        return ConfidenceLevel.high;
      case 'medium':
        return ConfidenceLevel.medium;
      case 'low':
        return ConfidenceLevel.low;
      case 'insufficient':
      default:
        return ConfidenceLevel.insufficient;
    }
  }

  String get value {
    switch (this) {
      case ConfidenceLevel.high:
        return 'high';
      case ConfidenceLevel.medium:
        return 'medium';
      case ConfidenceLevel.low:
        return 'low';
      case ConfidenceLevel.insufficient:
        return 'insufficient';
    }
  }
}

@immutable
class GraphWarning {
  final String code;
  final String message;
  final String severity;

  const GraphWarning({
    required this.code,
    required this.message,
    this.severity = 'warning',
  });

  factory GraphWarning.fromJson(Map<String, dynamic> json) {
    return GraphWarning(
      code: (json['code'] as String?) ?? 'unknown_warning',
      message: (json['message'] as String?) ?? '',
      severity: (json['severity'] as String?) ?? 'warning',
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'severity': severity,
  };
}

@immutable
class DataCompleteness {
  final double metadata;
  final double references;
  final double citations;
  final double semantic;

  const DataCompleteness({
    this.metadata = 1.0,
    this.references = 1.0,
    this.citations = 1.0,
    this.semantic = 1.0,
  });

  factory DataCompleteness.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DataCompleteness();
    return DataCompleteness(
      metadata: (json['metadata'] as num?)?.toDouble() ?? 1.0,
      references: (json['references'] as num?)?.toDouble() ?? 1.0,
      citations: (json['citations'] as num?)?.toDouble() ?? 1.0,
      semantic: (json['semantic'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'metadata': metadata,
    'references': references,
    'citations': citations,
    'semantic': semantic,
  };
}

@immutable
class GraphOrigin {
  final String id;
  final String canonicalId;
  final String title;
  final int? year;
  final String? doi;

  const GraphOrigin({
    required this.id,
    required this.canonicalId,
    required this.title,
    this.year,
    this.doi,
  });

  factory GraphOrigin.fromJson(Map<String, dynamic> json) {
    return GraphOrigin(
      id: (json['id'] as String?) ?? '',
      canonicalId: (json['canonical_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Origin Seed Paper',
      year: (json['year'] as num?)?.toInt(),
      doi: json['doi'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonical_id': canonicalId,
    'title': title,
    'year': year,
    'doi': doi,
  };
}

@immutable
class GraphNode {
  final String id;
  final String canonicalId;
  final String title;
  final String? shortTitle;
  final String? doi;
  final List<String> authors;
  final int? year;
  final String? venue;
  final int citationCount;
  final bool isOrigin;
  final double radius;
  final double x;
  final double y;
  final double? finalScore;
  final ConfidenceLevel? confidence;
  final Map<String, MetricResult>? scores;
  final int? cluster;
  final String? archetype;

  const GraphNode({
    required this.id,
    required this.canonicalId,
    required this.title,
    this.shortTitle,
    this.doi,
    this.authors = const [],
    this.year,
    this.venue,
    this.citationCount = 0,
    this.isOrigin = false,
    this.radius = 12.0,
    this.x = 0.0,
    this.y = 0.0,
    this.finalScore,
    this.confidence,
    this.scores,
    this.cluster,
    this.archetype,
  });

  String get displayTitle => shortTitle ?? title;

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    Map<String, MetricResult>? parsedScores;
    if (json['scores'] != null && json['scores'] is Map) {
      parsedScores = {};
      final rawScores = json['scores'] as Map;
      for (final entry in rawScores.entries) {
        final rawMetric = entry.value;
        if (rawMetric is Map) {
          parsedScores[entry.key.toString()] = MetricResult.fromJson(
            Map<String, dynamic>.from(rawMetric),
          );
        }
      }
    }

    return GraphNode(
      id: (json['id'] as String?) ?? '',
      canonicalId: (json['canonical_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Untitled',
      shortTitle: json['short_title'] as String?,
      doi: json['doi'] as String?,
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      year: (json['year'] as num?)?.toInt(),
      venue: json['venue'] as String?,
      citationCount: (json['citation_count'] as num?)?.toInt() ?? 0,
      isOrigin: json['is_origin'] == true,
      radius: (json['radius'] as num?)?.toDouble() ?? 12.0,
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      finalScore: (json['final_score'] as num?)?.toDouble(),
      confidence: json['confidence'] != null
          ? ConfidenceLevel.fromString(json['confidence'] as String?)
          : null,
      scores: parsedScores,
      cluster: (json['cluster'] as num?)?.toInt(),
      archetype: json['archetype'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'canonical_id': canonicalId,
    'title': title,
    'short_title': shortTitle,
    'doi': doi,
    'authors': authors,
    'year': year,
    'venue': venue,
    'citation_count': citationCount,
    'is_origin': isOrigin,
    'radius': radius,
    'x': x,
    'y': y,
    'final_score': finalScore,
    'confidence': confidence?.value,
    'scores': scores?.map((k, v) => MapEntry(k, v.toJson())),
    'cluster': cluster,
    'archetype': archetype,
  };
}

@immutable
class GraphEdge {
  final String source;
  final String target;
  final EdgeType type;
  final double weight;
  final bool directed;
  final String? label;
  final Map<String, dynamic>? metadata;

  const GraphEdge({
    required this.source,
    required this.target,
    required this.type,
    this.weight = 1.0,
    this.directed = false,
    this.label,
    this.metadata,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final edgeType = EdgeType.fromString(json['type'] as String?);
    final isDirected =
        (json['directed'] as bool?) ?? (edgeType == EdgeType.citation);

    return GraphEdge(
      source: (json['source'] as String?) ?? '',
      target: (json['target'] as String?) ?? '',
      type: edgeType,
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      directed: isDirected,
      label: json['label'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'target': target,
    'type': type.value,
    'weight': weight,
    'directed': directed,
    'label': label,
    'metadata': metadata,
  };
}

@immutable
class GraphSnapshot {
  final String graphId;
  final GraphOrigin origin;
  final GraphJobStatus status;
  final List<GraphNode> nodes;
  final List<GraphEdge> similarityEdges;
  final List<GraphEdge> citationEdges;
  final DataCompleteness dataCompleteness;
  final List<GraphWarning> warnings;
  final int schemaVersion;
  final String algorithmVersion;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const GraphSnapshot({
    required this.graphId,
    required this.origin,
    required this.status,
    this.nodes = const [],
    this.similarityEdges = const [],
    this.citationEdges = const [],
    this.dataCompleteness = const DataCompleteness(),
    this.warnings = const [],
    this.schemaVersion = 1,
    this.algorithmVersion = 'v1.0',
    required this.createdAt,
    this.expiresAt,
  });

  /// Computed expiration date (defaults to 14 days after creation if not explicitly set)
  DateTime get effectiveExpiresAt =>
      expiresAt ?? createdAt.add(const Duration(days: 14));

  /// Whether this cached graph snapshot has passed its validity TTL.
  bool get isExpired => DateTime.now().isAfter(effectiveExpiresAt);

  /// Validates schema version compatibility.
  bool isCompatible(int supportedVersion) => schemaVersion == supportedVersion;

  factory GraphSnapshot.fromJson(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
        : DateTime.now();

    return GraphSnapshot(
      graphId: (json['graph_id'] as String?) ?? '',
      origin: GraphOrigin.fromJson(
        Map<String, dynamic>.from((json['origin'] as Map?) ?? {}),
      ),
      status: GraphJobStatus.fromString(json['status'] as String?),
      nodes:
          (json['nodes'] as List<dynamic>?)
              ?.map(
                (n) => GraphNode.fromJson(Map<String, dynamic>.from(n as Map)),
              )
              .toList() ??
          const [],
      similarityEdges:
          (json['similarity_edges'] as List<dynamic>?)
              ?.map(
                (e) => GraphEdge.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
      citationEdges:
          (json['citation_edges'] as List<dynamic>?)
              ?.map(
                (e) => GraphEdge.fromJson(Map<String, dynamic>.from(e as Map)),
              )
              .toList() ??
          const [],
      dataCompleteness: DataCompleteness.fromJson(
        json['data_completeness'] != null
            ? Map<String, dynamic>.from(json['data_completeness'] as Map)
            : null,
      ),
      warnings:
          (json['warnings'] as List<dynamic>?)
              ?.map(
                (w) =>
                    GraphWarning.fromJson(Map<String, dynamic>.from(w as Map)),
              )
              .toList() ??
          const [],
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      algorithmVersion: (json['algorithm_version'] as String?) ?? 'v1.0',
      createdAt: createdAt,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'graph_id': graphId,
    'origin': origin.toJson(),
    'status': status.value,
    'nodes': nodes.map((n) => n.toJson()).toList(),
    'similarity_edges': similarityEdges.map((e) => e.toJson()).toList(),
    'citation_edges': citationEdges.map((e) => e.toJson()).toList(),
    'data_completeness': dataCompleteness.toJson(),
    'warnings': warnings.map((w) => w.toJson()).toList(),
    'schema_version': schemaVersion,
    'algorithm_version': algorithmVersion,
    'created_at': createdAt.toIso8601String(),
    'expires_at': effectiveExpiresAt.toIso8601String(),
  };

  GraphSnapshot copyWith({
    String? graphId,
    GraphOrigin? origin,
    GraphJobStatus? status,
    List<GraphNode>? nodes,
    List<GraphEdge>? similarityEdges,
    List<GraphEdge>? citationEdges,
    DataCompleteness? dataCompleteness,
    List<GraphWarning>? warnings,
    int? schemaVersion,
    String? algorithmVersion,
    DateTime? createdAt,
    DateTime? expiresAt,
  }) {
    return GraphSnapshot(
      graphId: graphId ?? this.graphId,
      origin: origin ?? this.origin,
      status: status ?? this.status,
      nodes: nodes ?? this.nodes,
      similarityEdges: similarityEdges ?? this.similarityEdges,
      citationEdges: citationEdges ?? this.citationEdges,
      dataCompleteness: dataCompleteness ?? this.dataCompleteness,
      warnings: warnings ?? this.warnings,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      algorithmVersion: algorithmVersion ?? this.algorithmVersion,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

@immutable
class GraphStatusResponse {
  final String graphId;
  final GraphJobStatus status;
  final double progress;
  final GraphJobStatus currentStage;
  final String pollUrl;
  final GraphSnapshot? snapshot;
  final List<GraphWarning> warnings;
  final DataCompleteness? dataCompleteness;
  final String? error;

  const GraphStatusResponse({
    required this.graphId,
    required this.status,
    required this.progress,
    required this.currentStage,
    required this.pollUrl,
    this.snapshot,
    this.warnings = const [],
    this.dataCompleteness,
    this.error,
  });

  factory GraphStatusResponse.fromJson(Map<String, dynamic> json) {
    return GraphStatusResponse(
      graphId: (json['graph_id'] as String?) ?? '',
      status: GraphJobStatus.fromString(json['status'] as String?),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      currentStage: GraphJobStatus.fromString(json['current_stage'] as String?),
      pollUrl: (json['poll_url'] as String?) ?? '',
      snapshot: json['snapshot'] != null
          ? GraphSnapshot.fromJson(
              Map<String, dynamic>.from(json['snapshot'] as Map),
            )
          : null,
      warnings:
          (json['warnings'] as List<dynamic>?)
              ?.map(
                (w) =>
                    GraphWarning.fromJson(Map<String, dynamic>.from(w as Map)),
              )
              .toList() ??
          const [],
      dataCompleteness: json['data_completeness'] != null
          ? DataCompleteness.fromJson(
              Map<String, dynamic>.from(json['data_completeness'] as Map),
            )
          : null,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'graph_id': graphId,
    'status': status.value,
    'progress': progress,
    'current_stage': currentStage.value,
    'poll_url': pollUrl,
    'snapshot': snapshot?.toJson(),
    'warnings': warnings.map((w) => w.toJson()).toList(),
    'data_completeness': dataCompleteness?.toJson(),
    'error': error,
  };
}

@immutable
class CreateGraphRequest {
  final String originId;
  final int maxNodes;
  final bool includePriorWorks;
  final bool includeDerivativeWorks;
  final String weightProfile;
  final String algorithmVersion;

  const CreateGraphRequest({
    required this.originId,
    this.maxNodes = 40,
    this.includePriorWorks = true,
    this.includeDerivativeWorks = true,
    this.weightProfile = 'default',
    this.algorithmVersion = 'v1.0',
  });

  Map<String, dynamic> toJson() => {
    'origin_id': originId,
    'max_nodes': maxNodes,
    'include_prior_works': includePriorWorks,
    'include_derivative_works': includeDerivativeWorks,
    'weight_profile': weightProfile,
    'algorithm_version': algorithmVersion,
  };
}

@immutable
class CreateGraphResponse {
  final String graphId;
  final GraphJobStatus status;
  final String pollUrl;
  final DateTime createdAt;

  const CreateGraphResponse({
    required this.graphId,
    this.status = GraphJobStatus.queued,
    required this.pollUrl,
    required this.createdAt,
  });

  factory CreateGraphResponse.fromJson(Map<String, dynamic> json) {
    return CreateGraphResponse(
      graphId: (json['graph_id'] as String?) ?? '',
      status: GraphJobStatus.fromString(json['status'] as String?),
      pollUrl: (json['poll_url'] as String?) ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'graph_id': graphId,
    'status': status.value,
    'poll_url': pollUrl,
    'created_at': createdAt.toIso8601String(),
  };
}
