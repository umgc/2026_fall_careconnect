// Tests for NotificationService tap callbacks
// (lib/features/fall_alert/services/notification_service.dart): simulates
// platform-originated notification events and checks the payload that is
// delivered on onNotificationTap.
//
// The plugin picks its platform implementation when first constructed, so
// this file runs with an iOS target platform to reach both the Darwin
// local-notification callback and the notification-response callback.

import 'dart:async';

import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';
import 'package:care_connect_app/features/fall_alert/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

Future<void> _fromPlatform(String method, Map<String, Object?> args) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channel.name,
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];
  late String shownPayload;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == 'show') {
        shownPayload = (call.arguments as Map)['payload'] as String;
      }
      if (call.method == 'initialize' || call.method == 'requestPermissions') {
        return true;
      }
      return null;
    });
    await NotificationService().init(navigatorKey: GlobalKey<NavigatorState>());
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('init requests Darwin permissions', () {
    expect(calls.map((c) => c.method), contains('initialize'));
    expect(calls.map((c) => c.method), contains('requestPermissions'));
  });

  test('notification response payload is decoded onto the tap stream',
      () async {
    final alert = FallAlert(
      id: 'a&1',
      patientId: 'p=2',
      patientName: 'Lee Tester',
      detectedAtUtc: DateTime.utc(2026, 1, 2, 3, 4, 5),
      source: 'watch',
      hasLiveVideo: false,
    );
    await NotificationService().showFallAlert(alert);

    final next = NotificationService().onNotificationTap.first;
    await _fromPlatform('didReceiveNotificationResponse', {
      'notificationId': 1,
      'actionId': null,
      'input': null,
      // A segment without '=' is ignored by the decoder.
      'payload': '$shownPayload&orphan',
      'notificationResponseType': 0,
    });
    final payload = await next.timeout(const Duration(seconds: 2));
    expect(payload['id'], 'a&1');
    expect(payload['patientId'], 'p=2');
    expect(payload['patientName'], 'Lee Tester');
    expect(payload.containsKey('orphan'), isFalse);
  });

  test('legacy local notification callback forwards its payload', () async {
    final next = NotificationService().onNotificationTap.first;
    await _fromPlatform('didReceiveLocalNotification', {
      'id': 2,
      'title': 't',
      'body': 'b',
      'payload': 'source=camera',
    });
    final payload = await next.timeout(const Duration(seconds: 2));
    expect(payload, {'source': 'camera'});
  });

  test('background tap handler accepts payloads and null payloads', () {
    expect(
      () => NotificationService.notificationTapBackground(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: 'id=1',
        ),
      ),
      returnsNormally,
    );
    expect(
      () => NotificationService.notificationTapBackground(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      ),
      returnsNormally,
    );
  });

  test('null payloads are ignored', () async {
    final events = <Map<String, String>>[];
    final sub = NotificationService().onNotificationTap.listen(events.add);
    await _fromPlatform('didReceiveNotificationResponse', {
      'notificationId': 3,
      'actionId': null,
      'input': null,
      'payload': null,
      'notificationResponseType': 0,
    });
    await _fromPlatform('didReceiveLocalNotification', {
      'id': 4,
      'title': null,
      'body': null,
      'payload': null,
    });
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(events, isEmpty);
  });
}
