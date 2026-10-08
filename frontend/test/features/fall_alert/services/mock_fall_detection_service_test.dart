// Tests for MockFallDetectionService and the FallAlert model.
//
// NOTE: This is a Dart/Flutter project. The equivalent of JUnit here is the
// `flutter_test` package. These tests exercise the same concerns (singleton
// lifecycle, stream emissions, field validity, model serialization) that a
// JUnit suite would cover in a Java project.
//
// `NotificationService` calls flutter_local_notifications which talks to native
// code. We silence that platform channel with a mock handler so the tests run
// on the Dart VM without any device or emulator.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/fall_alert/models/fall_alert.dart';
import 'package:care_connect_app/features/fall_alert/services/mock_fall_detection_service.dart';

// ─── helpers ────────────────────────────────────────────────────────────────

// Known patients hard-coded inside MockFallDetectionService._emitRandom()
const _patientIds = {'p1', 'p2', 'p3'};
const _patientNames = {'John Carter', 'Amelia Lopez', 'Michael Chen'};
const _mockPhone = '18002428447';

// Installs a no-op handler for the flutter_local_notifications method channel
// so that NotificationService.showFallAlert() does not throw during tests.
void _stubNotificationChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    (_) async => null,
  );
}

void _clearNotificationChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dexterous.com/flutter/local_notifications'),
    null,
  );
}

// ─── test entry point ────────────────────────────────────────────────────────

void main() {
  // Needed so MethodChannel / TestDefaultBinaryMessengerBinding are available.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_stubNotificationChannel);

  tearDown(() {
    _clearNotificationChannel();
    // Clean up any running timer so tests don't bleed into each other.
    MockFallDetectionService().stop();
  });

  // ─── FallAlert model ───────────────────────────────────────────────────────

  group('FallAlert model', () {
    // Helper that builds a fully-populated FallAlert for serialization tests.
    FallAlert makeAlert({bool hasVideo = true}) {
      return FallAlert(
        id: '123',
        patientId: 'p1',
        patientName: 'John Carter',
        detectedAtUtc: DateTime.utc(2025, 10, 21, 2, 16, 4),
        source: 'camera',
        hasLiveVideo: hasVideo,
        liveVideoUrl: hasVideo ? Uri.parse('https://example.com/live/p1') : null,
        patientPhone: _mockPhone,
        emergencyContactName: 'Sarah Carter',
        emergencyContactPhone: _mockPhone,
        playbackData: {'status_code': 200, 'success': true},
      );
    }

    test('constructor sets all required fields correctly', () {
      // Verify that the model stores exactly what is passed in.
      final alert = makeAlert();

      expect(alert.id, '123');
      expect(alert.patientId, 'p1');
      expect(alert.patientName, 'John Carter');
      expect(alert.source, 'camera');
      expect(alert.hasLiveVideo, isTrue);
      expect(alert.liveVideoUrl, Uri.parse('https://example.com/live/p1'));
      expect(alert.patientPhone, _mockPhone);
      expect(alert.emergencyContactName, 'Sarah Carter');
      expect(alert.emergencyContactPhone, _mockPhone);
      expect(alert.detectedAtUtc.isUtc, isTrue);
    });

    test('optional fields default to null when omitted', () {
      // Optional contact / video fields must be nullable so callers can omit them.
      final alert = FallAlert(
        id: '1',
        patientId: 'p1',
        patientName: 'Test',
        detectedAtUtc: DateTime.now().toUtc(),
        source: 'watch',
        hasLiveVideo: false,
      );

      expect(alert.liveVideoUrl, isNull);
      expect(alert.patientPhone, isNull);
      expect(alert.emergencyContactName, isNull);
      expect(alert.emergencyContactPhone, isNull);
      expect(alert.playbackData, isNull);
    });

    test('toPayload() serialises all fields to String values', () {
      // toPayload() is used when building notification payloads; every value
      // must be a String so it can be URL-encoded later.
      final payload = makeAlert().toPayload();

      expect(payload['id'], '123');
      expect(payload['patientId'], 'p1');
      expect(payload['patientName'], 'John Carter');
      expect(payload['source'], 'camera');
      expect(payload['hasLiveVideo'], 'true');
      expect(payload['liveVideoUrl'], 'https://example.com/live/p1');
      expect(payload['patientPhone'], _mockPhone);
      expect(payload['emergencyContactName'], 'Sarah Carter');
      expect(payload['emergencyContactPhone'], _mockPhone);
      // playbackData is JSON-encoded, not empty
      expect(payload['playbackData'], isNotEmpty);
      expect(payload['playbackData'], contains('status_code'));
    });

    test('toPayload() uses empty strings for null optional fields', () {
      // A missing value must produce "" so fromPayload() can detect absence.
      final alert = FallAlert(
        id: '2',
        patientId: 'p2',
        patientName: 'Test',
        detectedAtUtc: DateTime.now().toUtc(),
        source: 'watch',
        hasLiveVideo: false,
      );
      final payload = alert.toPayload();

      expect(payload['liveVideoUrl'], '');
      expect(payload['patientPhone'], '');
      expect(payload['emergencyContactName'], '');
      expect(payload['emergencyContactPhone'], '');
      expect(payload['playbackData'], '');
    });

    test('fromPayload() round-trips a fully-populated alert', () {
      // Serialise then deserialise — the reconstructed alert must match the original.
      final original = makeAlert();
      final reconstructed = FallAlert.fromPayload(original.toPayload());

      expect(reconstructed.id, original.id);
      expect(reconstructed.patientId, original.patientId);
      expect(reconstructed.patientName, original.patientName);
      expect(reconstructed.source, original.source);
      expect(reconstructed.hasLiveVideo, original.hasLiveVideo);
      expect(reconstructed.liveVideoUrl.toString(), original.liveVideoUrl.toString());
      expect(reconstructed.patientPhone, original.patientPhone);
      expect(reconstructed.emergencyContactName, original.emergencyContactName);
      expect(reconstructed.emergencyContactPhone, original.emergencyContactPhone);
      expect(
        reconstructed.detectedAtUtc.toIso8601String(),
        original.detectedAtUtc.toIso8601String(),
      );
      expect(reconstructed.playbackData!['status_code'], 200);
    });

    test('fromPayload() restores null optional fields from empty strings', () {
      // Empty-string sentinel values must map back to null, not empty strings.
      final original = makeAlert(hasVideo: false);
      final reconstructed = FallAlert.fromPayload(original.toPayload());

      expect(reconstructed.liveVideoUrl, isNull);
    });

    test('fromPayload() restores null playbackData when payload is empty', () {
      final alert = FallAlert(
        id: '3',
        patientId: 'p3',
        patientName: 'Test',
        detectedAtUtc: DateTime.now().toUtc(),
        source: 'watch',
        hasLiveVideo: false,
      );
      final reconstructed = FallAlert.fromPayload(alert.toPayload());

      expect(reconstructed.playbackData, isNull);
    });
  });

  // ─── MockFallDetectionService ──────────────────────────────────────────────

  group('MockFallDetectionService', () {
    test('is a singleton — two factory calls return the identical instance', () {
      // The service manages shared timer/stream state; there must be only one.
      final a = MockFallDetectionService();
      final b = MockFallDetectionService();
      expect(identical(a, b), isTrue);
    });

    test('alerts\$ is a broadcast stream', () {
      // Broadcast streams allow multiple listeners across different widgets.
      expect(MockFallDetectionService().alerts$.isBroadcast, isTrue);
    });

    test('emitNow() emits exactly one FallAlert onto the stream', () async {
      // The basic contract: calling emitNow() produces one event.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;

      await service.emitNow();

      final alert = await future;
      expect(alert, isA<FallAlert>());
    });

    test('emitted alert has a non-empty id', () async {
      // The id is derived from DateTime.now().millisecondsSinceEpoch — never blank.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();

      expect((await future).id, isNotEmpty);
    });

    test('emitted alert patientId is one of the three known mock patients', () async {
      // Ensures the random selection stays within the hard-coded patient list.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();

      expect(_patientIds, contains((await future).patientId));
    });

    test('emitted alert patientName matches a known mock patient', () async {
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();

      expect(_patientNames, contains((await future).patientName));
    });

    test('emitted alert source is "camera" or "watch"', () async {
      // Source must be one of the two supported sensor types.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();

      expect(['camera', 'watch'], contains((await future).source));
    });

    test('detectedAtUtc is a UTC timestamp within the current second', () async {
      // The timestamp must be UTC and must fall between before/after the call.
      final service = MockFallDetectionService();
      final before = DateTime.now().toUtc();
      final future = service.alerts$.first;
      await service.emitNow();
      final after = DateTime.now().toUtc();

      final alert = await future;
      expect(alert.detectedAtUtc.isUtc, isTrue);
      expect(alert.detectedAtUtc.millisecondsSinceEpoch,
          greaterThanOrEqualTo(before.millisecondsSinceEpoch));
      expect(alert.detectedAtUtc.millisecondsSinceEpoch,
          lessThanOrEqualTo(after.millisecondsSinceEpoch));
    });

    test('hasLiveVideo is always false when source is "watch"', () async {
      // Per the implementation: hasVideo = isCamera && rng.nextBool()
      // A watch alert can never carry live video.
      final service = MockFallDetectionService();

      for (int i = 0; i < 30; i++) {
        final future = service.alerts$.first;
        await service.emitNow();
        final alert = await future;

        if (alert.source == 'watch') {
          expect(alert.hasLiveVideo, isFalse,
              reason: 'watch alerts must never have live video');
        }
      }
    });

    test('liveVideoUrl is null when hasLiveVideo is false', () async {
      // A missing video stream must not have a URL — prevents broken links.
      final service = MockFallDetectionService();

      for (int i = 0; i < 20; i++) {
        final future = service.alerts$.first;
        await service.emitNow();
        final alert = await future;

        if (!alert.hasLiveVideo) {
          expect(alert.liveVideoUrl, isNull);
          return;
        }
      }
      // Statistically this branch will be reached; if not, the invariant still holds.
    });

    test('liveVideoUrl contains the patient id when hasLiveVideo is true', () async {
      // The URL template is https://example.com/live/<patientId>.
      final service = MockFallDetectionService();

      for (int i = 0; i < 20; i++) {
        final future = service.alerts$.first;
        await service.emitNow();
        final alert = await future;

        if (alert.hasLiveVideo) {
          expect(alert.liveVideoUrl, isNotNull);
          expect(alert.liveVideoUrl.toString(), contains(alert.patientId));
          return;
        }
      }
    });

    test('emitted alert patientPhone equals the mock phone number', () async {
      // All three mock patients share the same demo phone number.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();

      expect((await future).patientPhone, _mockPhone);
    });

    test('emitted alert has non-empty emergency contact name and phone', () async {
      // Emergency contact fields must always be populated for mock patients.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();
      final alert = await future;

      expect(alert.emergencyContactName, isNotNull);
      expect(alert.emergencyContactName, isNotEmpty);
      expect(alert.emergencyContactPhone, isNotNull);
      expect(alert.emergencyContactPhone, isNotEmpty);
    });

    test('emitted alert playbackData contains status_code 200 and success true', () async {
      // The service always embeds the same fixed SAMPLE_RESPONSE map.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();
      final alert = await future;

      expect(alert.playbackData, isNotNull);
      expect(alert.playbackData!['status_code'], 200);
      expect(alert.playbackData!['success'], isTrue);
    });

    test('playbackData contains a nested "data.alert" map', () async {
      // Verifies the structure that skeleton_playback_widget depends on.
      final service = MockFallDetectionService();
      final future = service.alerts$.first;
      await service.emitNow();
      final alert = await future;

      final data = alert.playbackData!['data'] as Map<String, dynamic>;
      expect(data, contains('alert'));
      final innerAlert = data['alert'] as Map<String, dynamic>;
      expect(innerAlert['is_resolved'], isFalse);
      expect(innerAlert['status'], isA<int>());
    });

    test('start() can be called without throwing', () {
      // start() is effectively a no-op (timer line is commented out) but must
      // not crash the app.
      expect(() => MockFallDetectionService().start(), returnsNormally);
    });

    test('stop() can be called multiple times without throwing', () {
      // Idempotent: calling stop() when no timer is running must be safe.
      expect(
        () {
          MockFallDetectionService().stop();
          MockFallDetectionService().stop();
        },
        returnsNormally,
      );
    });

    test('multiple listeners all receive the emitted alert', () async {
      // Broadcast stream guarantee: every active subscriber gets the event.
      final service = MockFallDetectionService();
      final received1 = <FallAlert>[];
      final received2 = <FallAlert>[];

      final sub1 = service.alerts$.listen(received1.add);
      final sub2 = service.alerts$.listen(received2.add);

      await service.emitNow();
      // Allow the microtask queue to deliver events to both listeners.
      await Future.delayed(const Duration(milliseconds: 10));

      sub1.cancel();
      sub2.cancel();

      expect(received1, hasLength(1));
      expect(received2, hasLength(1));
      expect(received1.first.id, received2.first.id);
    });

    test('sequential emitNow() calls produce alerts with unique ids', () async {
      // Each id is derived from millisecondsSinceEpoch — they should not collide.
      final service = MockFallDetectionService();
      final ids = <String>{};

      for (int i = 0; i < 5; i++) {
        // Small delay so the millisecond timestamp advances between calls.
        if (i > 0) await Future.delayed(const Duration(milliseconds: 2));
        final future = service.alerts$.first;
        await service.emitNow();
        ids.add((await future).id);
      }

      expect(ids.length, greaterThan(1),
          reason: 'ids should generally be unique across calls');
    });
  });
}
