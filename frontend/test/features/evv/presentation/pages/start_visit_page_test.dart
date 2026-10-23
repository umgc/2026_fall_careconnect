// Tests for StartVisitPage
// (lib/features/evv/presentation/pages/start_visit_page.dart).
//
// _isLoading starts true; _loadPatientDetails() uses Provider.of<UserProvider> (try/catch).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/evv/presentation/pages/start_visit_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../../mock_user_provider.dart';

Widget _wrap({int patientId = 1}) {
  final provider = MockUserProvider(mockUser: MockUser(id: 1, role: 'CAREGIVER'));
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: StartVisitPage(patientId: patientId),
    ),
  );
}

void main() {
  group('StartVisitPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(StartVisitPage), findsOneWidget);
    });

    testWidgets('shows "Start Visit" in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Start Visit'), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('renders with different patientId', (tester) async {
      await tester.pumpWidget(_wrap(patientId: 99));
      expect(find.byType(StartVisitPage), findsOneWidget);
    });
  });
}
