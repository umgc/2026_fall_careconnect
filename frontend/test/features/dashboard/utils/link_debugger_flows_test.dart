// Tests for LinkDebugger.debugLinkIdForPatient
// (lib/features/dashboard/utils/link_debugger.dart) with the caregiver
// patients endpoint served by a mock HTTP client, so the real private
// search helpers run against each response shape.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/features/dashboard/utils/link_debugger.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../mock_user_provider.dart';

late http.Response Function() _response;

final _patient = Patient(
  id: 7,
  firstName: 'Lin',
  lastName: 'Ko',
  email: '',
  phone: '',
  dob: '',
  relationship: '',
);

Future<List<String>> _run(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>.value(
      value: MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 3),
      ),
      child: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }),
    ),
  );
  final lines = <String>[];
  await runZoned(
    () => _patient.debugLinkId(ctx),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => lines.add(line),
    ),
  );
  return lines;
}

void main() {
  setUpAll(() => ApiService.debugSetHttpClient(
        MockClient((_) async => _response()),
      ));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  final cases = <String, Object>{
    'direct list match': [
      'skip-me',
      {'id': 7, 'linkId': 55, 'patient': {'id': 9}},
    ],
    'nested match with link map': [
      {
        'id': 70,
        'patient': {'id': 7, 'linkId': 1},
        'link': {'id': 99, 'status': 'ACTIVE'},
      },
    ],
    'nested match with link.linkId': [
      {
        'patient': {'id': 7},
        'link': {'linkId': '5', 'isActive': true},
      },
    ],
    'nested match with link.relationshipId': [
      {
        'patient': {'id': 7},
        'link': {'relationshipId': 6, 'isActive': false},
      },
    ],
    'nested match with empty link': [
      {
        'patient': {'id': 7},
        'link': <String, dynamic>{},
      },
    ],
    'nested match with non-map link': [
      {
        'patient': {'id': 7},
        'link': 'oops',
      },
    ],
    'nested match without link': [
      {
        'patient': {'id': 7},
      },
    ],
    'not found': [
      {'id': 1},
      {'patient': {'id': 2}},
    ],
    'map with patients list': {
      'patients': [
        {'id': 7},
      ],
    },
    'map without patients': {'other': true},
    'scalar body': 42,
  };

  cases.forEach((name, body) {
    testWidgets('debugLinkId handles $name', (tester) async {
      _response = () => http.Response(jsonEncode(body), 200);
      final lines = await _run(tester);
      expect(lines, contains('🔍 ----- LINK DEBUGGER STARTING -----'));
      expect(lines.last, '🔍 ----- LINK DEBUGGER FINISHED -----');
    });
  });

  testWidgets('debugLinkId reports non-200 status', (tester) async {
    _response = () => http.Response('nope', 500);
    final lines = await _run(tester);
    expect(lines, contains('❌ Failed to get API response: 500'));
  });

  testWidgets('debugLinkId reports invalid JSON as an error', (tester) async {
    _response = () => http.Response('{bad', 200);
    final lines = await _run(tester);
    expect(lines.any((l) => l.startsWith('❌ Error in debug:')), isTrue);
  });
}
