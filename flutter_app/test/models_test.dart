import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/models/canonical_paper.dart';
import 'package:paper_graph/models/metric_result.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/models/api_schemas.dart';

void main() {
  group('MetricResult Null vs Zero Tests (Non-Negotiable Rule #6)', () {
    test('distinguishes null metric from evaluated zero metric', () {
      final nullJson = {
        'value': null,
        'availability': 'unavailable',
        'reason': 'references_not_loaded',
      };
      final nullMetric = MetricResult.fromJson(nullJson);
      expect(nullMetric.value, isNull);
      expect(nullMetric.availability, MetricAvailability.unavailable);
      expect(nullMetric.isAvailable, isFalse);

      final zeroJson = {
        'value': 0.0,
        'availability': 'available',
        'reason': 'evaluated_zero_coupling',
      };
      final zeroMetric = MetricResult.fromJson(zeroJson);
      expect(zeroMetric.value, 0.0);
      expect(zeroMetric.availability, MetricAvailability.available);
      expect(zeroMetric.isAvailable, isTrue);

      expect(nullMetric.value, isNot(equals(zeroMetric.value)));
    });

    test('parses provider error state', () {
      final errorMetric = MetricResult.fromJson({
        'value': null,
        'availability': 'provider_error',
        'reason': 'upstream_timeout_504',
      });
      expect(errorMetric.availability, MetricAvailability.providerError);
      expect(errorMetric.isAvailable, isFalse);
    });
  });

  group('CanonicalPaper Model Tests', () {
    test('parses full canonical paper payload with authors and sources', () {
      final json = {
        'canonical_id': 'doi:10.1145/357172.357176',
        'doi': '10.1145/357172.357176',
        'pmid': null,
        'semantic_scholar_id': 'b3e9e30a5e8c71b6',
        'open_alex_id': 'https://openalex.org/W2147152072',
        'title': 'The Byzantine Generals Problem',
        'normalized_title': 'the byzantine generals problem',
        'authors': [
          {'name': 'Leslie Lamport', 'position': 1, 'affiliation': 'SRI'},
          {'name': 'Robert Shostak', 'position': 2},
        ],
        'year': 1982,
        'venue': 'ACM TOPLAS',
        'abstract': 'Reliable computer systems...',
        'citation_count': 8940,
        'reference_count': 18,
        'reference_ids': ['doi:10.1145/359545.359563'],
        'topics': ['Computer Science', 'Distributed Systems'],
        'source_availability': {
          'semantic_scholar': true,
          'open_alex': true,
          'crossref': true,
          'pubmed': false,
        },
        'completeness': 0.95,
      };

      final paper = CanonicalPaper.fromJson(json);
      expect(paper.canonicalId, 'doi:10.1145/357172.357176');
      expect(paper.authorDisplay, 'Leslie Lamport & Robert Shostak');
      expect(paper.yearDisplay, '1982');
      expect(paper.authors.length, 2);
      expect(paper.sourceAvailability.semanticScholar, isTrue);
      expect(paper.sourceAvailability.pubmed, isFalse);
      expect(paper.completeness, 0.95);
    });
  });

  group('GraphEdge Edge-Typing Tests (Non-Negotiable Rule #9)', () {
    test(
      'differentiates directional citation vs non-directional similarity',
      () {
        final citationJson = {
          'source': 'doi:paper_a',
          'target': 'doi:paper_b',
          'type': 'citation',
          'weight': 1.0,
          'directed': true,
        };
        final citationEdge = GraphEdge.fromJson(citationJson);
        expect(citationEdge.type, EdgeType.citation);
        expect(citationEdge.directed, isTrue);

        final similarityJson = {
          'source': 'doi:paper_a',
          'target': 'doi:paper_b',
          'type': 'similarity',
          'weight': 0.78,
          'directed': false,
        };
        final similarityEdge = GraphEdge.fromJson(similarityJson);
        expect(similarityEdge.type, EdgeType.similarity);
        expect(similarityEdge.directed, isFalse);
      },
    );
  });

  group('GraphJobStatus 16 Lifecycle Stages Tests', () {
    test('contains all 16 discrete states', () {
      const statuses = [
        'queued',
        'resolving_origin',
        'generating_candidates',
        'pre_ranking',
        'enriching_metadata',
        'enriching_references',
        'computing_wbc',
        'enriching_citations',
        'computing_ncc',
        'computing_final_scores',
        'extracting_prior_works',
        'extracting_derivative_works',
        'building_layout',
        'completed',
        'partial',
        'failed',
      ];

      for (final s in statuses) {
        final parsed = GraphJobStatus.fromString(s);
        expect(parsed.value, s);
      }
    });
  });

  group('GraphSnapshot Partial Result with Warnings Tests', () {
    test('parses partial graph snapshot with warnings and completeness', () {
      final snapshotJson = {
        'graph_id': 'graph_123',
        'origin': {
          'id': 'doi:origin_1',
          'canonical_id': 'doi:origin_1',
          'title': 'Origin Paper',
          'year': 2020,
        },
        'status': 'partial',
        'nodes': [
          {
            'id': 'doi:origin_1',
            'canonical_id': 'doi:origin_1',
            'title': 'Origin Paper',
            'is_origin': true,
            'citation_count': 100,
            'radius': 24.0,
            'confidence': 'high',
          },
        ],
        'similarity_edges': [],
        'citation_edges': [],
        'data_completeness': {
          'metadata': 1.0,
          'references': 0.85,
          'citations': 0.40,
          'semantic': 0.90,
        },
        'warnings': [
          {
            'code': 'ncc_unavailable',
            'message': 'Citation enrichment partially unavailable.',
            'severity': 'warning',
          },
        ],
        'algorithm_version': 'v1.0',
        'created_at': '2026-09-10T20:00:00Z',
      };

      final snapshot = GraphSnapshot.fromJson(snapshotJson);
      expect(snapshot.status, GraphJobStatus.partial);
      expect(snapshot.warnings.length, 1);
      expect(snapshot.warnings.first.code, 'ncc_unavailable');
      expect(snapshot.dataCompleteness.citations, 0.40);
      expect(snapshot.nodes.first.isOrigin, isTrue);
      expect(snapshot.nodes.first.confidence, ConfidenceLevel.high);
    });
  });

  group('API Schemas Parsers Tests', () {
    test('parses search response', () {
      final res = SearchResponse.fromJson({
        'query': 'consensus',
        'total': 1,
        'items': [
          {
            'canonical_id': 'doi:10.1',
            'title': 'Raft Consensus',
            'authors': ['Diego Ongaro'],
            'year': 2014,
            'citation_count': 3500,
          },
        ],
        'disambiguation_needed': false,
        'candidates': [],
      });
      expect(res.total, 1);
      expect(res.items.first.title, 'Raft Consensus');
    });

    test('parses paper resolve response', () {
      final res = PaperResolveResponse.fromJson({
        'resolved': true,
        'paper': {
          'canonical_id': 'doi:10.1',
          'title': 'Raft Consensus',
          'normalized_title': 'raft consensus',
          'citation_count': 3500,
        },
        'confidence': 1.0,
      });
      expect(res.resolved, isTrue);
      expect(res.paper?.title, 'Raft Consensus');
    });
  });
}
