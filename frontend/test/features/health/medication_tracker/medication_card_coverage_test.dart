// Additional MedicationCard coverage: the remove flow (confirm dialog,
// success / failure responses, missing ids, and the busy spinner).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/widgets/medication-card.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Medication _med({int? id = 11}) => Medication(
      id: id,
      medicationName: 'Ibuprofen',
      dosage: '200mg',
      frequency: 'Twice daily',
      route: 'Oral',
      isActive: true,
      medicationType: MedicationType.OVER_THE_COUNTER,
    );

Widget _wrap(Widget child, {int? patientId = 5}) {
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'p@test.com',
    role: 'PATIENT',
    token: 'tok',
    name: 'Pat',
    patientId: patientId,
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Future<void> _confirmRemove(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.delete_outline));
  await tester.pumpAndSettle();
  expect(find.text('Remove Medication'), findsOneWidget);
  await tester.tap(find.widgetWithText(TextButton, 'Remove'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Telemetry opted out so no backend traffic is attempted.
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('cancel keeps the medication and makes no request',
      (tester) async {
    var requests = 0;
    ApiService.debugSetHttpClient(MockClient((_) async {
      requests++;
      return http.Response('', 204);
    }));
    await tester.pumpWidget(
        _wrap(MedicationCard(medication: _med(), onStatusChanged: (_) {})));
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('Remove Medication'), findsNothing);
  });

  testWidgets('successful remove shows snackbar and notifies parent',
      (tester) async {
    String? method;
    String? path;
    ApiService.debugSetHttpClient(MockClient((req) async {
      method = req.method;
      path = req.url.path;
      return http.Response('', 204);
    }));
    var removed = 0;
    await tester.pumpWidget(_wrap(MedicationCard(
      medication: _med(),
      onStatusChanged: (_) {},
      onMedicationRemoved: () => removed++,
    )));
    await _confirmRemove(tester);
    await tester.pumpAndSettle();

    expect(method, 'DELETE');
    expect(path, endsWith('/5/medications/11'));
    expect(removed, 1);
    expect(find.text('Medication removed successfully'), findsOneWidget);
  });

  testWidgets('spinner shows while the remove request is in flight',
      (tester) async {
    final gate = Completer<http.Response>();
    ApiService.debugSetHttpClient(MockClient((_) => gate.future));
    await tester.pumpWidget(
        _wrap(MedicationCard(medication: _med(), onStatusChanged: (_) {})));
    await _confirmRemove(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete(http.Response('', 200));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('server error shows failure snackbar with status code',
      (tester) async {
    ApiService.debugSetHttpClient(
        MockClient((_) async => http.Response('bad', 500)));
    var removed = 0;
    await tester.pumpWidget(_wrap(MedicationCard(
      medication: _med(),
      onStatusChanged: (_) {},
      onMedicationRemoved: () => removed++,
    )));
    await _confirmRemove(tester);
    await tester.pumpAndSettle();
    expect(find.text('Failed to remove medication: 500'), findsOneWidget);
    expect(removed, 0);
  });

  testWidgets('missing patient id shows an error', (tester) async {
    await tester.pumpWidget(_wrap(
      MedicationCard(medication: _med(), onStatusChanged: (_) {}),
      patientId: null,
    ));
    await _confirmRemove(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Patient ID not found'), findsOneWidget);
  });

  testWidgets('missing medication id shows an error', (tester) async {
    await tester.pumpWidget(_wrap(
        MedicationCard(medication: _med(id: null), onStatusChanged: (_) {})));
    await _confirmRemove(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Medication ID not found'), findsOneWidget);
  });
}
