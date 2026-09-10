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
    return HiveService.settingsBox.get(_promptShownKey, defaultValue: false) as bool;
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
    return HiveService.settingsBox.get('$_graphNotifPrefix$graphId', defaultValue: false) as bool;
  }

  /// Sets notification preference for a specific graph job.
  static Future<void> setGraphNotificationEnabled(String graphId, bool enabled) async {
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

    // Clean up per-graph notification toggle
    if (Hive.isBoxOpen(HiveService.settingsBoxName)) {
      await HiveService.settingsBox.delete('$_graphNotifPrefix$graphId');
    }
  }
}
