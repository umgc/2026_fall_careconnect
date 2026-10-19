// Tests for PatientVirtualCheckIn (web version)
// (lib/features/health/virtual_check_in/presentation/pages/patient_check_in_page_web.dart).
//
// Simple StatelessWidget — no Provider or HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page_web.dart';

Widget _wrap() => const MaterialApp(home: PatientVirtualCheckIn());

void main() {
  group('PatientVirtualCheckIn (web) – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(PatientVirtualCheckIn), findsOneWidget);
    });

    testWidgets('shows "Virtual Check-In" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Virtual Check-In'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows web availability message', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
        find.textContaining('available on mobile apps'),
        findsOneWidget,
      );
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center widget for message', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
