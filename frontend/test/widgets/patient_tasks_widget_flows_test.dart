// Flow tests for PatientTasksWidget and the TaskFormDialog / TaskInfo
// widgets it opens, with ApiService's HTTP client replaced by a MockClient.

import 'dart:convert';

import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/patient_tasks_widget.dart';
import 'package:care_connect_app/widgets/task_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _tasks = [
  {
    'id': 1,
    'name': 'Take vitamins',
    'description': 'With breakfast',
    'date': '2026-03-04T09:00:00',
    'timeOfDay': '09:30',
    'patientId': 5,
    'frequency': 'DAILY',
    'taskInterval': 1,
    'doCount': 3,
    'daysOfWeek': [true, false, true, false, false, false, false],
    'notifications': [
      {
        'id': 4,
        'taskId': 1,
        'receiverId': 5,
        'title': 'Reminder',
        'body': 'Vitamins',
        'notificationType': 'TASK',
        'scheduledTime': '2026-03-04T09:00:00',
      },
    ],
  },
  {
    'id': 2,
    'name': 'Evening walk',
    'description': '',
    'date': '2026-03-04T18:00:00',
    'timeOfDay': {'hour': 18, 'minute': 15},
    'patientId': 5,
  },
];

final _templates = [
  {
    'id': 10,
    'name': 'Hydrate',
    'description': 'Drink water',
    'frequency': 'DAILY',
    'taskInterval': 1,
    'timeOfDay': '08:00',
    'iconCode': 58144,
  },
  {
    'id': 11,
    'name': 'Unknown icon',
    'description': 'Fallback icon',
    'iconCode': 1,
  },
  {'id': 12, 'name': 'No icon', 'description': 'Default icon'},
];

class _Backend {
  _Backend({
    this.listStatus = 200,
    this.templateStatus = 200,
    this.throwOnList = false,
  });

  final int listStatus;
  final int templateStatus;
  final bool throwOnList;
  final List<String> requests = <String>[];

  MockClient client() => MockClient((request) async {
        final path = request.url.path;
        requests.add('${request.method} $path');
        if (path.contains('templates')) {
          return http.Response(jsonEncode(_templates), templateStatus);
        }
        if (request.method == 'DELETE') {
          return http.Response('', 200);
        }
        if (path.contains('/patient/') && request.method == 'GET') {
          if (throwOnList) throw http.ClientException('offline');
          return http.Response(jsonEncode(_tasks), listStatus);
        }
        return http.Response('{}', 200);
      });
}

Future<void> _pump(WidgetTester tester, {bool isCaregiver = true}) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PatientTasksWidget(
            patientId: 5,
            patientName: 'Pat',
            isCaregiver: isCaregiver,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  void useBackend(_Backend backend) =>
      ApiService.debugSetHttpClient(backend.client());

  testWidgets('lists tasks for a caregiver with edit and delete actions',
      (tester) async {
    useBackend(_Backend());
    await _pump(tester);
    expect(find.text('Tasks for Pat'), findsOneWidget);
    expect(find.text('Take vitamins'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.byTooltip('Edit Task'), findsNWidgets(2));
    expect(find.byTooltip('Add Task'), findsOneWidget);
  });

  testWidgets('patients see tasks read-only and can open details',
      (tester) async {
    useBackend(_Backend());
    await _pump(tester, isCaregiver: false);
    expect(find.byTooltip('Edit Task'), findsNothing);
    await tester.tap(find.text('Take vitamins'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskInfo), findsOneWidget);
    expect(find.text('Frequency: DAILY'), findsOneWidget);
    expect(find.text('Days of Week: Mon, Wed'), findsOneWidget);
    expect(find.text('Notifications:'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskInfo), findsNothing);
  });

  testWidgets('a failed load shows the status code', (tester) async {
    useBackend(_Backend(listStatus: 500));
    await _pump(tester);
    expect(find.text('Failed to load tasks: 500'), findsOneWidget);
  });

  testWidgets('a network error while loading is shown', (tester) async {
    useBackend(_Backend(throwOnList: true));
    await _pump(tester);
    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('deleting a task confirms and reloads', (tester) async {
    final backend = _Backend();
    useBackend(backend);
    await _pump(tester);
    await tester.tap(find.byTooltip('Delete Task').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.startsWith('DELETE')), isEmpty);

    await tester.tap(find.byTooltip('Delete Task').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.startsWith('DELETE')), hasLength(1));
    expect(
      backend.requests
          .where((r) => r.startsWith('GET') && r.contains('/patient/')),
      hasLength(2),
    );
  });

  testWidgets('editing a task opens the form and Back cancels it',
      (tester) async {
    useBackend(_Backend());
    await _pump(tester);
    await tester.tap(find.byTooltip('Edit Task').first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Task'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Task'), findsNothing);
  });

  testWidgets('adding a task lists templates and opens the form',
      (tester) async {
    useBackend(_Backend());
    await _pump(tester);
    await tester.tap(find.byTooltip('Add Task'));
    await tester.pumpAndSettle();
    expect(find.text('Assign Task'), findsOneWidget);
    expect(find.text('Hydrate'), findsOneWidget);

    await tester.tap(find.text('Hydrate'));
    await tester.pumpAndSettle();
    expect(find.text('Add Custom Task'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Assign Task'), findsOneWidget);

    await tester.tap(find.text('Custom Task'));
    await tester.pumpAndSettle();
    expect(find.text('Add Custom Task'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Assign Task'), findsNothing);
  });

  testWidgets('a template load failure is shown in the dialog', (tester) async {
    useBackend(_Backend(templateStatus: 503));
    await _pump(tester);
    await tester.tap(find.byTooltip('Add Task'));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load templates: 503'), findsOneWidget);
  });

  testWidgets('saving an edited task sends the update and reloads',
      (tester) async {
    final backend = _Backend();
    useBackend(backend);
    await _pump(tester);
    await tester.tap(find.byTooltip('Edit Task').first);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Task Name'), 'Vitamin D');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'), 'After lunch');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Interval (e.g., 1 = every day)'),
      '2',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Count (number of occurrences)'),
      '5',
    );
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('M'));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.access_time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Task'), findsNothing);
    expect(backend.requests.where((r) => r.startsWith('PUT')), hasLength(1));
  });

  testWidgets('saving a task from a template creates it', (tester) async {
    final backend = _Backend();
    useBackend(backend);
    await _pump(tester);
    await tester.tap(find.byTooltip('Add Task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hydrate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Add Custom Task'), findsNothing);
    expect(
      backend.requests
          .where((r) => r.startsWith('POST') && r.contains('/patient/')),
      hasLength(1),
    );
  });

  testWidgets('a custom task needs a name before saving', (tester) async {
    useBackend(_Backend());
    await _pump(tester);
    await tester.tap(find.byTooltip('Add Task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom Task'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_today));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.access_time));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
  });
}
