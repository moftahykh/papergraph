import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';

import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../firebase_options.dart';
import '../../views/research_monitoring/graph_updates_view.dart';
import '../network/api_client.dart';
import 'hive_service.dart';
import 'local_notification_service.dart';

/// Data carried by a research-monitoring push message.
@immutable
class ResearchPushPayload {
  final String? localGraphId;
  final String? graphTitle;
  final int updateCount;
  final String? type;

  const ResearchPushPayload({
    required this.localGraphId,
    required this.graphTitle,
    required this.updateCount,
    required this.type,
  });

  bool get isResearchUpdate =>
      type == 'research_updates' &&
      localGraphId != null &&
      localGraphId!.trim().isNotEmpty;

  factory ResearchPushPayload.fromData(Map<String, dynamic> data) {
    final rawCount = data['update_count'];
    final parsedCount = rawCount is int
        ? rawCount
        : int.tryParse(rawCount?.toString() ?? '');
    final graphId =
        data['local_graph_id']?.toString() ?? data['graph_id']?.toString();

    return ResearchPushPayload(
      localGraphId: graphId,
      graphTitle: data['graph_title']?.toString(),
      updateCount: parsedCount == null || parsedCount < 1 ? 1 : parsedCount,
      type: data['type']?.toString(),
    );
  }

  factory ResearchPushPayload.fromMessage(RemoteMessage message) {
    return ResearchPushPayload.fromData(message.data);
  }
}

/// FCM integration for authenticated research-monitoring notifications.
///
/// This service deliberately does not ask for permission during app startup.
/// The Settings toggle calls [enable] after the user explicitly opts in.
class FcmNotificationService {
  FcmNotificationService._();

  static const _enabledKey = 'research_push_notifications_enabled';
  static final PaperGraphApiClient _api = PaperGraphApiClient();
  static GlobalKey<NavigatorState>? _navigatorKey;
  static StreamSubscription<RemoteMessage>? _foregroundSub;
  static StreamSubscription<RemoteMessage>? _openedSub;
  static StreamSubscription<String>? _tokenSub;
  static bool _initialized = false;
  static bool _appShellReady = false;
  static ResearchPushPayload? _pendingTapPayload;

  static bool get isEnabled {
    if (!Hive.isBoxOpen(HiveService.settingsBoxName)) return false;
    return HiveService.settingsBox.get(_enabledKey, defaultValue: false)
        as bool;
  }

  static Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized || Firebase.apps.isEmpty) return;
    _initialized = true;
    _navigatorKey = navigatorKey;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      if (isEnabled) _registerToken(token);
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleTap(initialMessage);
    }

    await syncRegistration();
  }

  static Future<bool> enable() async {
    if (Firebase.apps.isEmpty) return false;

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) return false;

    await _setEnabled(true);
    await syncRegistration();
    return true;
  }

  static Future<void> disable() async {
    final token = await _safeGetToken();
    if (token != null) {
      await _deactivateToken(token);
    }
    await _setEnabled(false);
  }

  /// Called before Firebase sign-out so the protected DELETE still has auth.
  static Future<void> unregisterCurrentToken() async {
    final token = await _safeGetToken();
    if (token != null) await _deactivateToken(token);
  }

  static Future<void> syncRegistration() async {
    if (!isEnabled || Firebase.apps.isEmpty) return;
    final user = firebase_auth.FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) return;

    final token = await _safeGetToken();
    if (token != null) await _registerToken(token);
  }

  static Future<void> _registerToken(String token) async {
    try {
      await _api.registerDeviceToken(fcmToken: token, platform: _platform);
    } catch (_) {
      // Registration is retried by token refresh or the next explicit sync.
    }
  }

  static Future<void> _deactivateToken(String token) async {
    try {
      await _api.removeDeviceToken(fcmToken: token, platform: _platform);
    } catch (_) {
      // A failed cleanup must not block sign-out or opt-out.
    }
  }

  static Future<String?> _safeGetToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _setEnabled(bool value) async {
    if (Hive.isBoxOpen(HiveService.settingsBoxName)) {
      await HiveService.settingsBox.put(_enabledKey, value);
    }
  }

  static String get _platform {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return 'ios';
      default:
        return 'android';
    }
  }

  static void _handleForeground(RemoteMessage message) {
    if (message.data['type'] == 'fcm_test') {
      final context = _navigatorKey?.currentContext;
      context?.read<NotificationCubit>().notify(
        title:
            message.data['title']?.toString() ?? 'PaperGraph test notification',
        message:
            message.data['body']?.toString() ?? 'FCM delivery is connected.',
        type: NotificationType.success,
        showToast: true,
      );
      return;
    }

    final payload = ResearchPushPayload.fromMessage(message);
    if (!payload.isResearchUpdate) return;

    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    context.read<NotificationCubit>().notifyResearchUpdate(
      localGraphId: payload.localGraphId!,
      updateCount: payload.updateCount,
      graphTitle: payload.graphTitle,
    );
  }

  static void _handleTap(RemoteMessage message) {
    _handleTapData(message.data);
  }

  static void _handleTapData(Map<String, dynamic> data) {
    final payload = ResearchPushPayload.fromData(data);
    if (!payload.isResearchUpdate) return;
    if (!_appShellReady) {
      _pendingTapPayload = payload;
      return;
    }
    _openUpdatesWhenReady(payload);
  }

  /// Called by the authenticated main shell after SplashView has been
  /// replaced. Cold-start notification taps must wait for this point or the
  /// splash route will replace GraphUpdatesView a few seconds later.
  static void markAppShellReady() {
    _appShellReady = true;
    final pending = _pendingTapPayload;
    _pendingTapPayload = null;
    if (pending != null) {
      _openUpdatesWhenReady(pending);
    }
  }

  /// Handles taps from the local notification renderer after a data-only FCM
  /// message has been displayed in the background.
  static void handleLocalNotificationTap(String? rawPayload) {
    if (rawPayload == null || rawPayload.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        _handleTapData(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Ignore non-research local notification payloads.
    }
  }

  static void _openUpdatesWhenReady(ResearchPushPayload payload) {
    var attempts = 0;
    Timer.periodic(const Duration(milliseconds: 250), (timer) {
      attempts++;
      final navigator = _navigatorKey?.currentState;
      final user = firebase_auth.FirebaseAuth.instance.currentUser;
      if (navigator != null && user != null) {
        timer.cancel();
        navigator.push(
          MaterialPageRoute(
            builder: (_) => GraphUpdatesView(
              localGraphId: payload.localGraphId!,
              graphTitle: payload.graphTitle ?? 'Saved graph',
            ),
          ),
        );
      } else if (attempts >= 40) {
        timer.cancel();
      }
    });
  }

  static Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _openedSub?.cancel();
    await _tokenSub?.cancel();
    _foregroundSub = null;
    _openedSub = null;
    _tokenSub = null;
    _initialized = false;
    _appShellReady = false;
    _pendingTapPayload = null;
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await LocalNotificationService.init();

  final data = message.data;
  final type = data['type']?.toString();
  if (type != 'research_updates' && type != 'fcm_test') return;

  final title =
      data['title']?.toString() ??
      (type == 'fcm_test'
          ? 'PaperGraph test notification'
          : 'New research update');
  final body =
      data['body']?.toString() ??
      (type == 'fcm_test'
          ? 'FCM delivery is connected.'
          : 'Open PaperGraph to review the latest updates.');
  await LocalNotificationService.showResearchUpdateNotification(
    id:
        (data['local_graph_id'] ?? data['test_id'] ?? type)
            .toString()
            .hashCode
            .abs() %
        100000,
    title: title,
    body: body,
    payload: jsonEncode(data),
  );
}
