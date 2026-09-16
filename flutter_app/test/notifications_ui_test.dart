import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:paper_graph/core/services/local_notification_service.dart';
import 'package:paper_graph/cubits/notification/notification_cubit.dart';
import 'package:paper_graph/cubits/notification/notification_state.dart';
import 'package:paper_graph/views/widgets/notification_toast_overlay.dart';
import 'package:paper_graph/views/widgets/notifications_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationToastOverlay Widget Tests', () {
    late NotificationCubit notifCubit;

    setUp(() {
      notifCubit = NotificationCubit();
    });

    tearDown(() {
      notifCubit.close();
    });

    testWidgets(
      'renders child and displays animated toast on notification dispatch',
      (tester) async {
        await tester.pumpWidget(
          BlocProvider<NotificationCubit>.value(
            value: notifCubit,
            child: const MaterialApp(
              home: NotificationToastOverlay(
                child: Scaffold(body: Text('Main Screen Content')),
              ),
            ),
          ),
        );

        expect(find.text('Main Screen Content'), findsOneWidget);
        expect(find.text('Graph Ready'), findsNothing);

        // Trigger notification
        notifCubit.notify(
          title: 'Graph Ready',
          message: 'Synthesized 24 papers successfully.',
          type: NotificationType.success,
        );

        // Pump animation
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(find.text('Graph Ready'), findsOneWidget);
        expect(
          find.text('Synthesized 24 papers successfully.'),
          findsOneWidget,
        );

        // Tap close button on toast
        final closeIcon = find.byIcon(Icons.close_rounded);
        expect(closeIcon, findsOneWidget);
        await tester.tap(closeIcon);
        await tester.pumpAndSettle();

        expect(find.text('Graph Ready'), findsNothing);
      },
    );
  });

  group('NotificationsSheet Tests', () {
    late NotificationCubit notifCubit;

    setUp(() {
      notifCubit = NotificationCubit();
    });

    tearDown(() {
      notifCubit.close();
    });

    testWidgets('shows empty state when no notifications', (tester) async {
      await tester.pumpWidget(
        BlocProvider<NotificationCubit>.value(
          value: notifCubit,
          child: const MaterialApp(home: Scaffold(body: NotificationsSheet())),
        ),
      );

      expect(find.text('All caught up!'), findsOneWidget);
    });

    testWidgets('displays notifications and allows mark read and clear', (
      tester,
    ) async {
      notifCubit.notify(
        title: 'Graph ready',
        message: 'Synthesized 10 papers.',
        type: NotificationType.success,
      );

      await tester.pumpWidget(
        BlocProvider<NotificationCubit>.value(
          value: notifCubit,
          child: const MaterialApp(home: Scaffold(body: NotificationsSheet())),
        ),
      );

      expect(find.text('Graph ready'), findsOneWidget);
      expect(find.text('Synthesized 10 papers.'), findsOneWidget);

      // Tap Clear All
      final clearAllButton = find.byTooltip('Clear all');
      expect(clearAllButton, findsOneWidget);
      await tester.tap(clearAllButton);
      await tester.pumpAndSettle();

      expect(find.text('All caught up!'), findsOneWidget);
    });
  });

  group('LocalNotificationService Tests', () {
    test('init runs safely in test environment', () async {
      await LocalNotificationService.init();
    });

    test('onGraphFailed notifies cubit', () async {
      final cubit = NotificationCubit();
      await LocalNotificationService.onGraphFailed(
        graphId: 'test-err-graph',
        error: 'Network timeout',
        notificationCubit: cubit,
      );

      expect(cubit.state.notifications.isNotEmpty, isTrue);
      expect(
        cubit.state.notifications.first.type,
        equals(NotificationType.error),
      );
      expect(
        cubit.state.notifications.first.title,
        equals('Couldn’t create graph'),
      );
      expect(
        cubit.state.notifications.first.message,
        equals('Check your internet connection, then try again.'),
      );
      cubit.close();
    });
  });
}
