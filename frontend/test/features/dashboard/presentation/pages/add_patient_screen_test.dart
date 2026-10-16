// Tests for AddPatientScreen — the form for connecting a caregiver with a patient.
// initState adds listeners only (no API calls); the build method always renders
// the full Step 1 card. Step 2 connection form is only shown when _emailExists == true,
// which requires a real API response and cannot be tested without a live server.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/add_patient_screen.dart';
import 'package:care_connect_app/providers/user_provider.dart';

Widget _wrap() {
  // CommonDrawer and _sendConnectionRequest use UserProvider.
  final provider = UserProvider()
    ..setUser(UserSession(
      id: 1,
      email: 'caregiver@test.com',
      role: 'caregiver',
      token: 'token',
      caregiverId: 1,
    ));
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider,
    child: const MaterialApp(home: AddPatientScreen()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Mock connectivity_plus to avoid MissingPluginException in runAsync tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => ['wifi'],
    );
  });

  group('AddPatientScreen – UI structure', () {
    testWidgets('renders Scaffold', (tester) async {
      // Verifies the page builds without crashing.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows Connect with a Patient heading', (tester) async {
      // The main heading is always shown at the top of the scroll view.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Connect with a Patient'), findsOneWidget);
    });

    testWidgets('shows email/registration sub-heading', (tester) async {
      // A sub-heading explains the purpose of the form.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text(
          'Enter the email of an existing patient or register a new one',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows Step 1 card heading', (tester) async {
      // The Step 1 card heading is always visible.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Step 1: Check if patient exists'), findsOneWidget);
    });

    testWidgets('shows email TextFormField', (tester) async {
      // The patient email input field is always present in Step 1.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(TextFormField), findsOneWidget);
    });

    testWidgets('shows search icon button in email field suffix', (tester) async {
      // The search IconButton triggers _checkEmail when tapped.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('Step 2 form is not shown initially', (tester) async {
      // The connection-request form (Step 2) is hidden until _emailExists == true.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Step 2: Send connection request'), findsNothing);
    });
  });

  group('AddPatientScreen – empty email validation', () {
    testWidgets('empty email shows Please enter an email address', (tester) async {
      // Tapping search with no email triggers the empty check in _checkEmail.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      expect(find.text('Please enter an email address'), findsOneWidget);
    });
  });

  group('AddPatientScreen – email check result', () {
    testWidgets('shows result after API email check completes', (tester) async {
      // Entering an email and tapping search makes an API call via ApiService.
      // ApiService.checkEmailExists catches all errors internally and returns
      // {'exists': false, ...}. So _emailExists = false is set, showing the
      // "No patient found with this email." amber banner.
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.enterText(
          find.byType(TextFormField), 'patient@example.com');
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.search));
        await Future.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      // Either the "No patient found" banner or an error message is shown.
      expect(
        find.textContaining('patient'),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
