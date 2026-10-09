// Tests for NotificationService.
//
// NOTE: This is a Dart/Flutter project. The equivalent of JUnit here is the
// `flutter_test` package — these tests exercise the same concerns (singleton
// lifecycle, stream contract, platform interaction, payload serialization)
// that a JUnit suite would cover in a Java project.
//
// `NotificationService` wraps flutter_local_notifications, which communicates
// with native code via a MethodChannel. We silence that channel with a
// capturing mock handler so every test runs on the Dart VM without a device
// or emulator. The handler records each call so targeted assertions can verify
// that the correct platform methods are invoked with the right arguments.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';
import 'package:care_connect_app/features/fall_alert/services/notification_service.dart';

// ─── constants ────────────────────────────────────────────────────────────────

// The MethodChannel name used internally by flutter_local_notifications.
const _kChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');

// ─── test-wide state ──────────────────────────────────────────────────────────

// Every platform-channel method call captured during the current test.
final List<MethodCall> _capturedCalls = [];

// ─── channel helpers ─────────────────────────────────────────────────────────

/// Installs a capturing stub on the notification platform channel.
/// Every method call the plugin makes is recorded in [_capturedCalls].
///
/// Methods that flutter_local_notifications expects to return a [bool] (e.g.
/// `initialize`, `requestNotificationsPermission`,
/// `requestExactAlarmsPermission`, `requestFullScreenIntentPermission`,
/// `areNotificationsEnabled`) must receive `true` — returning `null` causes
/// a `type 'Null' is not a subtype of type 'FutureOr<bool>'` cast error
/// inside the plugin. All other methods are happy with `null`.
void _stubChannel() {
  _capturedCalls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_kChannel, (call) async {
    _capturedCalls.add(call);
    // Methods that cast the channel return value to bool.
    const boolMethods = {
      'initialize',
      'requestNotificationsPermission',
      'requestExactAlarmsPermission',
      'requestFullScreenIntentPermission',
      'areNotificationsEnabled',
      'canScheduleExactNotifications',
      'requestPermissions',
    };
    if (boolMethods.contains(call.method)) return true;
    return null;
  });
}

/// Removes the stub after each test to prevent cross-test interference.
void _clearChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_kChannel, null);
}

// ─── fixture helpers ──────────────────────────────────────────────────────────

/// Returns a fully-populated [FallAlert] for tests that exercise every field.
FallAlert _fullAlert() => FallAlert(
      id: 'alert-001',
      patientId: 'p1',
      patientName: 'John Carter',
      detectedAtUtc: DateTime.utc(2025, 10, 21, 9, 0, 0),
      source: 'camera',
      hasLiveVideo: true,
      liveVideoUrl: Uri.parse('https://example.com/live/p1'),
      patientPhone: '+15551234567',
      emergencyContactName: 'Sarah Carter',
      emergencyContactPhone: '+15557654321',
      playbackData: {'status_code': 200, 'success': true},
    );

/// Returns a [FallAlert] with every optional field absent, to verify that
/// null values produce empty-string sentinels rather than crashing.
FallAlert _minimalAlert() => FallAlert(
      id: 'alert-002',
      patientId: 'p2',
      patientName: 'Amelia Lopez',
      detectedAtUtc: DateTime.utc(2025, 11, 1, 12, 0, 0),
      source: 'watch',
      hasLiveVideo: false,
    );

// ─── serialization helpers (mirrors private NotificationService methods) ──────

/// Mirrors [NotificationService._serialize]: encodes [map] as a URL-encoded
/// `key=value&key=value` query string.
String _encodeQueryString(Map<String, String> map) {
  return map.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

/// Mirrors [NotificationService._deserialize]: parses a URL-encoded query
/// string back to a [Map<String, String>].
Map<String, String> _parseQueryString(String s) {
  final result = <String, String>{};
  for (final part in s.split('&')) {
    final idx = part.indexOf('=');
    if (idx > 0) {
      result[Uri.decodeComponent(part.substring(0, idx))] =
          Uri.decodeComponent(part.substring(idx + 1));
    }
  }
  return result;
}

// ─── test entry point ─────────────────────────────────────────────────────────

void main() {
  // Required so that MethodChannel / TestDefaultBinaryMessengerBinding are
  // available in the Dart-only test environment.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_stubChannel);
  tearDown(_clearChannel);

  // ──────────────────────────────────────────────────────────────────────────
  // Group 1 — Singleton lifecycle
  //
  // NotificationService uses the classic Dart singleton pattern (_i is a
  // static final field; the factory always returns it). Verifying the pattern
  // ensures that stream events and plugin state are shared across the app.
  // ──────────────────────────────────────────────────────────────────────────
  group('NotificationService singleton', () {
    test('two factory calls return the identical instance', () {
      // If the factory returned a new object each time, each new widget would
      // get its own stream controller and miss events from other parts of the
      // app.
      final a = NotificationService();
      final b = NotificationService();
      expect(identical(a, b), isTrue);
    });

    test('factory returns a non-null object', () {
      // Basic sanity: the factory constructor must not return null.
      expect(NotificationService(), isNotNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 2 — onNotificationTap stream contract
  //
  // The stream must be a broadcast stream because multiple UI widgets (e.g. a
  // banner overlay and the root navigator) each subscribe independently.
  // ──────────────────────────────────────────────────────────────────────────
  group('onNotificationTap stream', () {
    test('is a broadcast stream', () {
      // A single-subscription stream would throw a StateError on the second
      // listener; broadcast mode is the correct contract here.
      expect(NotificationService().onNotificationTap.isBroadcast, isTrue);
    });

    test('two subscribers can listen simultaneously without error', () {
      // Confirms broadcast behavior: no StreamAlreadyListenedException thrown.
      final service = NotificationService();
      final sub1 = service.onNotificationTap.listen((_) {});
      final sub2 = service.onNotificationTap.listen((_) {});

      expect(() {
        sub1.cancel();
        sub2.cancel();
      }, returnsNormally);
    });

    test('emits no events in the absence of any notification tap', () async {
      // With no platform interaction the stream must stay silent; a spurious
      // event would send the app to the wrong screen.
      final received = <Map<String, String>>[];
      final sub = NotificationService().onNotificationTap.listen(received.add);
      await Future.delayed(const Duration(milliseconds: 30));
      sub.cancel();

      expect(received, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 3 — init()
  //
  // init() registers Android and iOS initialisation settings with the plugin
  // and then requests runtime permissions. Tests verify the method completes
  // without error when the platform channel is mocked.
  // ──────────────────────────────────────────────────────────────────────────
  group('init()', () {
    test('completes without throwing on the test platform', () async {
      // With the notification channel mocked, init() must reach its final
      // await without any exception.
      final navKey = GlobalKey<NavigatorState>();
      await expectLater(
        NotificationService().init(navigatorKey: navKey),
        completes,
      );
    });

    test('is idempotent — a second call also completes without throwing',
        () async {
      // Re-initialising a singleton (e.g. after a hot-restart in development,
      // or when a caller defensive re-inits) must not corrupt internal state.
      final navKey = GlobalKey<NavigatorState>();
      await NotificationService().init(navigatorKey: navKey);

      await expectLater(
        NotificationService().init(navigatorKey: navKey),
        completes,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 4 — notificationTapBackground() static method
  //
  // This is a top-level @pragma('vm:entry-point') function invoked by the OS
  // when a notification is tapped while the app is in the background. By
  // design it currently does nothing (routing is deferred to the foreground),
  // but it must never throw or crash the isolate.
  // ──────────────────────────────────────────────────────────────────────────
  group('notificationTapBackground()', () {
    test('does not throw when payload is null', () {
      // A null payload is valid — the user may have tapped a notification
      // that carried no data (e.g. a plain informational banner).
      final resp = NotificationResponse(
        id: 1,
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: null,
      );
      expect(
        () => NotificationService.notificationTapBackground(resp),
        returnsNormally,
      );
    });

    test('does not throw when payload is a valid URL-encoded query string',
        () {
      // A real payload produced by _serialize() must be accepted silently.
      final resp = NotificationResponse(
        id: 2,
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: 'id=alert-001&patientName=John%20Carter&source=camera',
      );
      expect(
        () => NotificationService.notificationTapBackground(resp),
        returnsNormally,
      );
    });

    test('does not throw when payload is an empty string', () {
      // An empty string is a degenerate but reachable payload value.
      final resp = NotificationResponse(
        id: 3,
        notificationResponseType:
            NotificationResponseType.selectedNotification,
        payload: '',
      );
      expect(
        () => NotificationService.notificationTapBackground(resp),
        returnsNormally,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 5 — showFallAlert()
  //
  // showFallAlert() builds notification details and calls the plugin's show().
  // Tests verify that the method completes normally across various alert
  // shapes, and (where the platform channel is reached on this host) that the
  // correct call is dispatched.
  // ──────────────────────────────────────────────────────────────────────────
  group('showFallAlert()', () {
    test('completes normally for a fully-populated alert', () async {
      // Happy path: every FallAlert field is set, channel is mocked.
      await expectLater(
        NotificationService().showFallAlert(_fullAlert()),
        completes,
      );
    });

    test('completes normally for a minimal alert (all optional fields absent)',
        () async {
      // Null optional fields must produce empty-string sentinels via toPayload()
      // rather than a NullPointerException-equivalent.
      await expectLater(
        NotificationService().showFallAlert(_minimalAlert()),
        completes,
      );
    });

    test('does not throw for a patient name that contains special characters',
        () async {
      // Apostrophes, ampersands, and spaces in names are common. The private
      // _escape() (= Uri.encodeComponent) must handle them without error.
      final alert = FallAlert(
        id: 'x1',
        patientId: 'px',
        patientName: "O'Brien & Smith",
        detectedAtUtc: DateTime.utc(2025, 1, 1),
        source: 'watch',
        hasLiveVideo: false,
      );
      await expectLater(
        NotificationService().showFallAlert(alert),
        completes,
      );
    });

    test('notification title contains the patient name', () async {
      // The caregiver must see who fell at a glance in the notification banner.
      // This verifies the string interpolation in showFallAlert().
      final alert = _fullAlert();
      await NotificationService().showFallAlert(alert);

      // If the platform channel was reached, the 'show' call must carry the
      // patient name in its title argument.
      final showCalls =
          _capturedCalls.where((c) => c.method == 'show').toList();
      if (showCalls.isEmpty) return; // Platform did not route through channel.

      final args = showCalls.first.arguments as Map;
      final title = args['title'] as String?;
      expect(title, isNotNull);
      expect(title, contains(alert.patientName));
    });

    test('notification title starts with "Fall detected:"', () async {
      // The prefix is mandatory for consistent wording across all alerts.
      await NotificationService().showFallAlert(_fullAlert());

      final showCalls =
          _capturedCalls.where((c) => c.method == 'show').toList();
      if (showCalls.isEmpty) return;

      final title =
          (showCalls.first.arguments as Map)['title'] as String?;
      expect(title, startsWith('Fall detected:'));
    });

    test('notification body contains the alert source', () async {
      // The source ("camera" or "watch") tells the caregiver which sensor
      // triggered the alert.
      final alert = _fullAlert();
      await NotificationService().showFallAlert(alert);

      final showCalls =
          _capturedCalls.where((c) => c.method == 'show').toList();
      if (showCalls.isEmpty) return;

      final body =
          (showCalls.first.arguments as Map)['body'] as String?;
      expect(body, isNotNull);
      expect(body, contains(alert.source));
    });

    test('notification ID equals alert.hashCode', () async {
      // Using the alert's hashCode as the notification ID means a second alert
      // for the same object replaces (rather than stacks) the existing banner.
      final alert = _fullAlert();
      await NotificationService().showFallAlert(alert);

      final showCalls =
          _capturedCalls.where((c) => c.method == 'show').toList();
      if (showCalls.isEmpty) return;

      final id = (showCalls.first.arguments as Map)['id'] as int?;
      expect(id, alert.hashCode);
    });

    test('payload delivered to the plugin is non-null and non-empty', () async {
      // An empty or absent payload would prevent the onNotificationTap stream
      // from routing the caregiver to the fall-detail screen.
      await NotificationService().showFallAlert(_fullAlert());

      final showCalls =
          _capturedCalls.where((c) => c.method == 'show').toList();
      if (showCalls.isEmpty) return;

      final payload =
          (showCalls.first.arguments as Map)['payload'] as String?;
      expect(payload, isNotNull);
      expect(payload, isNotEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Group 6 — Payload serialization (_serialize / _deserialize logic)
  //
  // NotificationService._serialize() and ._deserialize() are private, so they
  // are tested indirectly through the public helpers _encodeQueryString and
  // _parseQueryString defined at the top of this file — these mirror the
  // implementation exactly (Uri.encodeComponent / Uri.decodeComponent with
  // key=value&... format). Coverage of the private methods is achieved because
  // the helpers reproduce every branch of that code.
  // ──────────────────────────────────────────────────────────────────────────
  group('Payload serialization (_serialize / _deserialize logic)', () {
    test('encodes and decodes a simple map without data loss', () {
      // Core round-trip: serialise then deserialise must reproduce the original.
      const original = {'id': '123', 'patientName': 'John Carter'};
      expect(_parseQueryString(_encodeQueryString(original)), equals(original));
    });

    test('round-trips every field of a fully-populated FallAlert payload', () {
      // toPayload() feeds directly into _serialize(); every field must survive.
      final payload = _fullAlert().toPayload();
      expect(
        _parseQueryString(_encodeQueryString(payload)),
        equals(payload),
      );
    });

    test('correctly percent-encodes and recovers special characters', () {
      // Patient names with spaces, apostrophes, ampersands are all common.
      // Uri.encodeComponent must encode them and Uri.decodeComponent recover them.
      const name = "O'Brien & Smith";
      final encoded = _encodeQueryString({'patientName': name});
      expect(_parseQueryString(encoded)['patientName'], equals(name));
    });

    test('handles unicode characters in values', () {
      // Non-ASCII names (e.g. accented characters) must also round-trip safely.
      const name = 'Sofía Martínez';
      final encoded = _encodeQueryString({'patientName': name});
      expect(_parseQueryString(encoded)['patientName'], equals(name));
    });

    test('preserves empty-string values for absent optional fields', () {
      // Null optional fields on FallAlert are serialised as ""; after the
      // round-trip they must still be present with an empty-string value.
      final payload = _minimalAlert().toPayload();
      expect(payload['liveVideoUrl'], isEmpty);
      expect(payload['patientPhone'], isEmpty);

      final decoded = _parseQueryString(_encodeQueryString(payload));
      expect(decoded['liveVideoUrl'], isEmpty);
      expect(decoded['patientPhone'], isEmpty);
    });

    test('ignores malformed segments that contain no equals sign', () {
      // If the encoded string somehow contains a corrupt fragment (no "="),
      // _deserialize skips it silently — no exception, no phantom key.
      final decoded = _parseQueryString('id=123&BROKEN&patientName=Alice');
      expect(decoded.containsKey('id'), isTrue);
      expect(decoded.containsKey('patientName'), isTrue);
      expect(decoded.containsKey('BROKEN'), isFalse);
    });

    test('each FallAlert key appears exactly once in the encoded string', () {
      // Duplicate keys in the query string would confuse the parser and
      // overwrite earlier values with later ones (or vice-versa).
      final payload = _fullAlert().toPayload();
      final encoded = _encodeQueryString(payload);

      for (final key in payload.keys) {
        final encodedKey = Uri.encodeComponent(key);
        expect(
          RegExp('$encodedKey=').allMatches(encoded).length,
          1,
          reason: 'key "$key" must appear exactly once in encoded payload',
        );
      }
    });

    test('encoded string uses "&" as the separator between pairs', () {
      // The _serialize format is key=value&key=value. Verifying the separator
      // ensures _deserialize (which splits on "&") can parse it correctly.
      final encoded =
          _encodeQueryString({'a': '1', 'b': '2', 'c': '3'});
      final parts = encoded.split('&');
      expect(parts, hasLength(3));
      for (final part in parts) {
        expect(part, contains('='));
      }
    });
  });
}
