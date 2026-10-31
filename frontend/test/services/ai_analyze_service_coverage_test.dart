import 'dart:convert';

import 'package:care_connect_app/services/ai_analyze_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _jwt(int exp) {
  final h = base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'));
  final p =
      base64Url.encode(utf8.encode(jsonEncode({'sub': '1', 'exp': exp})));
  return '$h.$p.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': _jwt(exp),
      'token_expiry': '$exp',
    });
  });

  test('extractAllergy sends context hints and handles list response',
      () async {
    Map<String, dynamic>? sent;
    final result = await http.runWithClient(
      () => AiAnalyzeService.extractAllergy(
        patientId: 3,
        transcript: 'peanut hives',
        allergen: ' Peanut ',
        severity: ' severe ',
        reaction: ' hives ',
      ),
      () => MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('[]', 200);
      }),
    );
    expect(sent!['context'],
        {'allergen': 'Peanut', 'severity': 'severe', 'reaction': 'hives'});
    expect(result['reaction'], 'peanut hives');
    expect(result['allergen'], '');
  });

  test('extractAllergy throws on non-2xx', () async {
    await expectLater(
      http.runWithClient(
        () => AiAnalyzeService.extractAllergy(patientId: 1, transcript: 'x'),
        () => MockClient((_) async => http.Response('bad', 500)),
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('extractSymptom sends hints and falls back on non-data body', () async {
    Map<String, dynamic>? sent;
    final result = await http.runWithClient(
      () => AiAnalyzeService.extractSymptom(
        patientId: 3,
        transcript: 'bad cough',
        symptomKeyHint: ' COUGH ',
        severityHint: ' HIGH ',
        notesHint: ' at night ',
        context: {'source': 'voice'},
      ),
      () => MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'other': 1}), 200);
      }),
    );
    expect(sent!['context'], {
      'symptomKey': 'COUGH',
      'severity': 'HIGH',
      'notes': 'at night',
      'source': 'voice',
    });
    expect(result['notes'], 'bad cough');
  });

  test('extractSymptom throws on error status', () async {
    await expectLater(
      http.runWithClient(
        () => AiAnalyzeService.extractSymptom(patientId: 1, transcript: 'x'),
        () => MockClient((_) async => http.Response('bad', 400)),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
