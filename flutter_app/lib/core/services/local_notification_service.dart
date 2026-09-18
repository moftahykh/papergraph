import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../cubits/notification/notification_cubit.dart';
import 'hive_service.dart';
import 'permission_service.dart';

/// LocalNotificationService provides contextual notification management for PaperGraph.
///
/// CONTRACTUAL GUARANTEES & NON-NEGOTIABLE CONSTRAINTS:
/// 1. Notification permissions are NEVER requested on app launch or startup.
/// 2. Permissions are only requested contextually upon explicit user intent
///    (e.g., opting in via "Notify me when synthesis finishes").
/// 3. Notification dispatch operates during active polling or approved background
///    session observation. The system explicitly does NOT claim that notifications
///    reliably trigger if the app is force-closed by the user or OS process manager.
class LocalNotificationService {
  static const String _promptShownKey = 'contextual_notif_prompt_shown';
  static const String _graphNotifPrefix = 'notif_enabled_graph_';

  static const String channelId = 'paper_graph_channel';
  static const String channelName = 'PaperGraph Notifications';
  static const String channelDescription =
      'Literature synthesis and alerts for PaperGraph';
  static const String researchChannelId = 'paper_graph_research_channel';
  static const String researchChannelName = 'Research updates';
  static const String researchChannelDescription =
      'Relevant papers found for saved PaperGraph graphs';

  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  static void Function(String?)? _notificationTapHandler;

  static bool get _isAppInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Initializes the local notifications plugin for system tray notifications.
  static Future<void> init({
    FlutterLocalNotificationsPlugin? plugin,
    void Function(String?)? onNotificationTap,
  }) async {
    _notificationTapHandler = onNotificationTap ?? _notificationTapHandler;
    if (_isInitialized) return;
    try {
      final activePlugin = plugin ?? _notificationsPlugin;
      const androidSettings = AndroidInitializationSettings(
        '@drawable/ic_stat_papergraph',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await activePlugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          _notificationTapHandler?.call(response.payload);
        },
      );
      await activePlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              researchChannelId,
              researchChannelName,
              description: researchChannelDescription,
              importance: Importance.high,
            ),
          );
      _isInitialized = true;
    } catch (_) {
      // Safe fallback when running in mock, test, or headless environments
    }
  }

  /// Displays an OS-level notification in the status bar/notification center.
  static Future<void> showSystemNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        icon: '@drawable/ic_stat_papergraph',
        color: const Color(0xFF71717A),
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'PaperGraph update',
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (_) {
      // Ignore failures gracefully in test runner or restricted environments
    }
  }

  /// Renders a branded research notification with the full PaperGraph mark
  /// as a large icon. FCM's automatic renderer cannot provide this asset.
  static Future<void> showResearchUpdateNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        researchChannelId,
        researchChannelName,
        channelDescription: researchChannelDescription,
        icon: '@drawable/ic_stat_papergraph',
        largeIcon: DrawableResourceAndroidBitmap('ic_papergraph_large'),
        color: Color(0xFF71717A),
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'PaperGraph research update',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
        ),
      );
      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _notificationsPlugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: payload,
      );
    } catch (_) {
      // Ignore failures gracefully in background/test environments.
    }
  }

  /// Checks if notification permission is currently granted.
  static Future<bool> hasPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

  /// Contextually requests notification permission with user consent.
  static Future<bool> requestContextualPermission() async {
    await markContextualPromptShown();
    return await PermissionService.requestNotificationPermission();
  }

  /// Whether the contextual permission prompt has already been shown.
  static bool isContextualPromptShown() {
    if (!Hive.isBoxOpen(HiveService.settingsBoxName)) return false;
    return HiveService.settingsBox.get(_promptShownKey, defaultValue: false)
        as bool;
  }

  /// Records that the contextual prompt was presented.
  static Future<void> markContextualPromptShown() async {
    if (Hive.isBoxOpen(HiveService.settingsBoxName)) {
      await HiveService.settingsBox.put(_promptShownKey, true);
    }
  }

  /// Checks if notifications are specifically requested for a given graph job.
  static bool isGraphNotificationEnabled(String graphId) {
    if (!Hive.isBoxOpen(HiveService.settingsBoxName)) return false;
    return HiveService.settingsBox.get(
          '$_graphNotifPrefix$graphId',
          defaultValue: false,
        )
        as bool;
  }

  /// Sets notification preference for a specific graph job.
  static Future<void> setGraphNotificationEnabled(
    String graphId,
    bool enabled,
  ) async {
    if (Hive.isBoxOpen(HiveService.settingsBoxName)) {
      await HiveService.settingsBox.put('$_graphNotifPrefix$graphId', enabled);
    }
  }

  /// Dispatches completion notification when polling observes completion.
  static Future<void> onGraphCompleted({
    required String graphId,
    required int nodeCount,
    bool isPartial = false,
    required NotificationCubit notificationCubit,
  }) async {
    // 1. Always notify in-app notification center and show toast
    notificationCubit.notifyGraphReady(
      graphId,
      nodeCount,
      isPartial: isPartial,
    );

    // 2. Dispatch an OS notification only when this graph was explicitly
    // opted in and the operating-system permission is still granted.
    final wasEnabled = isGraphNotificationEnabled(graphId);
    bool permitted = false;
    try {
      permitted = await hasPermission();
    } catch (_) {}

    if (wasEnabled && permitted && !_isAppInForeground) {
      final title = isPartial
          ? 'Graph ready with limited results'
          : 'Graph ready';
      final body = isPartial
          ? '$nodeCount papers are ready. Some sources did not respond.'
          : '$nodeCount connected papers are ready to explore.';
      await showSystemNotification(
        id: graphId.hashCode.abs() % 100000,
        title: title,
        body: body,
        payload: graphId,
      );
    }

    // Clean up per-graph notification toggle
    if (Hive.isBoxOpen(HiveService.settingsBoxName)) {
      await HiveService.settingsBox.delete('$_graphNotifPrefix$graphId');
    }
  }

  /// Dispatches failure notification if graph synthesis fails.
  static Future<void> onGraphFailed({
    required String graphId,
    required String error,
    required NotificationCubit notificationCubit,
  }) async {
    notificationCubit.notifyGraphFailed(graphId, error);

    final wasEnabled = isGraphNotificationEnabled(graphId);
    bool permitted = false;
    try {
      permitted = await hasPermission();
    } catch (_) {}

    if (wasEnabled && permitted && !_isAppInForeground) {
      await showSystemNotification(
        id: graphId.hashCode.abs() % 100000,
        title: 'Couldn’t create graph',
        body: NotificationCubit.friendlyGraphError(error),
        payload: graphId,
      );
    }

    if (Hive.isBoxOpen(HiveService.settingsBoxName)) {
      await HiveService.settingsBox.delete('$_graphNotifPrefix$graphId');
    }
  }
}
