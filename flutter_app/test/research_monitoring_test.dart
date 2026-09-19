import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/services/research_update_graph_service.dart';
import 'package:paper_graph/core/utils/abstract_text_formatter.dart';
import 'package:paper_graph/cubits/research_monitoring/research_monitoring_state.dart';
import 'package:paper_graph/models/graph_job_status.dart';
import 'package:paper_graph/models/graph_models.dart';
import 'package:paper_graph/models/research_monitoring_models.dart';

void main() {
  group('Research monitoring models', () {
    test('parses monitored graph status and dates', () {
      final graph = MonitoredGraphSummary.fromJson({
        'id': 'monitor_1',
        'local_graph_id': 'graph_1',
        'graph_title': 'Seed graph',
        'status': 'paused',
        'frequency': 'weekly',
        'timezone': 'Asia/Riyadh',
        'last_checked_at': '2026-09-18T10:00:00Z',
        'next_check_at': '2026-09-25T10:00:00Z',
        'last_notified_at': null,
      });

      expect(graph.localGraphId, 'graph_1');
      expect(graph.isPaused, isTrue);
      expect(graph.frequency, 'weekly');
      expect(graph.nextCheckAt.toUtc().year, 2026);
    });

    test('parses update and preserves action state in copyWith', () {
      final update = ResearchUpdate.fromJson({
        'id': 'update_1',
        'monitored_graph_id': 'monitor_1',
        'canonical_paper_id': 'doi:10.1000/new',
        'doi': '10.1000/new',
        'title': 'A newly related paper',
        'abstract': 'Abstract',
        'published_at': '2026-09-10T00:00:00Z',
        'relevance_score': 0.84,
        'relation_type': 'semantic_similarity',
        'explanation': 'Similarity score: 0.84',
        'detected_at': '2026-09-18T10:00:00Z',
        'is_read': false,
        'is_added_to_graph': false,
      });

      final updated = update.copyWith(isRead: true, isAddedToGraph: true);

      expect(update.relevanceScore, 0.84);
      expect(update.relationType, 'semantic_similarity');
      expect(updated.isRead, isTrue);
      expect(updated.isAddedToGraph, isTrue);
      expect(updated.title, update.title);
    });

    test('state counts unread research updates', () {
      final first = ResearchUpdate(
        id: '1',
        monitoredGraphId: 'monitor_1',
        canonicalPaperId: 'doi:1',
        title: 'Unread',
        relevanceScore: 0.9,
        relationType: 'direct_citation',
        explanation: 'Cites a saved paper.',
        detectedAt: DateTime.utc(2026, 9, 18),
      );
      final second = first.copyWith(isRead: true);

      final state = ResearchMonitoringState(updates: [first, second]);

      expect(state.unreadCount, 1);
    });

    test(
      'adding an update creates one node and preserves the existing graph',
      () {
        final origin = const GraphNode(
          id: 'doi:10.1000/origin',
          canonicalId: 'doi:10.1000/origin',
          title: 'Origin paper',
          isOrigin: true,
          x: 0,
          y: 0,
        );
        final snapshot = GraphSnapshot(
          graphId: 'graph_1',
          origin: const GraphOrigin(
            id: 'doi:10.1000/origin',
            canonicalId: 'doi:10.1000/origin',
            title: 'Origin paper',
            doi: '10.1000/origin',
          ),
          status: GraphJobStatus.completed,
          nodes: [origin],
          createdAt: DateTime.utc(2026, 9, 18),
        );
        final update = ResearchUpdate(
          id: 'update_1',
          monitoredGraphId: 'monitor_1',
          canonicalPaperId: 'doi:10.1000/new',
          doi: '10.1000/new',
          title: 'New citation',
          relevanceScore: 0.95,
          relationType: 'direct_citation',
          explanation: 'Cites the origin.',
          detectedAt: DateTime.utc(2026, 9, 18),
        );

        final updated = ResearchUpdateGraphService.addToSnapshot(
          snapshot,
          update,
        );

        expect(updated.nodes, hasLength(2));
        expect(updated.nodes.last.canonicalId, 'doi:10.1000/new');
        expect(updated.nodes.first.x, 0);
        expect(updated.nodes.first.y, 0);
        expect(updated.citationEdges, hasLength(1));
        expect(updated.citationEdges.single.source, 'doi:10.1000/new');
      },
    );

    test('adding the same update twice does not duplicate the node', () {
      final snapshot = GraphSnapshot(
        graphId: 'graph_1',
        origin: const GraphOrigin(
          id: 'doi:10.1000/origin',
          canonicalId: 'doi:10.1000/origin',
          title: 'Origin paper',
        ),
        status: GraphJobStatus.completed,
        nodes: const [
          GraphNode(
            id: 'doi:10.1000/origin',
            canonicalId: 'doi:10.1000/origin',
            title: 'Origin paper',
            isOrigin: true,
          ),
        ],
        createdAt: DateTime.utc(2026, 9, 18),
      );
      final update = ResearchUpdate(
        id: 'update_1',
        monitoredGraphId: 'monitor_1',
        canonicalPaperId: 'doi:10.1000/new',
        title: 'New paper',
        relevanceScore: 0.84,
        relationType: 'semantic_similarity',
        explanation: 'Related.',
        detectedAt: DateTime.utc(2026, 9, 18),
      );

      final once = ResearchUpdateGraphService.addToSnapshot(snapshot, update);
      final twice = ResearchUpdateGraphService.addToSnapshot(once, update);

      expect(once.nodes, hasLength(2));
      expect(twice.nodes, hasLength(2));
      expect(twice.similarityEdges, hasLength(1));
    });

    test(
      'formats structured abstracts without breaking scientific notation',
      () {
        final sections = parseAbstractSections(
          'SUMMARY\n\nBACKGROUND\nThis study compared lung function.\n'
          'METHODS\nMeasurements included FEV\n1 and FVC.',
        );

        expect(sections.map((section) => section.heading), [
          'Background',
          'Methods',
        ]);
        expect(sections.last.body, contains('FEV₁'));
        expect(sections.last.body, isNot(contains('\n')));
        expect(
          abstractPreview(sections.last.body, maxCharacters: 10),
          endsWith('…'),
        );
      },
    );
  });
}
