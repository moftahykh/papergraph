import 'package:flutter/foundation.dart';

@immutable
class MonitoredGraphSummary {
  final String id;
  final String localGraphId;
  final String graphTitle;
  final String status;
  final String frequency;
  final String timezone;
  final DateTime? lastCheckedAt;
  final DateTime nextCheckAt;
  final DateTime? lastNotifiedAt;

  const MonitoredGraphSummary({
    required this.id,
    required this.localGraphId,
    required this.graphTitle,
    required this.status,
    required this.frequency,
    required this.timezone,
    required this.nextCheckAt,
    this.lastCheckedAt,
    this.lastNotifiedAt,
  });

  bool get isPaused => status == 'paused';

  factory MonitoredGraphSummary.fromJson(Map<String, dynamic> json) {
    DateTime parseRequiredDate(String key) {
      return DateTime.tryParse(json[key] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    DateTime? parseOptionalDate(String key) {
      final raw = json[key] as String?;
      return raw == null ? null : DateTime.tryParse(raw);
    }

    return MonitoredGraphSummary(
      id: (json['id'] as String?) ?? '',
      localGraphId: (json['local_graph_id'] as String?) ?? '',
      graphTitle: (json['graph_title'] as String?) ?? 'Saved graph',
      status: (json['status'] as String?) ?? 'active',
      frequency: (json['frequency'] as String?) ?? 'daily',
      timezone: (json['timezone'] as String?) ?? 'Asia/Riyadh',
      nextCheckAt: parseRequiredDate('next_check_at'),
      lastCheckedAt: parseOptionalDate('last_checked_at'),
      lastNotifiedAt: parseOptionalDate('last_notified_at'),
    );
  }
}

@immutable
class ResearchUpdate {
  final String id;
  final String monitoredGraphId;
  final String canonicalPaperId;
  final String? doi;
  final String title;
  final String? abstractText;
  final DateTime? publishedAt;
  final double relevanceScore;
  final String relationType;
  final String explanation;
  final DateTime detectedAt;
  final bool isRead;
  final bool isAddedToGraph;

  const ResearchUpdate({
    required this.id,
    required this.monitoredGraphId,
    required this.canonicalPaperId,
    required this.title,
    required this.relevanceScore,
    required this.relationType,
    required this.explanation,
    required this.detectedAt,
    this.doi,
    this.abstractText,
    this.publishedAt,
    this.isRead = false,
    this.isAddedToGraph = false,
  });

  ResearchUpdate copyWith({
    bool? isRead,
    bool? isAddedToGraph,
  }) {
    return ResearchUpdate(
      id: id,
      monitoredGraphId: monitoredGraphId,
      canonicalPaperId: canonicalPaperId,
      doi: doi,
      title: title,
      abstractText: abstractText,
      publishedAt: publishedAt,
      relevanceScore: relevanceScore,
      relationType: relationType,
      explanation: explanation,
      detectedAt: detectedAt,
      isRead: isRead ?? this.isRead,
      isAddedToGraph: isAddedToGraph ?? this.isAddedToGraph,
    );
  }

  factory ResearchUpdate.fromJson(Map<String, dynamic> json) {
    return ResearchUpdate(
      id: (json['id'] as String?) ?? '',
      monitoredGraphId: (json['monitored_graph_id'] as String?) ?? '',
      canonicalPaperId: (json['canonical_paper_id'] as String?) ?? '',
      doi: json['doi'] as String?,
      title: (json['title'] as String?) ?? 'Untitled research update',
      abstractText: json['abstract'] as String?,
      publishedAt: _parseDate(json['published_at']),
      relevanceScore: (json['relevance_score'] as num?)?.toDouble() ?? 0,
      relationType: (json['relation_type'] as String?) ?? 'related',
      explanation: (json['explanation'] as String?) ?? '',
      detectedAt:
          _parseDate(json['detected_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      isRead: json['is_read'] == true,
      isAddedToGraph: json['is_added_to_graph'] == true,
    );
  }

  static DateTime? _parseDate(Object? raw) {
    return raw is String ? DateTime.tryParse(raw) : null;
  }
}