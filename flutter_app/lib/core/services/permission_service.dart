import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestStoragePermission() async {
    // Check storage or photos depending on Android platform version
    PermissionStatus status = await Permission.storage.status;
    if (status.isDenied) {
      status = await Permission.storage.request();
    }
    return status.isGranted || status.isLimited;
  }

  static Future<bool> requestNotificationPermission() async {
    PermissionStatus status = await Permission.notification.status;
    if (status.isDenied) {
      status = await Permission.notification.request();
    }
    return status.isGranted;
  }

  static Future<Map<String, bool>> checkAllPermissions() async {
    final storageStatus = await Permission.storage.status;
    final notificationStatus = await Permission.notification.status;

    return {
      'Storage': storageStatus.isGranted || storageStatus.isLimited,
      'Notifications': notificationStatus.isGranted,
    };
  }
}
