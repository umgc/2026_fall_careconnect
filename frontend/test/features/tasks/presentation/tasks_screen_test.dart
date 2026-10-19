// Tests for TasksScreen — displays a patient's task list retrieved from the API.
// With no user in UserProvider, initState's _fetchTasks immediately sets the
// "User not logged in." error and shows it in the body.
// With a real user, the HTTP call returns 400 in tests (TestWidgetsFlutterBinding
// intercepts all HTTP), setting error = "Failed to load tasks: 400".
//
// Scaffold.drawer is lazily inflated — its widget subtree is not built until the
// drawer is opened.  Instead of find.byType(CommonDrawer), we check for
// Icons.menu: Flutter's AppBar automatically adds a hamburger icon when the
// Scaffold has a drawer with no explicit leading widget.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/tasks/presentation/tasks_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

Widget _wrapNullUser(Widget child) {
  // UserProvider with no user set: user == null, triggering "User not logged in."
  final provider = UserProvider();
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

Widget _wrapWithUser(Widget child) {
  // UserProvider with a real user: triggers the HTTP call to getPatientTasks,
  // which returns 400 in tests, setting error = "Failed to load tasks: 400".
  final provider = UserProvider();
  provider.setUser(UserSession(
    id: 1,
    email: 'caregiver@test.com',
    role: 'caregiver',
    token: 'test-token',
    caregiverId: 1,
  ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: MaterialApp(home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Mock connectivity_plus channel to avoid MissingPluginException
    // when UserProvider._initConnectivity is triggered in runAsync tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => ['wifi'],
    );
    // ...and the onConnectivityChanged event channel. Without this the
    // stream's `listen` throws MissingPluginException on Linux CI.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  group('TasksScreen – null user (no login)', () {
    testWidgets('renders Scaffold', (tester) async {
      // Verifies the screen builds without crashing.
      await tester.pumpWidget(_wrapNullUser(
        const TasksScreen(patientId: 1, patientName: 'Test Patient'),
      ));
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows Tasks Dashboard in AppBar', (tester) async {
      // Verifies the AppBar title is "Tasks Dashboard".
      await tester.pumpWidget(_wrapNullUser(
        const TasksScreen(patientId: 1, patientName: 'Test Patient'),
      ));
      await tester.pump();
      expect(find.text('Tasks Dashboard'), findsOneWidget);
    });

    testWidgets('shows User not logged in error after settling',
        (tester) async {
      // With no user in UserProvider, _fetchTasks sets error = "User not logged in."
      // and loading = false; after pumpAndSettle the error text is visible.
      await tester.pumpWidget(_wrapNullUser(
        const TasksScreen(patientId: 1, patientName: 'Test Patient'),
      ));
      await tester.pumpAndSettle();
      expect(find.text('User not logged in.'), findsOneWidget);
    });

    testWidgets('shows FloatingActionButton with add icon', (tester) async {
      // The FAB with an add icon is always present to navigate to task creation.
      await tester.pumpWidget(_wrapNullUser(
        const TasksScreen(patientId: 1, patientName: 'Test Patient'),
      ));
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('AppBar shows drawer hamburger icon', (tester) async {
      // Flutter auto-adds Icons.menu to the AppBar when Scaffold has a drawer
      // and no explicit leading widget — confirming the drawer slot is populated.
      await tester.pumpWidget(_wrapNullUser(
        const TasksScreen(patientId: 1, patientName: 'Test Patient'),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.menu), findsOneWidget);
    });
  });

  group('TasksScreen – with user (API fails)', () {
    testWidgets('shows error text after API fails', (tester) async {
      // With a real user, _fetchTasks makes the HTTP call.
      // TestWidgetsFlutterBinding intercepts HTTP and returns 400, so
      // _fetchTasks sets error = "Failed to load tasks: 400".
      await tester.pumpWidget(_wrapWithUser(
        const TasksScreen(patientId: 1, patientName: 'Test Patient'),
      ));
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      // "Failed to load tasks: 400" contains "load"
      expect(find.textContaining('load'), findsAtLeastNWidgets(1));
    });
  });
}
