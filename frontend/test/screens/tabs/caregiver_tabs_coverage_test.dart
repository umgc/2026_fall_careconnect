// Coverage tests for the simple caregiver tabs
// (lib/screens/tabs/caregiver_tabs.dart): the Tasks placeholder tab renders
// its labels, and the patients / profile tabs can be constructed at runtime.

// Non-const constructors are used on purpose so the constructors run.
// ignore_for_file: prefer_const_constructors

import 'package:care_connect_app/screens/tabs/caregiver_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Tasks tab shows its title and description', (tester) async {
    await tester.pumpWidget(MaterialApp(home: CaregiverTasksTab()));

    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Task Management'), findsOneWidget);
    expect(find.text('Manage and assign tasks to your patients.'),
        findsOneWidget);
    expect(find.byIcon(Icons.assignment), findsOneWidget);
  });

  test('patients and profile tabs are stateless widgets', () {
    expect(CaregiverPatientsTab(), isA<StatelessWidget>());
    expect(CaregiverProfileTab(), isA<StatelessWidget>());
  });
}
