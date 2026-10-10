// Tests for fetchMedicationsFromEnhancedProfile and the error mapping in
// extractMedicationPhoto
// (lib/features/health/medication-tracker/data/medications_api.dart).
//
// Uses http.runWithClient() to intercept top-level http.get calls, and an
// injected MockClient for the photo upload. No real network traffic occurs.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/medication-tracker/data/medications_api.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication_photo_extraction.dart';

// -- Constants ----------------------------------------------------------------

const _baseUrl = 'http://localhost:8080';
const _patientId = 42;
const _jwt = 'test.jwt.token';

// -- Fixture helpers ----------------------------------------------------------

Map<String, dynamic> _medJson({
  String name = 'Aspirin',
  String dosage = '100mg',
  String frequency = 'Daily',
  String route = 'Oral',
  bool isActive = true,
  String? medicationType,
}) =>
    {
      'medicationName': name,
      'dosage': dosage,
      'frequency': frequency,
      'route': route,
      'isActive': isActive,
      if (medicationType != null) 'medicationType': medicationType,
    };

/// Wraps the medications list in the expected response envelope.
Map<String, dynamic> _envelope(List<Map<String, dynamic>> meds) => {
      'data': {'activeMedications': meds},
    };

/// Convenience for calling fetchMedicationsFromEnhancedProfile with defaults.
Future<List<Medication>> _fetch({MockClient? client}) =>
    http.runWithClient(
      () => fetchMedicationsFromEnhancedProfile(
        baseUrl: _baseUrl,
        patientId: _patientId,
        jwtToken: _jwt,
      ),
      () => client ?? MockClient((_) async => http.Response('{}', 200)),
    );

// -- Tests --------------------------------------------------------------------

void main() {
  // ---------- Request construction ----------

  group('Request construction', () {
    test('hits /v1/api/patients/{patientId}/profile/enhanced', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(_envelope([])), 200);
      });

      await _fetch(client: client);
      expect(captured.url.path, '/v1/api/patients/$_patientId/profile/enhanced');
    });

    test('uses GET method', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(_envelope([])), 200);
      });

      await _fetch(client: client);
      expect(captured.method, 'GET');
    });

    test('sends Authorization header with Bearer token', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(_envelope([])), 200);
      });

      await _fetch(client: client);
      expect(captured.headers['Authorization'], 'Bearer $_jwt');
    });

    test('sends Content-Type application/json header', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(jsonEncode(_envelope([])), 200);
      });

      await _fetch(client: client);
      expect(captured.headers['Content-Type'], 'application/json');
    });
  });

  // ---------- Success responses ----------

  group('Success responses', () {
    test('returns empty list when activeMedications is empty', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode(_envelope([])), 200));

      final result = await _fetch(client: client);
      expect(result, isEmpty);
    });

    test('returns a single Medication from response', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode(_envelope([_medJson()])), 200));

      final result = await _fetch(client: client);
      expect(result, hasLength(1));
      expect(result.first, isA<Medication>());
      expect(result.first.medicationName, 'Aspirin');
    });

    test('returns multiple Medications from response', () async {
      final meds = [
        _medJson(name: 'Aspirin'),
        _medJson(name: 'Metformin', dosage: '500mg'),
        _medJson(name: 'Lisinopril', dosage: '10mg'),
      ];
      final client = MockClient(
          (_) async => http.Response(jsonEncode(_envelope(meds)), 200));

      final result = await _fetch(client: client);
      expect(result, hasLength(3));
      expect(result[0].medicationName, 'Aspirin');
      expect(result[1].medicationName, 'Metformin');
      expect(result[2].medicationName, 'Lisinopril');
    });

    test('parses dosage correctly', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(_envelope([_medJson(dosage: '250mg')])), 200));

      final result = await _fetch(client: client);
      expect(result.first.dosage, '250mg');
    });

    test('parses frequency correctly', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(_envelope([_medJson(frequency: 'Twice daily')])), 200));

      final result = await _fetch(client: client);
      expect(result.first.frequency, 'Twice daily');
    });

    test('parses route correctly', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(_envelope([_medJson(route: 'IV')])), 200));

      final result = await _fetch(client: client);
      expect(result.first.route, 'IV');
    });

    test('parses isActive correctly', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(_envelope([_medJson(isActive: false)])), 200));

      final result = await _fetch(client: client);
      expect(result.first.isActive, isFalse);
    });

    test('parses medicationType when present', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(
              _envelope([_medJson(medicationType: 'PRESCRIPTION')])),
          200));

      final result = await _fetch(client: client);
      expect(result.first.medicationType, MedicationType.PRESCRIPTION);
    });

    test('calculates nextDose based on frequency', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode(_envelope([_medJson(frequency: 'Daily')])), 200));

      final result = await _fetch(client: client);
      expect(result.first.nextDose, 'Today');
    });
  });

  // ---------- Missing or null data ----------

  group('Missing or null data handling', () {
    test('returns empty list when data field is null', () async {
      final client = MockClient(
          (_) async => http.Response(jsonEncode({'data': null}), 200));

      final result = await _fetch(client: client);
      expect(result, isEmpty);
    });

    test('returns empty list when data field is absent', () async {
      final client =
          MockClient((_) async => http.Response(jsonEncode({}), 200));

      final result = await _fetch(client: client);
      expect(result, isEmpty);
    });

    test('returns empty list when activeMedications is null', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'data': {'activeMedications': null}
          }),
          200));

      final result = await _fetch(client: client);
      expect(result, isEmpty);
    });

    test('returns empty list when activeMedications is absent', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'data': {'otherField': 'value'}
          }),
          200));

      final result = await _fetch(client: client);
      expect(result, isEmpty);
    });

    test('filters out non-Map items from activeMedications', () async {
      // whereType<Map<String, dynamic>> should skip non-map items
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'data': {
              'activeMedications': [
                _medJson(),
                'not-a-map',
                42,
              ]
            }
          }),
          200));

      final result = await _fetch(client: client);
      expect(result, hasLength(1));
    });
  });

  // ---------- Error responses ----------

  group('Error responses', () {
    test('throws Exception on 401 status', () async {
      final client =
          MockClient((_) async => http.Response('Unauthorized', 401));

      await expectLater(
        _fetch(client: client),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('401'),
        )),
      );
    });

    test('throws Exception on 404 status', () async {
      final client =
          MockClient((_) async => http.Response('Not Found', 404));

      await expectLater(
        _fetch(client: client),
        throwsA(isA<Exception>()),
      );
    });

    test('throws Exception on 500 status', () async {
      final client = MockClient(
          (_) async => http.Response('Internal Server Error', 500));

      await expectLater(
        _fetch(client: client),
        throwsA(isA<Exception>()),
      );
    });

    test('exception message includes status code and body', () async {
      final client = MockClient(
          (_) async => http.Response('bad gateway', 502));

      await expectLater(
        _fetch(client: client),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          allOf(contains('502'), contains('bad gateway')),
        )),
      );
    });
  });

  // ---------- extractMedicationPhoto error mapping ----------

  group('extractMedicationPhoto error mapping', () {
    // AuthTokenManager reads secure storage and preferences for the auth
    // header; stub those channels so the call reaches the MockClient.
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
    });

    const unreadable =
        'The photo could not be read. Please enter the medication manually.';

    Future<MedicationPhotoExtractionResult> extract(MockClient client) =>
        extractMedicationPhoto(
          patientId: _patientId,
          imageBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
          fileName: 'label.jpg',
          client: client,
        );

    test(
        'TC-MED-PHOTO-092: a JSON error that is not a 400, or a 400 with no message, shows the generic manual-entry message',
        () async {
      // Arrange
      final server500 = MockClient((_) async => http.Response(
          jsonEncode({'message': 'NullPointerException in OCR step'}), 500));
      final bare400 =
          MockClient((_) async => http.Response(jsonEncode({}), 400));

      // Act
      final from500 = await extract(server500);
      final from400 = await extract(bare400);

      // Assert: only a 400 message is user-facing; server internals are not
      expect(from500.manualEntryRequired, isTrue);
      expect(from500.message, unreadable);
      expect(from400.manualEntryRequired, isTrue);
      expect(from400.message, unreadable);
    });
  });
}
