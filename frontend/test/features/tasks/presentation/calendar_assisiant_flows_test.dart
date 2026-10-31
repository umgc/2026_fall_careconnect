// Task CRUD flows for CalendarAssistantScreen
// (lib/features/tasks/presentation/calendar_assisiant.dart) against a
// MockClient behind ApiService: add (with appointment notification preview),
// edit single and recurring tasks, delete (single, series, queued, failing),
// filters, view switching, legend management and caregiver patients.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

String _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).toIso8601String();
}

Map<String, dynamic> _task(
  int id,
  String name, {
  String taskType = 'general',
  String? timeOfDay,
  String? frequency,
  int? parentTaskId,
  int patientId = 1,
}) =>
    {
      'id': id,
      'name': name,
      'description': '$name description',
      'date': _today(),
      'timeOfDay': timeOfDay,
      'patientId': patientId,
      'taskType': taskType,
      'isComplete': false,
      'frequency': frequency,
      'parentTaskId': parentTaskId,
    };

class _Backend {
  List<Map<String, dynamic>> tasks = [
    _task(1, 'Take Medicine', taskType: 'medication'),
    _task(2, 'Doctor Visit', taskType: 'appointment', timeOfDay: '09:30'),
    _task(3, 'Walk Child', parentTaskId: 1),
  ];
  int editStatus = 200;
  int deleteStatus = 200;
  int createStatus = 201;
  bool queued = false;
  final List<String> calls = <String>[];

  Map<String, String> get _headers =>
      queued ? {'x-offline-queued': 'true'} : const {};

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    calls.add('${r.method} $p');
    if (p.contains('/caregivers/') && p.endsWith('/patients')) {
      return http.Response(
        jsonEncode([
          {
            'patient': {'id': 1, 'firstName': 'Pat', 'lastName': 'One'},
          },
          {
            'patient': {'id': 2, 'firstName': 'Sam', 'lastName': 'Two'},
          },
          {'patient': null},
        ]),
        200,
      );
    }
    if (p.endsWith('/preview-notification')) {
      return http.Response(
        jsonEncode({
          'notificationPreview': {
            'emailRecipient': 'p@example.com',
            'emailSubject': 'Reminder',
            'emailTextBody': 'See you soon',
            'smsBody': 'Reminder sms',
          },
        }),
        200,
      );
    }
    final patientMatch = RegExp(r'/patient/(\d+)$').firstMatch(p);
    if (patientMatch != null) {
      if (r.method == 'POST') {
        return http.Response('{}', createStatus, headers: _headers);
      }
      final pid = int.parse(patientMatch.group(1)!);
      return http.Response(
          jsonEncode(tasks.where((t) => t['patientId'] == pid).toList()), 200);
    }
    final idMatch = RegExp(r'/(\d+)$').firstMatch(p);
    if (idMatch != null) {
      final id = int.parse(idMatch.group(1)!);
      if (r.method == 'GET') {
        final t = tasks.where((t) => t['id'] == id).toList();
        return t.isEmpty
            ? http.Response('{}', 404)
            : http.Response(jsonEncode(t.first), 200);
      }
      if (r.method == 'PUT') {
        return http.Response('{}', editStatus, headers: _headers);
      }
      if (r.method == 'DELETE') {
        return http.Response('', deleteStatus, headers: _headers);
      }
    }
    return http.Response('[]', 200);
  }
}

late _Backend _b;

Future<void> _settle(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pump(WidgetTester tester, {UserSession? user}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
            mockUser: user ??
                MockUser(role: 'PATIENT', patientId: 1, name: 'Test Patient'),
          ),
        ),
        ChangeNotifierProvider<TaskTypeManager>(
          create: (_) => TaskTypeManager(),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CalendarAssistantScreen(),
      ),
    ),
  );
  await _settle(tester);
}

void _dismissSnackBars(WidgetTester tester) {
  ScaffoldMessenger.of(tester.element(find.byType(CalendarAssistantScreen)))
      .clearSnackBars();
}

void main() {
  final originalOnError = FlutterError.onError;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _b = _Backend();
    ApiService.debugSetHttpClient(MockClient(_b.handle));
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
    FlutterError.onError = (details) {
      if (details.toString().contains('overflow')) return;
      originalOnError?.call(details);
    };
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  testWidgets('editing a single task saves it', (tester) async {
    await _pump(tester);
    expect(find.text('Take Medicine'), findsWidgets);

    await tester.tap(find.byIcon(Icons.edit).at(1)); // first list row
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Edit Task'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.text('Task updated successfully'), findsOneWidget);
  });

  testWidgets('editing a series member asks how to apply the change',
      (tester) async {
    _b.queued = true;
    await _pump(tester);

    final walkRow = find.ancestor(
        of: find.text('Walk Child'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: walkRow, matching: find.byIcon(Icons.edit)));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Update recurring task'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('Task update queued for sync when internet is restored'),
        findsOneWidget);

    // Cancelling the series prompt drops the edit.
    _dismissSnackBars(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: walkRow, matching: find.byIcon(Icons.edit)));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Update recurring task'), findsNothing);
  });

  testWidgets('a failed edit reports the failure', (tester) async {
    _b.editStatus = 500;
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.edit).at(1));
    await _settle(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.textContaining('500'), findsOneWidget);
  });

  testWidgets('deleting asks first and then removes the task',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    expect(find.text('Confirm Delete'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(find.textContaining('deleted'), findsOneWidget);
  });

  testWidgets('deleting a series member can delete the whole series',
      (tester) async {
    _b.queued = true;
    _b.deleteStatus = 204;
    await _pump(tester);
    final walkRow = find.ancestor(
        of: find.text('Walk Child'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(
        of: walkRow, matching: find.byIcon(Icons.delete)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete entire series'));
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(
      find.text('Task series delete queued for sync when internet is restored'),
      findsOneWidget,
    );
  });

  testWidgets('a failed delete shows the status code', (tester) async {
    _b.deleteStatus = 500;
    await _pump(tester);
    await tester.tap(find.byIcon(Icons.delete).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(find.text('Failed to delete task: 500'), findsOneWidget);
  });

  testWidgets('adding an appointment shows the notification preview',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Add Task').first);
    await tester.pumpAndSettle();
    expect(find.text('Add Task'), findsWidgets);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task Title'), 'Checkup');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appointment').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Appointment Notification Preview'), findsOneWidget);
    expect(find.text('Email To: p@example.com'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Task added successfully'), findsOneWidget);
  });

  testWidgets('a failed add reports the failure', (tester) async {
    _b.createStatus = 500;
    await _pump(tester);
    await tester.tap(find.text('Add Task').first);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task Title'), 'Nope');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appointment').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(find.byType(SnackBar), findsWidgets);
  });

  testWidgets('filters, view switching and legend management',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Expand filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilterChip).first);
    await _settle(tester);
    await tester.tap(find.text('Clear'));
    await _settle(tester);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    expect(find.text('Weekly'), findsOneWidget);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Manage Task Types'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsWidgets);
  });

  testWidgets('caregiver sees patient filters for each linked patient',
      (tester) async {
    _b.tasks.add(_task(9, 'Sam Task', patientId: 2));
    await _pump(
      tester,
      user: MockUser(role: 'CAREGIVER', caregiverId: 7, patientId: null),
    );
    expect(find.text('Sam Task'), findsWidgets);
    await tester.tap(find.byTooltip('Expand filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Sam Two'));
    await _settle(tester);
    expect(find.text('Take Medicine'), findsNothing);

    await tester.tap(find.text('Add Task').first);
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Assign to All Patients'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
