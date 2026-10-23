// Focused tests for the Issue #249 changes in CalendarAssistantScreen.
// HTTP and platform services are mocked so these tests do not use a live API.

import 'dart:convert';

import 'package:care_connect_app/features/tasks/presentation/calendar_assisiant.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/task_form_dialog.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
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
import '../../../test_support/fixtures.dart';

Widget _calendarFor(UserSession user) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: user),
      ),
      ChangeNotifierProvider<TaskTypeManager>(
        create: (_) => TaskTypeManager(),
      ),
    ],
    child: const MaterialApp(home: CalendarAssistantScreen()),
  );
}

Future<void> _pumpLoadedCalendar(
  WidgetTester tester,
  UserSession user,
) async {
  await tester.pumpWidget(_calendarFor(user));
  await tester.pump();
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Map<String, dynamic> _recurringTaskJson(DateTime date) {
  final daysOfWeek = List<bool>.filled(7, false);
  daysOfWeek[date.weekday % 7] = true;

  return {
    'id': 42,
    'name': 'Weekly Walk',
    'description': 'Walk outside',
    'date': DateTime(date.year, date.month, date.day).toIso8601String(),
    'timeOfDay': null,
    'patientId': 1,
    'taskType': 'exercise',
    'isComplete': false,
    'frequency': 'weekly',
    'interval': 1,
    'count': 1,
    'daysOfWeek': daysOfWeek,
    'parentTaskId': null,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (_) async => null,
    );
  });

  tearDown(() {
    ApiService.debugResetHttpClient();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });

  testWidgets('adds a patient task through the V2 endpoint', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? createdTaskBody;
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'POST' &&
          request.url.path.contains('/v2/api/tasks/patient/1')) {
        createdTaskBody = request.body;
        return http.Response('{}', 201);
      }
      if (request.method == 'GET' &&
          request.url.path.contains('/v2/api/tasks/patient/1')) {
        return http.Response('[]', 200);
      }
      return http.Response('{}', 200);
    });
    ApiService.debugSetHttpClient(client);

    // Arrange
    await _pumpLoadedCalendar(tester, fakePatientUser());

    // Act
    await tester.tap(find.text('Add Task'));
    await tester.pumpAndSettle();
    final taskDialog = tester.widget<TaskFormDialog>(
      find.byType(TaskFormDialog),
    );
    expect(taskDialog.defaultPatientId, 1);
    await tester.enterText(find.byType(TextFormField).first, 'Morning Walk');
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(saveButton);
    expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // Assert
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .join(' | ');
    expect(
      createdTaskBody,
      isNotNull,
      reason: 'Requests: $requests\nVisible text: $visibleText',
    );
    expect(jsonDecode(createdTaskBody!)['name'], 'Morning Walk');
    expect(find.text('Task added successfully'), findsOneWidget);
  });

  testWidgets('recurring edit asks about the entire series by default',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final taskJson = _recurringTaskJson(DateTime.now());
    Map<String, dynamic>? updatedTaskBody;
    final client = MockClient((request) async {
      if (request.method == 'GET' &&
          request.url.path.endsWith('/v2/api/tasks/42')) {
        return http.Response(jsonEncode(taskJson), 200);
      }
      if (request.method == 'PUT' &&
          request.url.path.endsWith('/v2/api/tasks/42')) {
        updatedTaskBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      }
      if (request.method == 'GET' &&
          request.url.path.contains('/v2/api/tasks/patient/1')) {
        return http.Response(jsonEncode([taskJson]), 200);
      }
      return http.Response('{}', 200);
    });
    ApiService.debugSetHttpClient(client);

    // Arrange
    await _pumpLoadedCalendar(tester, fakePatientUser());

    // Act
    await tester.tap(find.byIcon(Icons.edit).last);
    await tester.pumpAndSettle();
    final saveButton = find.widgetWithText(ElevatedButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // Assert the new series confirmation is shown and defaults to checked.
    expect(find.text('Update recurring task'), findsOneWidget);
    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);

    await tester.tap(find.text('Apply changes to entire series'));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(updatedTaskBody, isNotNull);
    expect(updatedTaskBody!['updateSeries'], isFalse);
    expect(find.text('Task updated successfully'), findsOneWidget);
  });
}
