// Tests for ScheduleVisitDialog
// (lib/features/shift_scheduling/presentation/widgets/schedule_visit_dialog.dart)
//
// ScheduleVisitDialog is a form for creating or editing a scheduled visit. It
// renders synchronously (no network call on init) and only touches the API
// when "Check for Conflicts" is pressed, so most tests need no HTTP setup;
// the conflict-check path injects a fake Dio adapter via
// ApiClient.debugSetHttpClientAdapter.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/features/shift_scheduling/models/scheduled_visit_model.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/schedule_visit_dialog.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);
  final String body;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(body, 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void _setupStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    if (call.method == 'readAll') return <String, String>{};
    return null;
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, (call) async {
    if (call.method == 'check') return ['wifi'];
    return null;
  });
}

void _teardownStubs() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_connectivityChannel, null);
}

ScheduledVisit _sampleVisit() => ScheduledVisit(
      id: 7,
      caregiverId: 1,
      patientId: 42,
      patientName: 'Mary Johnson',
      serviceType: 'Personal Care',
      scheduledDate: DateTime(2026, 8, 1),
      scheduledTime: const TimeOfDay(hour: 9, minute: 30),
      durationMinutes: 90,
      priority: 'High',
      notes: 'Bring updated care plan',
      status: 'Scheduled',
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

Widget _host(Widget dialog) => MaterialApp(home: Scaffold(body: dialog));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _setupStubs();
    ApiClient.instance
        .debugSetHttpClientAdapter(_FakeAdapter(jsonEncode({'hasConflict': false})));
  });
  tearDown(_teardownStubs);

  group('ScheduleVisitDialog - create mode', () {
    testWidgets('shows the "Schedule New Visit" title', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();
      expect(find.text('Schedule New Visit'), findsOneWidget);
    });

    testWidgets('renders empty patient and service fields', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();
      expect(find.text('Patient Name'), findsOneWidget);
      expect(find.text('Service Type'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
    });

    testWidgets('offers the create action labeled "Create"', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();
      expect(find.widgetWithText(ElevatedButton, 'Create'), findsOneWidget);
    });

    testWidgets('shows Check for Conflicts and Cancel actions', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();
      expect(find.text('Check for Conflicts'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('ScheduleVisitDialog - edit mode', () {
    testWidgets('shows the "Update Visit" title with an existing visit',
        (tester) async {
      await tester.pumpWidget(
          _host(ScheduleVisitDialog(caregiverId: 1, existingVisit: _sampleVisit())));
      await tester.pump();
      expect(find.text('Update Visit'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Update'), findsOneWidget);
    });

    testWidgets('pre-fills fields from the existing visit', (tester) async {
      await tester.pumpWidget(
          _host(ScheduleVisitDialog(caregiverId: 1, existingVisit: _sampleVisit())));
      await tester.pump();
      expect(find.text('Mary Johnson'), findsOneWidget);
      expect(find.text('Personal Care'), findsOneWidget);
      expect(find.text('Bring updated care plan'), findsOneWidget);
    });
  });

  group('ScheduleVisitDialog - validation', () {
    testWidgets('blocks save and warns when patient name is empty',
        (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      final createBtn = find.widgetWithText(ElevatedButton, 'Create');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump(); // surface the SnackBar

      expect(find.text('Please enter patient name'), findsOneWidget);
    });

    testWidgets('saves when name and service are filled (date defaults to now)',
        (tester) async {
      // In create mode the dialog pre-populates date and time with the current
      // date/time, so filling the required text fields yields a valid form.
      ScheduledVisit? savedVisit;
      await tester.pumpWidget(_host(ScheduleVisitDialog(
        caregiverId: 1,
        onSave: (v) => savedVisit = v,
      )));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'John Doe');
      await tester.enterText(fields.at(1), 'Nursing');
      final createBtn = find.widgetWithText(ElevatedButton, 'Create');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump();

      expect(savedVisit, isNotNull);
      expect(savedVisit!.patientName, 'John Doe');
      expect(savedVisit!.serviceType, 'Nursing');
      expect(savedVisit!.caregiverId, 1);
    });

    testWidgets('does not invoke onSave when the form is invalid',
        (tester) async {
      var saved = false;
      await tester.pumpWidget(_host(ScheduleVisitDialog(
        caregiverId: 1,
        onSave: (_) => saved = true,
      )));
      await tester.pump();

      final createBtn = find.widgetWithText(ElevatedButton, 'Create');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump();

      expect(saved, isFalse);
    });
  });

  group('ScheduleVisitDialog - interactions', () {
    testWidgets('Cancel closes the dialog', (tester) async {
      // Launch the dialog through showDialog so its Navigator.pop has a route
      // to pop, mirroring production usage.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog(
                context: context,
                builder: (_) => const ScheduleVisitDialog(caregiverId: 1),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleVisitDialog), findsOneWidget);

      final cancel = find.text('Cancel');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel);
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleVisitDialog), findsNothing);
    });

    testWidgets('typing updates the patient name field', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'Alex Rivera');
      await tester.pump();

      expect(find.text('Alex Rivera'), findsOneWidget);
    });

    testWidgets('Check for Conflicts triggers the API without crashing',
        (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'John Doe');
      await tester.enterText(fields.at(1), 'Nursing');
      final checkBtn = find.text('Check for Conflicts');
      await tester.ensureVisible(checkBtn);
      await tester.tap(checkBtn);
      await tester.pumpAndSettle();

      // Still mounted; the conflict check resolved against the fake API.
      expect(find.byType(ScheduleVisitDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ScheduleVisitDialog - validation & inputs', () {
    testWidgets('warns when service type is empty', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), 'John Doe');
      final createBtn = find.widgetWithText(ElevatedButton, 'Create');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump();

      expect(find.text('Please enter service type'), findsOneWidget);
    });

    testWidgets('opening the date field shows a date picker', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      final dateField =
          find.ancestor(of: find.text('Date'), matching: find.byType(InkWell));
      await tester.ensureVisible(dateField.first);
      await tester.tap(dateField.first);
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsOneWidget); // date picker is open
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening the time field shows a time picker', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      final timeField =
          find.ancestor(of: find.text('Time'), matching: find.byType(InkWell));
      await tester.ensureVisible(timeField.first);
      await tester.tap(timeField.first);
      await tester.pumpAndSettle();

      expect(find.text('OK'), findsOneWidget); // time picker is open
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting a duration updates the dropdown', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      final dd = find.byType(DropdownButtonFormField<int>);
      await tester.ensureVisible(dd);
      await tester.tap(dd);
      await tester.pumpAndSettle();
      await tester.tap(find.text('90 minutes').last);
      await tester.pumpAndSettle();

      expect(find.text('90 minutes'), findsOneWidget);
    });

    testWidgets('selecting a priority updates the dropdown', (tester) async {
      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      final dd = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dd);
      await tester.tap(dd);
      await tester.pumpAndSettle();
      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();

      expect(find.text('High'), findsOneWidget);
    });

    testWidgets('blocks save until a detected conflict is resolved',
        (tester) async {
      // Reinstall the adapter so the conflict check reports a conflict.
      ApiClient.instance.debugSetHttpClientAdapter(_FakeAdapter(jsonEncode({
        'hasConflicts': true,
        'conflictingVisits': [],
        'conflictType': 'overlap',
        'conflictMessages': ['Overlaps an existing visit'],
      })));

      await tester.pumpWidget(_host(const ScheduleVisitDialog(caregiverId: 1)));
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(0), 'John Doe');
      await tester.enterText(find.byType(TextField).at(1), 'Nursing');

      final checkBtn = find.text('Check for Conflicts');
      await tester.ensureVisible(checkBtn);
      await tester.tap(checkBtn);
      await tester.pumpAndSettle();

      final createBtn = find.widgetWithText(ElevatedButton, 'Create');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump();

      expect(find.text('Please resolve conflicts before saving'), findsOneWidget);
    });
  });
}
