import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/fall_alert.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService _i = NotificationService._();
  factory NotificationService() => _i;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final _tapStream = StreamController<Map<String, String>>.broadcast();

  Stream<Map<String, String>> get onNotificationTap => _tapStream.stream;

  Future<void> init({required GlobalKey<NavigatorState> navigatorKey}) async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        if (payload != null) _tapStream.add(_deserialize(payload));
      },
    );

    final InitializationSettings initSettings = InitializationSettings(
        android: androidInit, iOS: iosInit, macOS: null, linux: null);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null) {
          _tapStream.add(_deserialize(payload));
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    await _requestPermissions();
  }

  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse resp) {
    final payload = resp.payload;
    if (payload != null) {
      // No navigator here. App will deliver this when foreground is ready.
      // You can persist this if you want to handle cold start routes.
    }
  }

  Future<void> showFallAlert(FallAlert alert) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'falls',
      'Fall Alerts',
      channelDescription: 'Notifications for detected patient falls',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      interruptionLevel: InterruptionLevel.critical,
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    final title = 'Fall detected: ${alert.patientName}';
    final body = 'Source: ${alert.source}  •  Tap to view details';

    await _plugin.show(
      alert.hashCode,
      title,
      body,
      details,
      payload: _serialize(alert.toPayload()),
    );
  }

  Future<void> _requestPermissions() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestExactAlarmsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
            alert: true, badge: true, sound: true, critical: true);
  }

  String _serialize(Map<String, String> map) {
    return map.entries
        .map((e) => '${_escape(e.key)}=${_escape(e.value)}')
        .join('&');
  }

  Map<String, String> _deserialize(String s) {
    final out = <String, String>{};
    for (final part in s.split('&')) {
      final idx = part.indexOf('=');
      if (idx > 0) {
        final k = _unescape(part.substring(0, idx));
        final v = _unescape(part.substring(idx + 1));
        out[k] = v;
      }
    }
    return out;
  }

  String _escape(String v) => Uri.encodeComponent(v);
  String _unescape(String v) => Uri.decodeComponent(v);
}
