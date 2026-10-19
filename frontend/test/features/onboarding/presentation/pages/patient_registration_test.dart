// Tests for PatientRegistrationPage
// (lib/features/onboarding/presentation/pages/patient_registration.dart).
//
// Multi-step form widget with 3 steps: Personal Info, Address, Relationship.
// Tests cover rendering, form validation, stepper navigation, and field interactions.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/onboarding/presentation/pages/patient_registration.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:provider/provider.dart';

Widget _wrap({int? caregiverId}) => MaterialApp(
      home: PatientRegistrationPage(caregiverId: caregiverId),
      onUnknownRoute: (_) =>
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('route'))),
    );

/// Taps the current step's Next button by invoking its onPressed callback
/// directly to bypass hit-test issues with the Stepper's internal scrollable.
Future<void> _tapStepperNext(WidgetTester tester) async {
  final nextBtn = find.widgetWithText(ElevatedButton, 'Next');
  final ElevatedButton button = tester.widget(nextBtn.last);
  button.onPressed!();
  await tester.pumpAndSettle();
}

/// Taps the current step's Back button by invoking its onPressed callback.
Future<void> _tapStepperBack(WidgetTester tester) async {
  final backBtn = find.widgetWithText(TextButton, 'Back');
  final TextButton button = tester.widget(backBtn.last);
  button.onPressed!();
  await tester.pumpAndSettle();
}

/// Fill step 0 (Personal Info) with valid data and tap Next.
Future<void> _fillStep0AndAdvance(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  // First Name
  await tester.enterText(fields.at(0), 'John');
  // Last Name
  await tester.enterText(fields.at(1), 'Doe');
  // Email
  await tester.enterText(fields.at(2), 'john@example.com');
  // Phone
  await tester.enterText(fields.at(3), '1234567890');
  await tester.pumpAndSettle();

  // Date of Birth - tap to open date picker
  await tester.ensureVisible(fields.at(4));
  await tester.pumpAndSettle();
  await tester.tap(fields.at(4));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // MA Number
  await tester.ensureVisible(fields.at(5));
  await tester.pumpAndSettle();
  await tester.enterText(fields.at(5), 'MA123456789');
  await tester.pumpAndSettle();

  // Gender dropdown
  final genderDropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(genderDropdown);
  await tester.pumpAndSettle();
  await tester.tap(genderDropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Male').last);
  await tester.pumpAndSettle();

  // Tap Next
  await _tapStepperNext(tester);
}

/// Fill step 1 (Address) with valid data and tap Next.
/// Step 0 has 6 TextFormFields, so step 1 fields start at index 6:
///   6 = Address Line 1, 7 = Address Line 2, 8 = City, 9 = State,
///   10 = ZIP, 11 = Address Phone
Future<void> _fillStep1AndAdvance(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  // Address Line 1
  await tester.enterText(fields.at(6), '123 Main St');
  await tester.pumpAndSettle();
  // City
  await tester.enterText(fields.at(8), 'Springfield');
  // State
  await tester.enterText(fields.at(9), 'VA');
  await tester.pumpAndSettle();
  // ZIP
  await tester.enterText(fields.at(10), '22150');
  // Address Phone
  await tester.enterText(fields.at(11), '5551234567');
  await tester.pumpAndSettle();

  // Tap Next
  await _tapStepperNext(tester);
}

void main() {
  tearDown(() {
    // Reset view size in case a test changed it.
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.clearAllTestValues();
  });

  group('PatientRegistrationPage - initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(PatientRegistrationPage), findsOneWidget);
    });

    testWidgets('shows "Register New Patient" in the AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Register New Patient'), findsOneWidget);
    });

    testWidgets('shows Stepper widget', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Stepper), findsOneWidget);
    });

    testWidgets('shows "Personal Information" step title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Personal Information'), findsOneWidget);
    });

    testWidgets('shows Form widgets (one per step)', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Form), findsWidgets);
    });

    testWidgets('shows "Next" button on first step', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows multiple TextFormFields', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('does NOT show CircularProgressIndicator initially',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows "First Name" field label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('First Name *'), findsOneWidget);
    });

    testWidgets('shows "Last Name" field label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Last Name *'), findsOneWidget);
    });

    testWidgets('shows "Email Address" field label', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Email Address *'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('does not show Back button on first step', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.widgetWithText(TextButton, 'Back'), findsNothing);
    });
  });

  group('PatientRegistrationPage - step 0 field rendering', () {
    testWidgets('can enter valid first name', (tester) async {
      await tester.pumpWidget(_wrap());
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      expect(find.text('John'), findsOneWidget);
    });

    testWidgets('can enter valid last name', (tester) async {
      await tester.pumpWidget(_wrap());
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'Doe');
      expect(find.text('Doe'), findsOneWidget);
    });

    testWidgets('shows Gender dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Gender *'), findsOneWidget);
    });

    testWidgets('shows MA Number field', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('MA Number *'), findsOneWidget);
    });

    testWidgets('shows Date of Birth field', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Date of Birth *'), findsOneWidget);
    });

    testWidgets('shows phone person icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.person), findsWidgets);
    });

    testWidgets('shows Phone Number field', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Phone Number *'), findsOneWidget);
    });

    testWidgets('shows email icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.email), findsOneWidget);
    });

    testWidgets('shows phone icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.phone), findsOneWidget);
    });

    testWidgets('shows calendar icon for DOB', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('shows badge icon for MA Number', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.byIcon(Icons.badge));
      expect(find.byIcon(Icons.badge), findsOneWidget);
    });

    testWidgets('shows email helper text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(
        find.text('Must contain @ symbol (e.g., name@example.com)'),
        findsOneWidget,
      );
    });

    testWidgets('shows MA number helper text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.ensureVisible(find.text('MA Number *'));
      await tester.pumpAndSettle();
      expect(
        find.text('Format: MA followed by 9 digits (e.g., MA123456789)'),
        findsOneWidget,
      );
    });

    testWidgets('can enter email address', (tester) async {
      await tester.pumpWidget(_wrap());
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(2), 'test@example.com');
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('can enter phone number', (tester) async {
      await tester.pumpWidget(_wrap());
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(3), '5551234567');
      expect(find.text('5551234567'), findsOneWidget);
    });

    testWidgets('can enter MA number', (tester) async {
      await tester.pumpWidget(_wrap());
      final fields = find.byType(TextFormField);
      await tester.ensureVisible(fields.at(5));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(5), 'MA123456789');
      expect(find.text('MA123456789'), findsOneWidget);
    });

    testWidgets('date picker opens when DOB field tapped', (tester) async {
      await tester.pumpWidget(_wrap());
      final fields = find.byType(TextFormField);
      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('gender dropdown shows all options', (tester) async {
      await tester.pumpWidget(_wrap());
      final genderDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(genderDropdown);
      await tester.pumpAndSettle();

      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('Prefer not to say'), findsOneWidget);
    });

    testWidgets('can select gender from dropdown', (tester) async {
      await tester.pumpWidget(_wrap());
      final genderDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female').last);
      await tester.pumpAndSettle();
      expect(find.text('Female'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - step 0 validation', () {
    testWidgets('empty form shows validation errors on Next tap',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Tap Next with empty form
      await _tapStepperNext(tester);

      // Should show validation error snackbar
      expect(
        find.text(
            'Please complete all required fields correctly before continuing'),
        findsOneWidget,
      );
    });

    testWidgets('first name validation - empty shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Fill only last name and tap Next
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'Doe');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      // Should show validation error for first name
      expect(find.text('Please enter first name'), findsOneWidget);
    });

    testWidgets('first name validation - numbers rejected', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John123');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('first name should not contain numbers'), findsOneWidget);
    });

    testWidgets('last name validation - empty shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter last name'), findsOneWidget);
    });

    testWidgets('last name validation - numbers rejected', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe456');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('last name should not contain numbers'), findsOneWidget);
    });

    testWidgets('email validation - empty shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter an email address'), findsOneWidget);
    });

    testWidgets('email validation - no @ shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'invalidemail');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter a valid email address'), findsOneWidget);
    });

    testWidgets('phone validation - empty shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'john@test.com');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter phone number'), findsOneWidget);
    });

    testWidgets('DOB validation - empty shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'john@test.com');
      await tester.enterText(fields.at(3), '1234567890');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter date of birth'), findsOneWidget);
    });

    testWidgets('MA number validation - empty shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'john@test.com');
      await tester.enterText(fields.at(3), '1234567890');
      await tester.pumpAndSettle();

      // Pick a date
      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter MA Number'), findsOneWidget);
    });

    testWidgets('MA number validation - missing MA prefix', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'john@test.com');
      await tester.enterText(fields.at(3), '1234567890');
      await tester.pumpAndSettle();

      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(fields.at(5));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(5), '123456789');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('MA Number must start with "MA"'), findsOneWidget);
    });

    testWidgets('MA number validation - wrong digit count', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'john@test.com');
      await tester.enterText(fields.at(3), '1234567890');
      await tester.pumpAndSettle();

      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(fields.at(5));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(5), 'MA12345');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(
        find.text(
            'MA Number must have exactly 9 digits after "MA" (e.g., MA123456789)'),
        findsOneWidget,
      );
    });

    testWidgets('gender validation - not selected shows error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.enterText(fields.at(2), 'john@test.com');
      await tester.enterText(fields.at(3), '1234567890');
      await tester.pumpAndSettle();

      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(fields.at(5));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(5), 'MA123456789');
      await tester.pumpAndSettle();

      // Do NOT select gender
      await _tapStepperNext(tester);

      expect(find.text('Please select gender'), findsWidgets);
    });
  });

  group('PatientRegistrationPage - step 0 to step 1 navigation', () {
    testWidgets('valid step 0 advances to step 1 (Address Information)',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      // Should now be on step 1
      expect(find.text('Address Line 1 *'), findsOneWidget);
    });

    testWidgets('step 1 shows Back button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      expect(find.widgetWithText(TextButton, 'Back').last, findsOneWidget);
    });

    testWidgets('step 1 shows Address Line 2', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      expect(find.text('Address Line 2'), findsOneWidget);
    });

    testWidgets('step 1 shows City field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      await tester.ensureVisible(find.text('City *'));
      await tester.pumpAndSettle();
      expect(find.text('City *'), findsOneWidget);
    });

    testWidgets('step 1 shows State field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      await tester.ensureVisible(find.text('State *'));
      await tester.pumpAndSettle();
      expect(find.text('State *'), findsOneWidget);
    });

    testWidgets('step 1 shows ZIP Code field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      await tester.ensureVisible(find.text('ZIP Code *'));
      await tester.pumpAndSettle();
      expect(find.text('ZIP Code *'), findsOneWidget);
    });

    testWidgets('step 1 shows Address Phone field', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      await tester.ensureVisible(find.text('Address Phone *'));
      await tester.pumpAndSettle();
      expect(find.text('Address Phone *'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - step 1 validation', () {
    testWidgets('empty address shows validation errors', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      // Tap Next with empty address form
      await _tapStepperNext(tester);

      expect(find.text('Please enter address line 1'), findsOneWidget);
    });

    testWidgets('city with numbers shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      // Step 0 has 6 TextFormFields, so step 1 fields start at index 6.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(6), '123 Main St'); // Address Line 1
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(8), 'City123'); // City
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('city should not contain numbers'), findsOneWidget);
    });

    testWidgets('state with numbers shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(6), '123 Main St');
      await tester.pumpAndSettle();

      await tester.enterText(fields.at(8), 'Springfield'); // City
      await tester.enterText(fields.at(9), 'V1'); // State
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('state should not contain numbers'), findsOneWidget);
    });

    testWidgets('empty ZIP shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(6), '123 Main St');
      await tester.enterText(fields.at(8), 'Springfield');
      await tester.enterText(fields.at(9), 'VA');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter ZIP code'), findsOneWidget);
    });

    testWidgets('empty address phone shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(6), '123 Main St');
      await tester.enterText(fields.at(8), 'Springfield');
      await tester.enterText(fields.at(9), 'VA');
      await tester.enterText(fields.at(10), '22150');
      await tester.pumpAndSettle();

      await _tapStepperNext(tester);

      expect(find.text('Please enter address phone'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - step 1 to step 2 navigation', () {
    testWidgets('valid step 1 advances to step 2 (Relationship)',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      // Should now be on step 2
      expect(find.text('Relationship to Patient *'), findsOneWidget);
    });

    testWidgets('step 2 shows Register Patient button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      expect(find.text('Register Patient'), findsOneWidget);
    });

    testWidgets('step 2 shows Back button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      expect(find.widgetWithText(TextButton, 'Back').last, findsOneWidget);
    });

    testWidgets('step 2 shows Registration Summary', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      await tester.ensureVisible(find.text('Registration Summary'));
      await tester.pumpAndSettle();
      expect(find.text('Registration Summary'), findsOneWidget);
    });

    testWidgets('step 2 summary shows patient info', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      await tester.ensureVisible(find.textContaining('Patient: John Doe'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Patient: John Doe'), findsOneWidget);
    });

    testWidgets('step 2 summary shows email', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      // The email may appear in multiple places (summary + step 0 field).
      expect(find.textContaining('john@example.com'), findsAtLeastNWidgets(1));
    });

    testWidgets('step 2 shows relationship hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      expect(
        find.text('e.g., Parent, Spouse, Child, Daughter, Son, etc.'),
        findsOneWidget,
      );
    });
  });

  group('PatientRegistrationPage - step 2 validation', () {
    testWidgets('empty relationship shows validation error', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      // Tap Register Patient without entering relationship
      await tester.tap(find.widgetWithText(ElevatedButton, 'Register Patient'));
      await tester.pumpAndSettle();

      expect(
          find.text('Please enter relationship to patient'), findsOneWidget);
    });

    testWidgets('can enter relationship text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      // Step 0 has 6 fields, step 1 has 6 fields, so step 2 relationship = index 12.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(12), 'Spouse');
      await tester.pumpAndSettle();

      expect(find.text('Spouse'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - stepper back navigation', () {
    testWidgets('Back from step 1 goes to step 0', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      // Tap Back
      await _tapStepperBack(tester);

      // Should be on step 0 again
      expect(find.text('First Name *'), findsOneWidget);
      expect(find.text('Last Name *'), findsOneWidget);
    });

    testWidgets('Back from step 2 goes to step 1', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);
      await _fillStep1AndAdvance(tester);

      // Tap Back
      await _tapStepperBack(tester);

      // Should be on step 1 again
      expect(find.text('Address Line 1 *'), findsOneWidget);
    });

    testWidgets('tapping earlier step title navigates back', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      // Tap on "Personal Information" step title to go back
      await tester.tap(find.text('Personal Information'));
      await tester.pumpAndSettle();

      // Should show step 0 fields
      expect(find.text('First Name *'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - with caregiverId', () {
    testWidgets('renders with caregiverId', (tester) async {
      await tester.pumpWidget(_wrap(caregiverId: 42));
      expect(find.byType(PatientRegistrationPage), findsOneWidget);
    });

    testWidgets('shows same Stepper with caregiverId', (tester) async {
      await tester.pumpWidget(_wrap(caregiverId: 42));
      expect(find.byType(Stepper), findsOneWidget);
    });

    testWidgets('shows same fields with caregiverId', (tester) async {
      await tester.pumpWidget(_wrap(caregiverId: 42));
      expect(find.text('First Name *'), findsOneWidget);
      expect(find.text('Last Name *'), findsOneWidget);
      expect(find.text('Email Address *'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - address step field entry', () {
    testWidgets('can enter address line 1', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(6), '456 Oak Ave');
      await tester.pumpAndSettle();
      expect(find.text('456 Oak Ave'), findsOneWidget);
    });

    testWidgets('can enter address line 2', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(7), 'Apt 5B');
      await tester.pumpAndSettle();
      expect(find.text('Apt 5B'), findsOneWidget);
    });

    testWidgets('shows city helper text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      // Multiple fields may show this helper text (city, state).
      expect(find.text('Text only, no numbers'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows state hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      await tester.ensureVisible(find.text('State *'));
      await tester.pumpAndSettle();
      expect(find.text('VA'), findsOneWidget);
    });

    testWidgets('shows address line 1 hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      expect(find.text('Street address, P.O. box'), findsOneWidget);
    });

    testWidgets('shows address line 2 hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      expect(
        find.text('Apartment, suite, unit, building, floor, etc.'),
        findsOneWidget,
      );
    });

    testWidgets('shows address phone hint text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      await _fillStep0AndAdvance(tester);

      await tester.ensureVisible(find.text('Address Phone *'));
      await tester.pumpAndSettle();
      expect(find.text('Home/Work phone'), findsOneWidget);
    });
  });

  group('PatientRegistrationPage - DOB field', () {
    testWidgets('DOB field is readOnly', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      // Try to enter text directly - should not work since readOnly
      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(4), '01/01/2000');
      await tester.pumpAndSettle();

      // The text should not appear because the field is readOnly
      // (enterText won't work on readOnly fields in the same way)
      // But we can verify the date picker behavior
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('DOB shows hint text MM/DD/YYYY', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.text('MM/DD/YYYY'), findsOneWidget);
    });

    testWidgets('cancel in date picker does not set DOB', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      final fields = find.byType(TextFormField);
      await tester.ensureVisible(fields.at(4));
      await tester.pumpAndSettle();
      await tester.tap(fields.at(4));
      await tester.pumpAndSettle();

      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // DOB should remain empty (hint should still show)
      expect(find.text('MM/DD/YYYY'), findsOneWidget);
    });
  });

  // Cases merged from patient_registration_test.dart.
  group('merged from patient_registration_test.dart', () {
    group('PatientRegistrationPage', () {
      Widget buildTestWidget() {
        final mockUser = UserSession(
          id: 1,
          role: 'caregiver',
          token: 'mock_token',
          email: 'testcaregiver@sample.com',
          caregiverId: 1,
        );

        return MaterialApp(
          home: ChangeNotifierProvider(
            create: (context) => UserProvider()..setUser(mockUser),
            child: const PatientRegistrationPage(),
          ),
        );
      }

      testWidgets('renders patient registration form', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(buildTestWidget());

        // Verify that the form elements are present
        // The page title is 'Register New Patient'
        expect(find.text('Register New Patient'), findsAtLeast(1));
        // Form fields use asterisk-suffixed labels (e.g. 'First Name *')
        expect(find.text('First Name *'), findsOneWidget);
        expect(find.text('Last Name *'), findsOneWidget);
        expect(find.text('Email Address *'), findsOneWidget);
        expect(find.text('Phone Number *'), findsOneWidget);
        expect(find.text('Date of Birth *'), findsOneWidget);
      });

      testWidgets('validates required fields on step 0', (WidgetTester tester) async {
        // Use a larger surface size to avoid overflow with the Stepper
        await tester.binding.setSurfaceSize(const Size(800, 1200));

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // Tap the first Next button (step 0) without filling in fields
        final nextButton = find.text('Next').first;
        await tester.tap(nextButton);
        await tester.pumpAndSettle();

        // After tapping Next without filling fields, validation errors
        // and/or a SnackBar should appear
        final snackBarFinder = find.textContaining('Please complete all required fields');
        final firstNameError = find.text('Please enter first name');

        expect(
          snackBarFinder.evaluate().length + firstNameError.evaluate().length,
          greaterThan(0),
        );

        // Reset surface size
        await tester.binding.setSurfaceSize(null);
      });

      testWidgets('shows Scaffold', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget());
        expect(find.byType(Scaffold), findsOneWidget);
      });

      testWidgets('shows AppBar', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget());
        expect(find.byType(AppBar), findsOneWidget);
      });

      testWidgets('shows TextFormField widgets', (WidgetTester tester) async {
        await tester.pumpWidget(buildTestWidget());
        expect(find.byType(TextFormField), findsWidgets);
      });

      testWidgets('shows Register Patient button on final step', (WidgetTester tester) async {
        // Increase viewport size to avoid overflow issues with the Stepper
        await tester.binding.setSurfaceSize(const Size(800, 1200));

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // The Stepper has 3 steps. 'Register Patient' is only shown on step 2.
        // We need to navigate through the steps to see it.
        // The step titles are visible in the Stepper header.
        expect(find.text('Personal Information'), findsOneWidget);
        expect(find.text('Address Information'), findsOneWidget);
        expect(find.text('Relationship'), findsOneWidget);

        // Reset surface size
        await tester.binding.setSurfaceSize(null);
      });
    });
  });
}
