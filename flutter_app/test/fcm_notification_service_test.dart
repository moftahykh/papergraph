import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/core/services/fcm_notification_service.dart';

void main() {
  group('ResearchPushPayload', () {
    test('parses the backend research update contract', () {
      final payload = ResearchPushPayload.fromData({
        'type': 'research_updates',
        'local_graph_id': 'graph_local_1',
        'graph_title': 'Seed graph',
        'update_count': '3',
      });

      expect(payload.isResearchUpdate, isTrue);
      expect(payload.localGraphId, 'graph_local_1');
      expect(payload.graphTitle, 'Seed graph');
      expect(payload.updateCount, 3);
    });

    test('accepts graph_id for backward-compatible payloads', () {
      final payload = ResearchPushPayload.fromData({
        'type': 'research_updates',
        'graph_id': 'graph_local_2',
      });

      expect(payload.isResearchUpdate, isTrue);
      expect(payload.localGraphId, 'graph_local_2');
      expect(payload.updateCount, 1);
    });

    test('ignores unrelated push messages', () {
      final payload = ResearchPushPayload.fromData({
        'type': 'graph_ready',
        'graph_id': 'job_1',
      });

      expect(payload.isResearchUpdate, isFalse);
    });
  });
}