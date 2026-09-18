import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/cubits/research_monitoring/research_monitoring_state.dart';
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
  });
}