// Tests for AiAnalyzeService.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/ai_analyze_service.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final Map<String, String?> _secureStore = {};

void _setupSecureStorageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'write':
        _secureStore[call.arguments['key'] as String] =
            call.arguments['value'] as String?;
        return null;
      case 'read':
        return _secureStore[call.arguments['key'] as String];
      case 'delete':
        _secureStore.remove(call.arguments['key'] as String);
        return null;
      case 'deleteAll':
        _secureStore.clear();
        return null;
      default:
        return null;
    }
  });
}

String _makeJwt({required int expSeconds}) {
  final header = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final payload = base64Url.encode(
    utf8.encode(jsonEncode({'sub': '1', 'exp': expSeconds})),
  );
  return '$header.$payload.fakesig';
}

void _seedValidJwt() {
  final futureExp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
  final jwt = _makeJwt(expSeconds: futureExp);
  _secureStore['jwt_token'] = jwt;
  _secureStore['token_expiry'] = futureExp.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _secureStore.clear();
    SharedPreferences.setMockInitialValues({});
    _setupSecureStorageStub();
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  group('AiAnalyzeService.extractAllergy', () {
    test('no JWT → throws No JWT available', () async {
      await expectLater(
        http.runWithClient(
          () => AiAnalyzeService.extractAllergy(
            patientId: 1,
            transcript: 'penicillin allergy',
          ),
          () => MockClient((_) async => http.Response('{}', 200)),
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('No JWT available'),
        )),
      );
    });

    test('JWT + 200 with nested data map → returns allergen/reaction/severity', () async {
      _seedValidJwt();
      final responseBody = jsonEncode({
        'data': {'allergen': 'Penicillin', 'reaction': 'rash', 'severity': 'mild'},
      });
      final result = await http.runWithClient(
        () => AiAnalyzeService.extractAllergy(
          patientId: 1,
          transcript: 'penicillin allergy rash',
        ),
        () => MockClient((_) async => http.Response(responseBody, 200)),
      );
      expect(result['allergen'], 'Penicillin');
      expect(result['reaction'], 'rash');
      expect(result['severity'], 'MILD');
    });

    test('JWT + 200 with medication key → maps to allergen', () async {
      _seedValidJwt();
      final responseBody = jsonEncode({
        'data': {'medication': 'Aspirin', 'reaction': 'rash', 'severity': 'mild'},
      });
      final result = await http.runWithClient(
        () => AiAnalyzeService.extractAllergy(
          patientId: 1,
          transcript: 'aspirin rash',
        ),
        () => MockClient((_) async => http.Response(responseBody, 200)),
      );
      expect(result['allergen'], 'Aspirin');
    });
  });

  group('AiAnalyzeService.extractSymptom', () {
    test('JWT + 200 with data map → returns data map', () async {
      _seedValidJwt();
      final responseBody = jsonEncode({
        'data': {
          'symptomKey': 'HEADACHE',
          'symptomValue': 'severe headache',
          'severity': 'HIGH',
          'notes': 'Started yesterday',
        },
      });
      final result = await http.runWithClient(
        () => AiAnalyzeService.extractSymptom(
          patientId: 1,
          transcript: 'severe headache since yesterday',
        ),
        () => MockClient((_) async => http.Response(responseBody, 200)),
      );
      expect(result['symptomKey'], 'HEADACHE');
      expect(result['severity'], 'HIGH');
    });
  });
}
