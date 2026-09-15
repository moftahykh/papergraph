import 'package:flutter_bloc/flutter_bloc.dart';
import 'notification_state.dart';

class NotificationCubit extends Cubit<NotificationState> {
  int _counter = 0;

  NotificationCubit() : super(const NotificationState());

  /// Posts a new in-app notification and optionally sets it as an active toast.
  void notify({
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    String? relatedGraphId,
    String? relatedPaperId,
    bool showToast = true,
  }) {
    _counter++;
    final notification = InAppNotification(
      id: 'notif_${DateTime.now().millisecondsSinceEpoch}_$_counter',
      title: title,
      message: message,
      type: type,
      timestamp: DateTime.now(),
      relatedGraphId: relatedGraphId,
      relatedPaperId: relatedPaperId,
    );

    final updated = [notification, ...state.notifications];
    emit(
      state.copyWith(
        notifications: updated,
        latestToast: showToast ? notification : state.latestToast,
      ),
    );
  }

  /// Specialized helper for graph synthesis completion.
  void notifyGraphReady(
    String graphId,
    int nodeCount, {
    bool isPartial = false,
  }) {
    notify(
      title: isPartial ? 'Graph Ready (Partial)' : 'Literature Graph Ready',
      message: isPartial
          ? 'Synthesized $nodeCount papers with partial source coverage.'
          : 'Synthesized $nodeCount papers and citation relationships.',
      type: isPartial ? NotificationType.warning : NotificationType.success,
      relatedGraphId: graphId,
      showToast: true,
    );
  }

  /// Specialized helper for graph generation errors.
  void notifyGraphFailed(String graphId, String error) {
    notify(
      title: 'Graph Generation Failed',
      message: error,
      type: NotificationType.error,
      relatedGraphId: graphId,
      showToast: true,
    );
  }

  /// Dismisses the currently displayed toast without removing it from history.
  void dismissToast() {
    emit(state.copyWith(clearToast: true));
  }

  /// Marks a specific notification as read.
  void markAsRead(String notificationId) {
    final updated = state.notifications.map((n) {
      if (n.id == notificationId) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();

    emit(state.copyWith(notifications: updated));
  }

  /// Clears all notifications and any active toast.
  void clearAll() {
    emit(const NotificationState());
  }
}
