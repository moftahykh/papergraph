import 'package:flutter/foundation.dart';
import 'canonical_paper.dart';

@immutable
class SearchResultItem {
  final String canonicalId;
  final String title;
  final List<String> authors;
  final int? year;
  final String? venue;
  final int citationCount;
  final String? doi;
  final double? score;

  const SearchResultItem({
    required this.canonicalId,
    required this.title,
    this.authors = const [],
    this.year,
    this.venue,
    this.citationCount = 0,
    this.doi,
    this.score,
  });

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      canonicalId: (json['canonical_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Untitled',
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      year: (json['year'] as num?)?.toInt(),
      venue: json['venue'] as String?,
      citationCount: (json['citation_count'] as num?)?.toInt() ?? 0,
      doi: json['doi'] as String?,
      score: (json['score'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'canonical_id': canonicalId,
    'title': title,
    'authors': authors,
    'year': year,
    'venue': venue,
    'citation_count': citationCount,
    'doi': doi,
    'score': score,
  };
}

@immutable
class SearchResponse {
  final String query;
  final int total;
  final List<SearchResultItem> items;
  final bool disambiguationNeeded;
  final List<SearchResultItem> candidates;

  const SearchResponse({
    required this.query,
    this.total = 0,
    this.items = const [],
    this.disambiguationNeeded = false,
    this.candidates = const [],
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    return SearchResponse(
      query: (json['query'] as String?) ?? '',
      total: (json['total'] as num?)?.toInt() ?? 0,
      items:
          (json['items'] as List<dynamic>?)
              ?.map(
                (item) => SearchResultItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList() ??
          const [],
      disambiguationNeeded: json['disambiguation_needed'] == true,
      candidates:
          (json['candidates'] as List<dynamic>?)
              ?.map(
                (item) => SearchResultItem.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'query': query,
    'total': total,
    'items': items.map((e) => e.toJson()).toList(),
    'disambiguation_needed': disambiguationNeeded,
    'candidates': candidates.map((e) => e.toJson()).toList(),
  };
}

@immutable
class PaperResolveResponse {
  final bool resolved;
  final CanonicalPaper? paper;
  final List<CanonicalPaper> ambiguousCandidates;
  final double confidence;
  final String? message;

  const PaperResolveResponse({
    required this.resolved,
    this.paper,
    this.ambiguousCandidates = const [],
    this.confidence = 1.0,
    this.message,
  });

  factory PaperResolveResponse.fromJson(Map<String, dynamic> json) {
    return PaperResolveResponse(
      resolved: json['resolved'] == true,
      paper: json['paper'] != null
          ? CanonicalPaper.fromJson(
              Map<String, dynamic>.from(json['paper'] as Map),
            )
          : null,
      ambiguousCandidates:
          (json['ambiguous_candidates'] as List<dynamic>?)
              ?.map(
                (p) => CanonicalPaper.fromJson(
                  Map<String, dynamic>.from(p as Map),
                ),
              )
              .toList() ??
          const [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      message: json['message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'resolved': resolved,
    'paper': paper?.toJson(),
    'ambiguous_candidates': ambiguousCandidates.map((e) => e.toJson()).toList(),
    'confidence': confidence,
    'message': message,
  };
}

@immutable
class PaperDetailsResponse {
  final CanonicalPaper paper;
  final String? tldr;
  final String? openAccessUrl;
  final String? bibtex;
  final List<String> affiliations;
  final bool isSaved;

  const PaperDetailsResponse({
    required this.paper,
    this.tldr,
    this.openAccessUrl,
    this.bibtex,
    this.affiliations = const [],
    this.isSaved = false,
  });

  factory PaperDetailsResponse.fromJson(Map<String, dynamic> json) {
    return PaperDetailsResponse(
      paper: CanonicalPaper.fromJson(
        Map<String, dynamic>.from(json['paper'] as Map),
      ),
      tldr: json['tldr'] as String?,
      openAccessUrl: json['open_access_url'] as String?,
      bibtex: json['bibtex'] as String?,
      affiliations:
          (json['affiliations'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isSaved: json['is_saved'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'paper': paper.toJson(),
    'tldr': tldr,
    'open_access_url': openAccessUrl,
    'bibtex': bibtex,
    'affiliations': affiliations,
    'is_saved': isSaved,
  };
}

@immutable
class DiscoveryTopic {
  final String label;
  final String query;
  final int rank;

  const DiscoveryTopic({
    required this.label,
    required this.query,
    this.rank = 0,
  });

  factory DiscoveryTopic.fromJson(Map<String, dynamic> json) {
    return DiscoveryTopic(
      label: (json['label'] as String?) ?? '',
      query: (json['query'] as String?) ?? '',
      rank: (json['rank'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'query': query,
    'rank': rank,
  };
}

@immutable
class DiscoveryRecommendation {
  final String canonicalId;
  final String? doi;
  final String title;
  final String reason;
  final String localGraphId;
  final String graphTitle;
  final String relationType;
  final double relevanceScore;
  final DateTime? detectedAt;

  const DiscoveryRecommendation({
    required this.canonicalId,
    this.doi,
    required this.title,
    required this.reason,
    required this.localGraphId,
    required this.graphTitle,
    required this.relationType,
    this.relevanceScore = 0,
    this.detectedAt,
  });

  factory DiscoveryRecommendation.fromJson(Map<String, dynamic> json) {
    return DiscoveryRecommendation(
      canonicalId: (json['canonical_id'] as String?) ?? '',
      doi: json['doi'] as String?,
      title: (json['title'] as String?) ?? 'Untitled paper',
      reason: (json['reason'] as String?) ?? 'Related to your research.',
      localGraphId: (json['local_graph_id'] as String?) ?? '',
      graphTitle: (json['graph_title'] as String?) ?? 'Saved graph',
      relationType: (json['relation_type'] as String?) ?? 'related',
      relevanceScore: (json['relevance_score'] as num?)?.toDouble() ?? 0,
      detectedAt: json['detected_at'] == null
          ? null
          : DateTime.tryParse(json['detected_at'].toString()),
    );
  }

  Map<String, dynamic> toJson() => {
    'canonical_id': canonicalId,
    'doi': doi,
    'title': title,
    'reason': reason,
    'local_graph_id': localGraphId,
    'graph_title': graphTitle,
    'relation_type': relationType,
    'relevance_score': relevanceScore,
    'detected_at': detectedAt?.toIso8601String(),
  };
}

@immutable
class DiscoveryHomeResponse {
  final List<DiscoveryTopic> topics;
  final DiscoveryRecommendation? recommendation;

  const DiscoveryHomeResponse({
    this.topics = const [],
    this.recommendation,
  });

  factory DiscoveryHomeResponse.fromJson(Map<String, dynamic> json) {
    return DiscoveryHomeResponse(
      topics: (json['topics'] as List<dynamic>?)
              ?.map(
                (item) => DiscoveryTopic.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .where((topic) => topic.label.isNotEmpty && topic.query.isNotEmpty)
              .toList() ??
          const [],
      recommendation: json['recommendation'] == null
          ? null
          : DiscoveryRecommendation.fromJson(
              Map<String, dynamic>.from(
                json['recommendation'] as Map,
              ),
            ),
    );
  }

  Map<String, dynamic> toJson() => {
    'topics': topics.map((t) => t.toJson()).toList(),
    'recommendation': recommendation?.toJson(),
  };
}
