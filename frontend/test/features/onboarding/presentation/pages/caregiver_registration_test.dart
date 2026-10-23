// Tests for CaregiverRegistrationPage
// (lib/features/onboarding/presentation/pages/caregiver_registration.dart).
//
// Pure form widget — no API calls in initState; submission only on button press.
// Tests cover initial render, form fields, checkboxes, and in-line validation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/onboarding/presentation/pages/caregiver_registration.dart';

Widget _wrap() =>
    const MaterialApp(home: CaregiverRegistrationPage());

void main() {
  group('CaregiverRegistrationPage – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CaregiverRegistrationPage), findsOneWidget);
    });

    testWidgets('shows "Caregiver Registration" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Caregiver Registration'), findsOneWidget);
    });

    testWidgets('shows "Register a Caregiver" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Register a Caregiver'), findsOneWidget);
    });

    testWidgets('shows a Form widget', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Form), findsOneWidget);
    });

    testWidgets('shows multiple TextFormFields', (tester) async {
      await tester.pumpWidget(_wrap());
      // Full Name, Email, Phone, City, State, Password, Confirm Password = 7
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('shows "Caregiver Type" section label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Caregiver Type'), findsOneWidget);
    });

    testWidgets('shows "Family Member" checkbox', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Family Member'), findsOneWidget);
    });

    testWidgets('shows "Professional" checkbox', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Professional'), findsOneWidget);
    });

    testWidgets('shows "Register" submit button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('Family Member checkbox is initially checked', (tester) async {
      await tester.pumpWidget(_wrap());
      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).toList();
      // First checkbox is "Family Member" — starts checked.
      expect(checkboxes.first.value, isTrue);
    });

    testWidgets('Professional checkbox is initially unchecked', (tester) async {
      await tester.pumpWidget(_wrap());
      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).toList();
      // Second checkbox is "Professional" — starts unchecked.
      expect(checkboxes.last.value, isFalse);
    });
  });

  group('CaregiverRegistrationPage – checkbox interaction', () {
    testWidgets('tapping Professional checkbox checks it', (tester) async {
      await tester.pumpWidget(_wrap());
      // Ensure the checkbox is visible before tapping (form is in a scroll view).
      await tester.ensureVisible(find.text('Professional'));
      await tester.tap(find.text('Professional'));
      await tester.pump();
      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).toList();
      expect(checkboxes.last.value, isTrue);
    });

    testWidgets('unchecking Family Member auto-checks Professional',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Family Member'));
      // Uncheck "Family Member" (currently checked).
      await tester.tap(find.text('Family Member'));
      await tester.pump();
      final checkboxes = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      ).toList();
      // When both would be unchecked, Professional is forced true.
      expect(checkboxes.last.value, isTrue);
    });
  });

  group('CaregiverRegistrationPage – form fields', () {
    testWidgets('shows Full Name field with helper text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Enter your full name (letters only)'), findsOneWidget);
    });

    testWidgets('shows Email field', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Email'), findsWidgets);
    });

    testWidgets('shows Phone Number field', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Phone Number'), findsOneWidget);
    });

    testWidgets('shows City field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('City'));
      expect(find.text('City'), findsOneWidget);
    });

    testWidgets('shows State field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('State'));
      expect(find.text('State'), findsOneWidget);
    });

    testWidgets('shows Password field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Password'));
      expect(find.text('Password'), findsWidgets);
    });

    testWidgets('shows Confirm Password field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Confirm Password'));
      expect(find.text('Confirm Password'), findsOneWidget);
    });

    testWidgets('shows FilledButton for Register', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Register'));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('shows 7 TextFormFields', (tester) async {
      await tester.pumpWidget(_wrap());
      // Name, Email, Phone, City, State, Password, Confirm Password
      expect(find.byType(TextFormField), findsNWidgets(7));
    });
  });

  group('CaregiverRegistrationPage – form validation', () {
    testWidgets('empty form submit shows error SnackBar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('Register'));
      await tester.pump();
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(
        find.text('Please check the form for errors and complete all required fields'),
        findsOneWidget,
      );
    });

    testWidgets('name with numbers shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      final nameField = find.byType(TextFormField).first;
      await tester.enterText(nameField, 'John123');
      await tester.pump();
      await tester.ensureVisible(find.text('Register'));
      await tester.pump();
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('full name should not contain numbers'), findsOneWidget);
    });

    testWidgets('invalid email shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      final emailField = find.byType(TextFormField).at(1);
      await tester.enterText(emailField, 'notvalid');
      await tester.pump();
      await tester.ensureVisible(find.text('Register'));
      await tester.pump();
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('Please enter a valid email address'), findsWidgets);
    });

    testWidgets('short password shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      final passwordField = find.byType(TextFormField).at(5);
      await tester.enterText(passwordField, 'abc');
      await tester.pump();
      await tester.ensureVisible(find.text('Register'));
      await tester.pump();
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('Password must be at least 9 characters'), findsWidgets);
    });

    testWidgets('password without uppercase shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      final passwordField = find.byType(TextFormField).at(5);
      await tester.enterText(passwordField, 'abcdefgh1!');
      await tester.pump();
      await tester.ensureVisible(find.text('Register'));
      await tester.pump();
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('Password must contain an uppercase letter'), findsWidgets);
    });

    testWidgets('mismatched passwords show error', (tester) async {
      await tester.pumpWidget(_wrap());
      final passwordField = find.byType(TextFormField).at(5);
      final confirmField = find.byType(TextFormField).at(6);
      await tester.enterText(passwordField, 'ValidPass1!');
      await tester.enterText(confirmField, 'DifferentPass1!');
      await tester.pump();
      await tester.ensureVisible(find.text('Register'));
      await tester.pump();
      await tester.tap(find.text('Register'));
      await tester.pump();
      expect(find.text('Passwords do not match'), findsWidgets);
    });
  });

  group('CaregiverRegistrationPage – layout', () {
    testWidgets('shows SafeArea', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('shows SingleChildScrollView', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shows 2 CheckboxListTile widgets', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
    });
  });
}
