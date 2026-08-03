// Tests for PatientVirtualCheckIn (web page)
// (lib/features/health/virtual_check_in/presentation/pages/patient_check_in_page_web.dart).
//
// Loads questionnaire via UserProvider; a logged-out provider avoids HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page_web.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

class _LoggedOutUserProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}

Widget _wrap() => ChangeNotifierProvider<UserProvider>.value(
      value: _LoggedOutUserProvider(),
      child: const MaterialApp(home: PatientVirtualCheckIn()),
    );

Future<void> _pumpSettled(WidgetTester tester) async {
  await tester.pumpWidget(_wrap());
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('PatientVirtualCheckIn – web stub', () {
    testWidgets('renders without crashing', (tester) async {
      await _pumpSettled(tester);
      expect(find.byType(PatientVirtualCheckIn), findsOneWidget);
    });

    testWidgets('shows "Virtual Check-In" in the AppBar', (tester) async {
      await _pumpSettled(tester);
      expect(find.text('Virtual Check-In'), findsOneWidget);
    });

    testWidgets('shows web-only notice text', (tester) async {
      await _pumpSettled(tester);
      expect(
        find.textContaining(
          'Camera recording flow is only available on mobile',
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders a Scaffold', (tester) async {
      await _pumpSettled(tester);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await _pumpSettled(tester);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center widget', (tester) async {
      await _pumpSettled(tester);
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('does NOT show CircularProgressIndicator after load',
        (tester) async {
      await _pumpSettled(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows no-session error when logged out', (tester) async {
      await _pumpSettled(tester);
      expect(find.textContaining('No user session found'), findsOneWidget);
    });
  });
}
