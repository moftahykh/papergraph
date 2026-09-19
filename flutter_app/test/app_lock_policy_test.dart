import 'package:flutter_test/flutter_test.dart';
import 'package:paper_graph/views/widgets/app_lock_gate.dart';

void main() {
  group('AppLockPolicy', () {
    final backgroundedAt = DateTime(2026, 1, 1, 12);

    test('does not lock after a quick return', () {
      expect(
        AppLockPolicy.shouldLockAfter(
          backgroundedAt: backgroundedAt,
          resumedAt: backgroundedAt.add(const Duration(seconds: 10)),
        ),
        isFalse,
      );
    });

    test('locks at the configured timeout', () {
      expect(
        AppLockPolicy.shouldLockAfter(
          backgroundedAt: backgroundedAt,
          resumedAt: backgroundedAt.add(AppLockPolicy.backgroundTimeout),
        ),
        isTrue,
      );
    });

    test('locks after a long background session', () {
      expect(
        AppLockPolicy.shouldLockAfter(
          backgroundedAt: backgroundedAt,
          resumedAt: backgroundedAt.add(const Duration(minutes: 6)),
        ),
        isTrue,
      );
    });

    test('does not lock before the five-minute timeout', () {
      expect(
        AppLockPolicy.shouldLockAfter(
          backgroundedAt: backgroundedAt,
          resumedAt: backgroundedAt.add(
            const Duration(minutes: 4, seconds: 59),
          ),
        ),
        isFalse,
      );
    });
  });
}
