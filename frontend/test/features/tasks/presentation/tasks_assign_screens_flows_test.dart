// TasksScreen and AssignTaskScreen (lib/features/tasks/presentation/) with
// ApiService backed by a MockClient and a GoRouter for navigation: loading
// tasks, deleting one, adding via the FAB, and choosing templates.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/tasks/presentation/assign_task_screen.dart';
import 'package:care_connect_app/features/tasks/presentation/tasks_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../../../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');
const _connectivityStatus =
    MethodChannel('dev.fluttercommunity.plus/connectivity_status');

int _status = 200;
final List<String> _calls = <String>[];

Future<http.Response> _handle(http.Request r) async {
  _calls.add('${r.method} ${r.url.path}');
  if (_status != 200) return http.Response('err', _status);
  if (r.url.path.endsWith('/templates/all')) {
    return http.Response(
      jsonEncode([
        {
          'id': 1,
          'name': 'Hydrate',
          'description': 'Drink water',
          'iconCode': 58144,
          'timeOfDay': '08:30',
        },
        {'id': 2, 'name': 'Rest', 'description': 'Nap', 'iconCode': 1},
      ]),
      200,
    );
  }
  if (r.method == 'DELETE') return http.Response('', 200);
  return http.Response(
    jsonEncode([
      {
        'id': 5,
        'name': 'Walk',
        'description': 'Around the block',
        'date': '2026-10-01T00:00:00',
        'patientId': 1,
      },
    ]),
    200,
  );
}

Widget _app(String initial, {UserProvider? provider}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/tasks',
        builder: (_, __) =>
            const TasksScreen(patientId: 1, patientName: 'Pat'),
      ),
      GoRoute(
        path: '/assign-task',
        builder: (_, __) =>
            const AssignTaskScreen(patientId: 1, patientName: 'Pat'),
      ),
      GoRoute(
        path: '/custom-task-scheduling',
        builder: (_, __) => const Scaffold(body: Text('custom page')),
      ),
      GoRoute(
        path: '/pre-defined-task',
        builder: (_, s) => Scaffold(
            body: Text('template ${s.uri.queryParameters['templateId']}')),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider ?? MockUserProvider(mockUser: MockUser(id: 1)),
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    _status = 200;
    _calls.clear();
    SharedPreferences.setMockInitialValues({'userId': '1'});
    ApiService.debugSetHttpClient(MockClient(_handle));
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secureStorage, (call) async => null);
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockMethodCallHandler(_connectivityStatus, (call) async => null);
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final c in [_secureStorage, _connectivity, _connectivityStatus]) {
      m.setMockMethodCallHandler(c, null);
    }
    ApiService.debugResetHttpClient();
  });

  testWidgets('tasks load, delete asks first, and the FAB opens assign',
      (tester) async {
    await tester.pumpWidget(_app('/tasks'));
    await _settle(tester);
    expect(find.text('Walk'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(_calls.where((c) => c.startsWith('DELETE')), hasLength(1));

    await tester.tap(find.byTooltip('Add task'));
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Assign Task to Pat'), findsOneWidget);
    expect(find.text('Hydrate'), findsOneWidget);

    await tester.tap(find.text('Hydrate'));
    await tester.pumpAndSettle();
    expect(find.text('template 1'), findsOneWidget);
  });

  testWidgets('assign screen opens the custom task page', (tester) async {
    await tester.pumpWidget(_app('/assign-task'));
    await _settle(tester);
    await tester.tap(find.text('Custom Task'));
    await tester.pumpAndSettle();
    expect(find.text('custom page'), findsOneWidget);
  });

  testWidgets('failed loads show the error text', (tester) async {
    _status = 500;
    await tester.pumpWidget(_app('/tasks'));
    await _settle(tester);
    expect(find.text('Failed to load tasks: 500'), findsOneWidget);

    await tester.pumpWidget(_app('/assign-task'));
    await _settle(tester);
    expect(find.text('Failed to load templates: 500'), findsOneWidget);
  });

  testWidgets('tasks screen without a user explains it', (tester) async {
    await tester.pumpWidget(_app('/tasks', provider: _NullUserProvider()));
    await _settle(tester);
    expect(find.text('User not logged in.'), findsOneWidget);
  });
}

class _NullUserProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}
