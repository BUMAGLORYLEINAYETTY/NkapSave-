import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

/// Background-isolate handler. Must be a top-level function.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  // Background pushes are surfaced by the OS automatically; nothing to do.
}

/// Firebase Cloud Messaging integration.
///
/// `init()` is safe to call before the user is logged in. The token is only
/// pushed to the backend in `syncTokenWithBackend()`, which the auth flow
/// should call after login. On logout, call `unregisterFromBackend()` to
/// disable the token server-side.
class FcmService {
  static final FcmService instance = FcmService._();
  FcmService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  String? _token;

  String? get token => _token;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Firebase not configured (no google-services.json / GoogleService-Info.plist
      // / firebase_options.dart). Push won't work but the app continues.
      debugPrint('[FCM] Firebase init skipped: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[FCM] Permission denied by user');
    }

    await _initLocalNotifications();
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    _token = await messaging.getToken();
    messaging.onTokenRefresh.listen(_onTokenRefresh);
    _initialized = true;
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
  }

  void _onForegroundMessage(RemoteMessage message) {
    final notif = message.notification;
    if (notif == null) return;
    _local.show(
      message.hashCode,
      notif.title,
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nkapsave_default',
          'NkapSave',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data['deep_link'] as String?,
    );
  }

  Future<void> _onTokenRefresh(String newToken) async {
    final old = _token;
    _token = newToken;
    if (ApiService.isLoggedIn) {
      try {
        await syncTokenWithBackend();
        if (old != null) {
          await ApiService.unregisterPushToken(old);
        }
      } catch (e) {
        debugPrint('[FCM] Token refresh sync failed: $e');
      }
    }
  }

  /// Push the current FCM token to the backend. Call after a successful login.
  Future<void> syncTokenWithBackend() async {
    if (!_initialized || _token == null) return;
    final platform = kIsWeb
        ? 'web'
        : (Platform.isIOS ? 'ios' : 'android');
    await ApiService.registerPushToken(token: _token!, platform: platform);
  }

  /// Disable the current device token server-side. Call before logout.
  Future<void> unregisterFromBackend() async {
    if (_token == null) return;
    try {
      await ApiService.unregisterPushToken(_token!);
    } catch (e) {
      debugPrint('[FCM] unregister failed: $e');
    }
  }
}
