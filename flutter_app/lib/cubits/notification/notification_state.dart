import 'package:flutter/foundation.dart';

enum NotificationType {
  info,
  success,
  warning,
  error;

  String get label => name.toUpperCase();
}

enum NotificationCategory { general, graphReady, researchUpdate }

@immutable
class InAppNotification {
  final String id;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime timestamp;
  final bool isRead;
  final String? relatedGraphId;
  final String? relatedPaperId;
  final NotificationCategory category;

  const InAppNotification({
    required this.id,
    required this.title,
    required this.message,
    this.type = NotificationType.info,
    required this.timestamp,
    this.isRead = false,
    this.relatedGraphId,
    this.relatedPaperId,
    this.category = NotificationCategory.general,
  });

  InAppNotification copyWith({
    String? id,
    String? title,
    String? message,
    NotificationType? type,
    DateTime? timestamp,
    bool? isRead,
    String? relatedGraphId,
    String? relatedPaperId,
    NotificationCategory? category,
  }) {
    return InAppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      message: message ?? this.message,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      relatedGraphId: relatedGraphId ?? this.relatedGraphId,
      relatedPaperId: relatedPaperId ?? this.relatedPaperId,
      category: category ?? this.category,
    );
  }
}

@immutable
class NotificationState {
  final List<InAppNotification> notifications;
  final InAppNotification? latestToast;

  const NotificationState({this.notifications = const [], this.latestToast});

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  NotificationState copyWith({
    List<InAppNotification>? notifications,
    InAppNotification? latestToast,
    bool clearToast = false,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      latestToast: clearToast ? null : (latestToast ?? this.latestToast),
    );
  }
}
