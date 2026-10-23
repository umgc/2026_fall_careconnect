// Tests for PatientDashboard from
// lib/features/dashboard/presentation/patient_main_screen.dart.
// Uses Consumer<UserProvider> in build and CommonDrawer needs UserProvider.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/dashboard/presentation/patient_main_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: null);

  @override
  UserSession? get user => null;
}

Widget _wrap() {
  final provider = _NullUserProvider();
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const PatientDashboard(userId: 1),
    ),
  );
}

void main() {
  group('PatientDashboard (patient_main_screen) – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(PatientDashboard), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows Patient Dashboard title', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Patient Dashboard'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows "How are you feeling today?" text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('How are you feeling today?'), findsOneWidget);
    });

    testWidgets('shows greeting with Patient fallback name', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Patient'), findsWidgets);
    });

    testWidgets('shows SafeArea', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('shows SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SingleChildScrollView), findsWidgets);
    });

    testWidgets('shows Divider', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Divider), findsWidgets);
    });
  });
}
