// Tests for TelemetryGuardrails
// (lib/features/telemetry/telemetry_guardrails.dart).
//
// TelemetryGuardrails.sanitize is a pure static method:
//   - Returns null if eventName is not in the allowedEvents whitelist.
//   - Removes keys found in blockedKeys (case-insensitive).
//   - Removes null values.
//   - Removes non-primitive values (e.g., Lists, Maps).
//   - Removes String values longer than 64 characters.
//   - Returns an empty map (not null) for a whitelisted event with no
//     passing properties.
// No platform channels or network I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/telemetry/telemetry_guardrails.dart';

void main() {
  group('TelemetryGuardrails.sanitize', () {
    test('returns null for non-whitelisted event names', () {
      // An event not in allowedEvents must be dropped entirely.
      final result = TelemetryGuardrails.sanitize(
        'track_user_location',
        {'lat': 40.7128, 'lon': -74.0060},
      );
      expect(result, isNull);
    });

    test('returns a map for whitelisted event names', () {
      // A whitelisted event with safe props must return a non-null map.
      final result = TelemetryGuardrails.sanitize(
        'screen_view',
        {'screen': 'Dashboard', 'duration': 5},
      );
      expect(result, isNotNull);
    });

    test('passes through safe string, num, and bool values', () {
      // Safe primitives should be present in the output.
      final result = TelemetryGuardrails.sanitize(
        'button_tap',
        {'buttonId': 'submit', 'count': 3, 'isEnabled': true},
      );
      expect(result!['buttonId'], 'submit');
      expect(result['count'], 3);
      expect(result['isEnabled'], true);
    });

    test('removes blocked keys (case-insensitive)', () {
      // Keys matching blockedKeys (lowercased) must be removed.
      final result = TelemetryGuardrails.sanitize(
        'screen_view',
        {
          'name': 'Alice',           // blocked
          'Email': 'alice@test.com', // blocked (case-insensitive)
          'screen': 'Home',          // allowed
          'patientId': 99,           // blocked
        },
      );
      expect(result, isNotNull);
      expect(result!.containsKey('name'), isFalse);
      expect(result.containsKey('Email'), isFalse);
      expect(result.containsKey('patientId'), isFalse);
      expect(result['screen'], 'Home');
    });

    test('removes null values', () {
      // Null property values must be excluded from output.
      final result = TelemetryGuardrails.sanitize(
        'button_tap',
        {'buttonId': 'ok', 'extra': null},
      );
      expect(result!.containsKey('extra'), isFalse);
      expect(result['buttonId'], 'ok');
    });

    test('removes non-primitive values (List, Map)', () {
      // Non-primitive types (List, Map) must be excluded.
      final result = TelemetryGuardrails.sanitize(
        'screen_view',
        {
          'screen': 'Home',
          'tags': ['a', 'b'],
          'meta': {'key': 'value'},
        },
      );
      expect(result!.containsKey('tags'), isFalse);
      expect(result.containsKey('meta'), isFalse);
      expect(result['screen'], 'Home');
    });

    test('removes string values longer than 64 characters', () {
      // A string with more than 64 characters must be dropped.
      final longString = 'A' * 65;
      final result = TelemetryGuardrails.sanitize(
        'button_tap',
        {'buttonId': 'ok', 'longProp': longString},
      );
      expect(result!.containsKey('longProp'), isFalse);
      expect(result['buttonId'], 'ok');
    });

    test('keeps string values exactly 64 characters long', () {
      // A string at exactly 64 characters must be kept.
      final exactString = 'B' * 64;
      final result = TelemetryGuardrails.sanitize(
        'button_tap',
        {'longProp': exactString},
      );
      expect(result!['longProp'], exactString);
    });

    test('returns empty map (not null) when all properties are filtered', () {
      // If all properties are blocked/invalid, the event is kept but the
      // props map is empty (the event itself was whitelisted).
      final result = TelemetryGuardrails.sanitize(
        'error_network',
        {'name': 'Alice', 'email': 'alice@test.com'},
      );
      expect(result, isNotNull);
      expect(result, isEmpty);
    });

    test('allowedEvents contains expected event types', () {
      // Verifies the whitelist includes core event names.
      expect(TelemetryGuardrails.allowedEvents, contains('screen_view'));
      expect(TelemetryGuardrails.allowedEvents, contains('button_tap'));
      expect(TelemetryGuardrails.allowedEvents, contains('error_network'));
      expect(TelemetryGuardrails.allowedEvents, contains('error_timeout'));
      expect(TelemetryGuardrails.allowedEvents, contains('offline_toggled'));
      expect(TelemetryGuardrails.allowedEvents, contains('feature_use'));
      expect(TelemetryGuardrails.allowedEvents, contains('sync_started'));
      expect(TelemetryGuardrails.allowedEvents, contains('sync_completed'));
      expect(TelemetryGuardrails.allowedEvents, contains('sync_failed'));
      expect(TelemetryGuardrails.allowedEvents, contains('session_start'));
      expect(TelemetryGuardrails.allowedEvents, contains('session_end'));
    });

    test('blockedKeys contains PII/PHI fields', () {
      // Verifies the blocklist contains expected sensitive keys.
      expect(TelemetryGuardrails.blockedKeys, contains('email'));
      expect(TelemetryGuardrails.blockedKeys, contains('ssn'));
      expect(TelemetryGuardrails.blockedKeys, contains('dob'));
      expect(TelemetryGuardrails.blockedKeys, contains('symptom'));
    });

    test('feature medication events are whitelisted', () {
      // Verifies that feature.medications.* events pass through.
      final result = TelemetryGuardrails.sanitize(
        'feature.medications.add',
        {'count': 1},
      );
      expect(result, isNotNull);
      expect(result!['count'], 1);
    });

    test('feature_use keeps anonymous feature key', () {
      final result = TelemetryGuardrails.sanitize(
        'feature_use',
        {'feature': 'medications_tracker'},
      );
      expect(result, isNotNull);
      expect(result!['feature'], 'medications_tracker');
    });

    test('sync_started keeps scope and pendingCount', () {
      final result = TelemetryGuardrails.sanitize(
        'sync_started',
        {'scope': 'batch', 'pendingCount': 3},
      );
      expect(result, isNotNull);
      expect(result!['scope'], 'batch');
      expect(result['pendingCount'], 3);
    });

    test('sync_completed keeps batch counters', () {
      final result = TelemetryGuardrails.sanitize(
        'sync_completed',
        {
          'scope': 'batch',
          'attempted': 2,
          'succeeded': 1,
          'failed': 1,
        },
      );
      expect(result, isNotNull);
      expect(result!['attempted'], 2);
      expect(result['succeeded'], 1);
      expect(result['failed'], 1);
    });

    test('sync_failed keeps scope and failed count', () {
      final result = TelemetryGuardrails.sanitize(
        'sync_failed',
        {'scope': 'single', 'attempted': 1, 'failed': 1},
      );
      expect(result, isNotNull);
      expect(result!['scope'], 'single');
      expect(result['failed'], 1);
    });

    test('session lifecycle events keep coarse reason fields', () {
      final start = TelemetryGuardrails.sanitize(
        'session_start',
        {'source': 'cold_start'},
      );
      final end = TelemetryGuardrails.sanitize(
        'session_end',
        {'reason': 'detached'},
      );

      expect(start, isNotNull);
      expect(start!['source'], 'cold_start');
      expect(end, isNotNull);
      expect(end!['reason'], 'detached');
    });

    test('error_timeout keeps anonymous transport metadata', () {
      final result = TelemetryGuardrails.sanitize(
        'error_timeout',
        {
          'source': 'http',
          'method': 'GET',
          'endpoint': 'patients',
          'timeoutMs': 15000,
        },
      );
      expect(result, isNotNull);
      expect(result!['source'], 'http');
      expect(result['method'], 'GET');
      expect(result['endpoint'], 'patients');
      expect(result['timeoutMs'], 15000);
    });

    test('error_network keeps anonymous transport metadata', () {
      final result = TelemetryGuardrails.sanitize(
        'error_network',
        {
          'source': 'http',
          'method': 'POST',
          'endpoint': 'evv',
          'statusCode': 0,
          'errorType': 'client',
        },
      );
      expect(result, isNotNull);
      expect(result!['endpoint'], 'evv');
      expect(result['statusCode'], 0);
      expect(result['errorType'], 'client');
    });

    test('sync event details drop blocked patient identifiers', () {
      final result = TelemetryGuardrails.sanitize(
        'sync_started',
        {
          'scope': 'single',
          'pendingCount': 1,
          'patientId': 42,
        },
      );
      expect(result, isNotNull);
      expect(result!.containsKey('patientId'), isFalse);
      expect(result['scope'], 'single');
    });
  });
}
