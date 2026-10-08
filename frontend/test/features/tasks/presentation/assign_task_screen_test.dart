// Tests for AssignTaskScreen
// (lib/features/tasks/presentation/assign_task_screen.dart).
//
// AssignTaskScreen fetches templates in initState with a 30s timeout.
// loading=true → CircularProgressIndicator is shown until API call completes.
// After asserting the loading state, we advance the clock 31 s to trigger the
// timeout, letting the catch block run and clearing the pending timer.
//
// The Scaffold.drawer (CommonDrawer) is lazy — not built on initial render —
// so UserProvider is not required in these tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/tasks/presentation/assign_task_screen.dart';

Widget _wrap({int patientId = 1, String patientName = 'Alice'}) =>
    MaterialApp(
      home: AssignTaskScreen(
        patientId: patientId,
        patientName: patientName,
      ),
    );

// Pump past the 30-second timeout so the pending timer is cleared.
Future<void> _clearTimers(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 31));

void main() {
  group('AssignTaskScreen – initial loading state', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AssignTaskScreen), findsOneWidget);
      await _clearTimers(tester);
    });

    testWidgets('shows patient name in AppBar', (tester) async {
      await tester.pumpWidget(_wrap(patientName: 'Jane Smith'));
      expect(find.textContaining('Jane Smith'), findsOneWidget);
      await _clearTimers(tester);
    });

    testWidgets('shows "Assign Task to" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap(patientName: 'Bob'));
      expect(find.textContaining('Assign Task to Bob'), findsOneWidget);
      await _clearTimers(tester);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      // Check loading spinner BEFORE pumping past the timeout.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _clearTimers(tester);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
      await _clearTimers(tester);
    });

    testWidgets('does NOT show a ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
      await _clearTimers(tester);
    });
  });
}
