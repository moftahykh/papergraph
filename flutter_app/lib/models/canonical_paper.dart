import 'package:flutter/foundation.dart';

@immutable
class Author {
  final String? id;
  final String name;
  final int? position;
  final String? affiliation;

  const Author({this.id, required this.name, this.position, this.affiliation});

  factory Author.fromJson(Map<String, dynamic> json) {
    return Author(
      id: json['id'] as String?,
      name: (json['name'] as String?) ?? 'Unknown Author',
      position: (json['position'] as num?)?.toInt(),
      affiliation: json['affiliation'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'position': position,
      'affiliation': affiliation,
    };
  }
}

@immutable
class SourceAvailability {
  final bool semanticScholar;
  final bool openAlex;
  final bool crossref;
  final bool pubmed;

  const SourceAvailability({
    this.semanticScholar = false,
    this.openAlex = false,
    this.crossref = false,
    this.pubmed = false,
  });

  factory SourceAvailability.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SourceAvailability();
    return SourceAvailability(
      semanticScholar: json['semantic_scholar'] == true,
      openAlex: json['open_alex'] == true,
      crossref: json['crossref'] == true,
      pubmed: json['pubmed'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'semantic_scholar': semanticScholar,
      'open_alex': openAlex,
      'crossref': crossref,
      'pubmed': pubmed,
    };
  }
}

@immutable
class CanonicalPaper {
  final String canonicalId;
  final String? doi;
  final String? pmid;
  final String? semanticScholarId;
  final String? openAlexId;
  final String title;
  final String normalizedTitle;
  final List<Author> authors;
  final int? year;
  final String? venue;
  final String? abstractText;
  final int citationCount;
  final int referenceCount;
  final List<String> referenceIds;
  final List<String> citationIds;
  final List<String> topics;
  final SourceAvailability sourceAvailability;
  final double completeness;
  final Map<String, dynamic> provenance;

  const CanonicalPaper({
    required this.canonicalId,
    this.doi,
    this.pmid,
    this.semanticScholarId,
    this.openAlexId,
    required this.title,
    required this.normalizedTitle,
    this.authors = const [],
    this.year,
    this.venue,
    this.abstractText,
    this.citationCount = 0,
    this.referenceCount = 0,
    this.referenceIds = const [],
    this.citationIds = const [],
    this.topics = const [],
    this.sourceAvailability = const SourceAvailability(),
    this.completeness = 0.0,
    this.provenance = const {},
  });

  String get authorDisplay {
    if (authors.isEmpty) return 'Author information unavailable';
    if (authors.length == 1) return authors.first.name;
    if (authors.length == 2) return '${authors[0].name} & ${authors[1].name}';
    return '${authors.first.name} et al.';
  }

  String get yearDisplay => year != null ? year.toString() : 'Year unavailable';

  factory CanonicalPaper.fromJson(Map<String, dynamic> json) {
    return CanonicalPaper(
      canonicalId: (json['canonical_id'] as String?) ?? '',
      doi: json['doi'] as String?,
      pmid: json['pmid'] as String?,
      semanticScholarId: json['semantic_scholar_id'] as String?,
      openAlexId: json['open_alex_id'] as String?,
      title: (json['title'] as String?) ?? 'Untitled Work',
      normalizedTitle: (json['normalized_title'] as String?) ?? '',
      authors:
          (json['authors'] as List<dynamic>?)
              ?.map((a) => Author.fromJson(Map<String, dynamic>.from(a as Map)))
              .toList() ??
          const [],
      year: (json['year'] as num?)?.toInt(),
      venue: json['venue'] as String?,
      abstractText: json['abstract'] as String?,
      citationCount: (json['citation_count'] as num?)?.toInt() ?? 0,
      referenceCount: (json['reference_count'] as num?)?.toInt() ?? 0,
      referenceIds:
          (json['reference_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      citationIds:
          (json['citation_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      topics:
          (json['topics'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      sourceAvailability: SourceAvailability.fromJson(
        json['source_availability'] != null
            ? Map<String, dynamic>.from(json['source_availability'] as Map)
            : null,
      ),
      completeness: (json['completeness'] as num?)?.toDouble() ?? 0.0,
      provenance: json['provenance'] != null
          ? Map<String, dynamic>.from(json['provenance'] as Map)
          : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'canonical_id': canonicalId,
      'doi': doi,
      'pmid': pmid,
      'semantic_scholar_id': semanticScholarId,
      'open_alex_id': openAlexId,
      'title': title,
      'normalized_title': normalizedTitle,
      'authors': authors.map((a) => a.toJson()).toList(),
      'year': year,
      'venue': venue,
      'abstract': abstractText,
      'citation_count': citationCount,
      'reference_count': referenceCount,
      'reference_ids': referenceIds,
      'citation_ids': citationIds,
      'topics': topics,
      'source_availability': sourceAvailability.toJson(),
      'completeness': completeness,
      'provenance': provenance,
    };
  }
}
