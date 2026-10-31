// Additional coverage for CurrentMedicationsSection: delete / approve flows
// (guard clauses, dialog cancel, error bodies, thrown errors) and start/end
// date rendering.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/current_medications_card.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/services/api_service.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

late Future<http.Response> Function(http.Request) _handler;
final _allRequests = <http.Request>[];

/// Requests made by the widget itself (telemetry posts are ignored).
List<http.Request> get _requests =>
    _allRequests.where((r) => !r.url.path.contains('telemetry')).toList();

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

Medication _med({
  int? id = 5,
  int? patientId = 7,
  bool isActive = true,
  String? startDate,
  String? endDate,
}) =>
    Medication(
      id: id,
      patientId: patientId,
      medicationName: 'Lisinopril',
      dosage: '10mg',
      frequency: 'Daily',
      route: 'Oral',
      isActive: isActive,
      startDate: startDate,
      endDate: endDate,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_wrap(child));
}

Future<void> _tapDeleteAndConfirm(WidgetTester tester,
    {bool confirm = true}) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
  await tester.pumpAndSettle();
  expect(find.text('Delete Medication'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, confirm ? 'Delete' : 'Cancel'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _allRequests.clear();
    _handler = (request) async => http.Response('{}', 200);
    ApiService.debugSetHttpClient(MockClient((request) async {
      _allRequests.add(request);
      return _handler(request);
    }));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  testWidgets('renders start and end dates (and raw invalid date)',
      (tester) async {
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [
        _med(startDate: '2025-03-04', endDate: '2025-12-25'),
      ]),
    );
    expect(find.text('Started'), findsOneWidget);
    expect(find.text('Mar 4, 2025'), findsOneWidget);
    expect(find.text('End Date'), findsOneWidget);
    expect(find.text('Dec 25, 2025'), findsOneWidget);

    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med(startDate: 'not-a-date')]),
    );
    expect(find.text('not-a-date'), findsOneWidget);
    expect(find.text('End Date'), findsNothing);
  });

  testWidgets('delete without ids shows missing-ID snackbar', (tester) async {
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med(id: null)], caregiverId: 1),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pump();
    expect(find.text('Unable to delete medication: Missing ID'),
        findsOneWidget);
  });

  testWidgets('delete without caregiver shows missing caregiver snackbar',
      (tester) async {
    await _pump(tester, CurrentMedicationsSection(entries: [_med()]));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pump();
    expect(find.text('Unable to delete medication: Missing caregiver ID'),
        findsOneWidget);
  });

  testWidgets('cancelling delete dialog makes no request', (tester) async {
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med()], caregiverId: 3),
    );
    await _tapDeleteAndConfirm(tester, confirm: false);
    expect(_requests, isEmpty);
    expect(find.text('Delete Medication'), findsNothing);
  });

  testWidgets('delete with non-JSON error body shows status code',
      (tester) async {
    _handler = (request) async => http.Response('oops', 500);
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med()], caregiverId: 3),
    );
    await _tapDeleteAndConfirm(tester);
    expect(_requests.single.method, 'DELETE');
    expect(_requests.single.url.path, contains('/caregiver/3'));
    expect(find.text('Failed to delete medication: 500'), findsOneWidget);
  });

  testWidgets('delete with thrown client error shows fallback failure',
      (tester) async {
    _handler = (request) async => throw Exception('socket closed');
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med()], caregiverId: 3),
    );
    await _tapDeleteAndConfirm(tester);
    // ApiService converts the thrown error into a 500 with no message.
    expect(find.text('Failed to delete medication'), findsOneWidget);
  });

  testWidgets('approve without ids shows missing-ID snackbar', (tester) async {
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med(patientId: null, isActive: false)]),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pump();
    expect(find.text('Unable to approve medication: Missing ID'),
        findsOneWidget);
  });

  testWidgets('approve failure surfaces server message', (tester) async {
    _handler = (request) async =>
        http.Response('{"message":"Not allowed"}', 403);
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med(isActive: false)]),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(_requests.single.method, 'PUT');
    expect(_requests.single.url.path, endsWith('/approve'));
    expect(find.text('Not allowed'), findsOneWidget);
  });

  testWidgets('approve failure without message uses fallback',
      (tester) async {
    _handler = (request) async => http.Response('{}', 400);
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med(isActive: false)]),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Failed to approve medication'), findsOneWidget);
  });

  testWidgets('approve with non-JSON error body shows Error snackbar',
      (tester) async {
    _handler = (request) async => http.Response('<html>', 502);
    await _pump(
      tester,
      CurrentMedicationsSection(entries: [_med(isActive: false)]),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error:'), findsOneWidget);
  });
}
