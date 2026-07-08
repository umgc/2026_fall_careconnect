// Tests for RegistrationPage
// (lib/features/auth/presentation/pages/sign_up_screen.dart).
//
// Multi-step registration form — no API calls in initState.
// Tests cover all 5 steps, form validation, password visibility, and role selection.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/auth/presentation/pages/sign_up_screen.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_http_overrides.dart';

/// Wraps RegistrationPage in a GoRouter so that context.go('/login') works.
Widget _wrap({String? initialRole, bool lockRole = false, double width = 800}) {
  final router = GoRouter(
    initialLocation: '/signup',
    routes: [
      GoRoute(
        path: '/signup',
        builder: (context, state) => RegistrationPage(
          initialRole: initialRole,
          lockRole: lockRole,
          skipEmailVerification: true,
        ),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            const Scaffold(body: Text('Login Page')),
      ),
      GoRoute(
        path: '/select-subscription-tier',
        builder: (context, state) =>
            const Scaffold(body: Text('Subscription Tier')),
      ),
    ],
  );

  return MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: MaterialApp.router(
      routerConfig: router,
    ),
  );
}

/// Go to step 1 using a preselected role (avoids dropdown interaction issues).
Future<void> _goToStep1(WidgetTester tester, {String role = 'Patient'}) async {
  await tester.pumpWidget(_wrap(initialRole: role));
  await tester.pump();
  await tester.pump();
  // Scroll to the Next button which may be off-screen
  await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Next'));
  await tester.pump();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Next'));
  await tester.pump();
  await tester.pump();
}

/// Helper to scroll to and tap the Next/Sign Up button.
Future<void> _tapNextButton(WidgetTester tester) async {
  // Try Next first, then Sign Up
  final nextFinder = find.widgetWithText(ElevatedButton, 'Next');
  if (nextFinder.evaluate().isNotEmpty) {
    await tester.ensureVisible(nextFinder);
    await tester.pump();
    await tester.tap(nextFinder);
  } else {
    final signUpFinder = find.widgetWithText(ElevatedButton, 'Sign Up');
    await tester.ensureVisible(signUpFinder);
    await tester.pump();
    await tester.tap(signUpFinder);
  }
  await tester.pump();
  await tester.pump();
}

/// Fills in step 1 (Personal Information) for Patient role.
Future<void> _fillPersonalInfo(WidgetTester tester) async {
  final fields = find.byType(TextFormField);

  // First Name
  await tester.enterText(fields.at(0), 'John');
  // Last Name
  await tester.enterText(fields.at(1), 'Doe');
  await tester.pump();

  // Date of Birth - tap the date field to open date picker
  await tester.ensureVisible(fields.at(2));
  await tester.pump();
  await tester.tap(fields.at(2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // Select gender dropdown
  final genderDropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(genderDropdown);
  await tester.pump();
  await tester.tap(genderDropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Male').last);
  await tester.pumpAndSettle();
}

/// Fills in step 1 for Caregiver role (includes caregiver type).
Future<void> _fillCaregiverPersonalInfo(WidgetTester tester,
    {String caregiverType = 'Family Member'}) async {
  final fields = find.byType(TextFormField);

  // First Name
  await tester.enterText(fields.at(0), 'Jane');
  // Last Name
  await tester.enterText(fields.at(1), 'Nurse');
  await tester.pump();

  // Date of Birth - tap the date field to open date picker
  await tester.ensureVisible(fields.at(2));
  await tester.pump();
  await tester.tap(fields.at(2));
  await tester.pumpAndSettle();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();

  // Select gender dropdown (first dropdown)
  final genderDropdown = find.byType(DropdownButtonFormField<String>).first;
  await tester.ensureVisible(genderDropdown);
  await tester.pump();
  await tester.tap(genderDropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Female').last);
  await tester.pumpAndSettle();

  // Select caregiver type dropdown (second dropdown)
  final caregiverTypeDropdown =
      find.byType(DropdownButtonFormField<String>).last;
  await tester.ensureVisible(caregiverTypeDropdown);
  await tester.pump();
  await tester.tap(caregiverTypeDropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(caregiverType).last);
  await tester.pumpAndSettle();
}

/// Go to step 2 (Contact Information).
Future<void> _goToStep2(WidgetTester tester) async {
  await _goToStep1(tester);
  await _fillPersonalInfo(tester);
  await _tapNextButton(tester);
}

/// Fill step 2 (Contact Information) with valid data.
Future<void> _fillContactInfo(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'test@example.com');
  await tester.enterText(fields.at(1), '1234567890');
  await tester.pump();

  // Scroll down to see address fields
  await tester.ensureVisible(fields.at(2));
  await tester.pump();
  await tester.enterText(fields.at(2), '123 Main St');
  await tester.pump();

  await tester.ensureVisible(fields.at(4));
  await tester.pump();
  await tester.enterText(fields.at(4), 'Springfield');
  await tester.enterText(fields.at(5), 'IL');
  await tester.enterText(fields.at(6), '62701');
  await tester.pump();
}

/// Go to step 3 (Security).
Future<void> _goToStep3(WidgetTester tester) async {
  await _goToStep2(tester);
  await _fillContactInfo(tester);
  await _tapNextButton(tester);
}

/// Go to step 4 (Review).
Future<void> _goToStep4(WidgetTester tester) async {
  await _goToStep3(tester);
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Password123');
  await tester.enterText(fields.at(1), 'Password123');
  await tester.pump();
  await _tapNextButton(tester);
}

/// Navigate a (non-professional) Caregiver all the way to the review step.
Future<void> _goToCaregiverReview(WidgetTester tester) async {
  await _goToStep1(tester, role: 'Caregiver'); // pumps widget; step 0 -> step 1
  await _fillCaregiverPersonalInfo(tester, caregiverType: 'Family Member');
  await _tapNextButton(tester); // step 1 -> step 2 (Contact)
  await _fillContactInfo(tester);
  await _tapNextButton(tester); // step 2 -> step 3 (Security)
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'Password123');
  await tester.enterText(fields.at(1), 'Password123');
  await tester.pump();
  await _tapNextButton(tester); // step 3 -> step 4 (Review)
}

void main() {
  // RegistrationPage builds AppConfig.getGooglePlacesApiKey(), which reads
  // dotenv.env. Without this, every build throws NotInitializedError.
  setUpAll(() {
    dotenv.loadFromString(
      mergeWith: {'GOOGLE_PLACES_API_KEY': 'test_key'},
      isOptional: true,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  group('RegistrationPage - initial render (step 0)', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(RegistrationPage), findsOneWidget);
    });

    testWidgets('shows "Create Your CareConnect Account" title',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Create Your CareConnect Account'), findsOneWidget);
    });

    testWidgets('shows "Join our secure healthcare platform" subtitle',
        (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Join our secure healthcare platform'), findsOneWidget);
    });

    testWidgets('shows progress heading "Step 1 of"', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.textContaining('Step 1 of'), findsOneWidget);
    });

    testWidgets('shows "Account Role" step label at step 0', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Account Role'), findsOneWidget);
    });

    testWidgets('shows "Back to Login" text button at step 0', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Back to Login'), findsOneWidget);
    });

    testWidgets('shows "Next" button', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Next'), findsOneWidget);
    });

    testWidgets('shows a Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('RegistrationPage - with preselected role', () {
    testWidgets('renders without crashing with Patient role', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.byType(RegistrationPage), findsOneWidget);
    });

    testWidgets('renders without crashing with Caregiver role',
        (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Caregiver'));
      await tester.pump();
      expect(find.byType(RegistrationPage), findsOneWidget);
    });

    testWidgets('shows role description when Patient is preselected',
        (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.textContaining('track your health'), findsOneWidget);
    });

    testWidgets('shows role description when Caregiver is preselected',
        (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Caregiver'));
      await tester.pump();
      expect(find.textContaining('monitor and assist'), findsOneWidget);
    });
  });

  group('RegistrationPage - step 0 UI elements', () {
    testWidgets('shows "Who is this account for?" heading', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Who is this account for?'), findsOneWidget);
    });

    testWidgets('shows "Account Role *" label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.text('Account Role *'), findsOneWidget);
    });

    testWidgets('shows both role option cards', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Role is chosen via two tappable cards, not a dropdown.
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('Caregiver'), findsOneWidget);
      expect(find.text('Managing my own health'), findsOneWidget);
      expect(find.text('Caring for someone else'), findsOneWidget);
    });

    testWidgets('shows role description text', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(
        find.text(
            'Choose the role that best describes your relationship to healthcare management'),
        findsOneWidget,
      );
    });

    testWidgets('shows role card icons', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Each role card renders its icon (Patient = person, Caregiver = favorite).
      expect(find.byIcon(Icons.person), findsWidgets);
      expect(find.byIcon(Icons.favorite), findsWidgets);
    });

    testWidgets('shows SafeArea', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SafeArea), findsWidgets);
    });
  });

  group('RegistrationPage - lockRole', () {
    testWidgets('renders with lockRole=true and Patient role', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient', lockRole: true));
      await tester.pump();
      expect(find.byType(RegistrationPage), findsOneWidget);
    });

    testWidgets('role cards are disabled when lockRole=true', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient', lockRole: true));
      await tester.pump();
      // Tapping a different role must not change the locked selection.
      await tester.ensureVisible(find.text('Caregiver'));
      await tester.tap(find.text('Caregiver'), warnIfMissed: false);
      await tester.pump();
      expect(find.textContaining('track your health'), findsOneWidget);
      expect(find.textContaining('monitor and assist'), findsNothing);
    });
  });

  group('RegistrationPage - Next button state', () {
    testWidgets('Next button is present at step 0', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.widgetWithText(ElevatedButton, 'Next'), findsOneWidget);
    });

    testWidgets('selecting a role shows its description', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.ensureVisible(find.text('Patient'));
      await tester.tap(find.text('Patient'));
      await tester.pump();
      expect(find.textContaining('track your health'), findsOneWidget);
    });

    testWidgets('Next button disabled when no role selected', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next button enabled when role is selected', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('RegistrationPage - progress indicator', () {
    testWidgets('progress shows 20% at step 0', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.text('20% Complete'), findsOneWidget);
    });

    testWidgets('progress shows 40% at step 1', (tester) async {
      await _goToStep1(tester);
      expect(find.text('40% Complete'), findsOneWidget);
    });
  });

  group('RegistrationPage - step 1 (Personal Information)', () {
    testWidgets('shows Personal Information heading', (tester) async {
      await _goToStep1(tester);
      expect(find.text('Personal Information'), findsOneWidget);
      expect(find.text('Enter your basic details'), findsOneWidget);
    });

    testWidgets('shows First Name field', (tester) async {
      await _goToStep1(tester);
      expect(find.text('First Name *'), findsOneWidget);
    });

    testWidgets('shows Last Name field', (tester) async {
      await _goToStep1(tester);
      expect(find.text('Last Name *'), findsOneWidget);
    });

    testWidgets('shows Date of Birth field', (tester) async {
      await _goToStep1(tester);
      expect(find.text('Date of Birth *'), findsOneWidget);
    });

    testWidgets('shows Gender dropdown', (tester) async {
      await _goToStep1(tester);
      expect(find.text('Gender *'), findsOneWidget);
    });

    testWidgets('shows Previous button', (tester) async {
      await _goToStep1(tester);
      expect(find.text('Previous'), findsOneWidget);
    });

    testWidgets('shows Step 2 of 5', (tester) async {
      await _goToStep1(tester);
      expect(find.text('Step 2 of 5'), findsOneWidget);
    });

    testWidgets('can enter text in first name', (tester) async {
      await _goToStep1(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Alice');
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('can enter text in last name', (tester) async {
      await _goToStep1(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), 'Smith');
      await tester.pump();
      expect(find.text('Smith'), findsOneWidget);
    });

    testWidgets('Next disabled when fields are empty', (tester) async {
      await _goToStep1(tester);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows Caregiver Type when Caregiver selected', (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      expect(find.text('Caregiver Type *'), findsOneWidget);
    });

    testWidgets('calendar icon is present for DOB field', (tester) async {
      await _goToStep1(tester);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('Previous goes back to step 0', (tester) async {
      await _goToStep1(tester);
      await tester.tap(find.text('Previous'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Account Role'), findsOneWidget);
      expect(find.text('Step 1 of 5'), findsOneWidget);
    });

    testWidgets('date picker opens when DOB field tapped', (tester) async {
      await _goToStep1(tester);
      final fields = find.byType(TextFormField);
      await tester.tap(fields.at(2));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('selecting gender from dropdown', (tester) async {
      await _goToStep1(tester);
      final genderDropdown = find.byType(DropdownButtonFormField<String>);
      expect(genderDropdown, findsOneWidget);
      await tester.tap(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female').last);
      await tester.pumpAndSettle();
      expect(find.text('Female'), findsOneWidget);
    });

    testWidgets('Next disabled when only first name is filled',
        (tester) async {
      await _goToStep1(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next enabled when all personal info filled', (tester) async {
      await _goToStep1(tester);
      await _fillPersonalInfo(tester);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'form validation shows errors when Next tapped with empty fields',
        (tester) async {
      await _goToStep1(tester);
      // Enter first name only and try to proceed
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'John');
      await tester.pump();

      // Still can't proceed without DOB and gender
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('date picker cancel does not set date', (tester) async {
      await _goToStep1(tester);
      final fields = find.byType(TextFormField);
      await tester.tap(fields.at(2));
      await tester.pumpAndSettle();
      // Tap Cancel instead of OK
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      // DOB field should still be empty, Next should remain disabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('selecting Other gender works', (tester) async {
      await _goToStep1(tester);
      final genderDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('selecting Prefer not to say gender works', (tester) async {
      await _goToStep1(tester);
      final genderDropdown = find.byType(DropdownButtonFormField<String>);
      await tester.tap(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prefer not to say').last);
      await tester.pumpAndSettle();
      expect(find.text('Prefer not to say'), findsOneWidget);
    });
  });

  group('RegistrationPage - step 2 (Contact Information)', () {
    testWidgets('shows Contact Information heading', (tester) async {
      await _goToStep2(tester);
      expect(find.text('Contact Information'), findsOneWidget);
      expect(
          find.text('Provide your contact details and address'), findsOneWidget);
    });

    testWidgets('shows email, phone, and address fields', (tester) async {
      await _goToStep2(tester);
      expect(find.text('Email Address *'), findsOneWidget);
      expect(find.text('Phone Number *'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
      expect(find.text('Address Line 1'), findsOneWidget);
    });

    testWidgets('shows Step 3 of 5', (tester) async {
      await _goToStep2(tester);
      expect(find.text('Step 3 of 5'), findsOneWidget);
    });

    testWidgets('shows Address Line 2 (Optional)', (tester) async {
      await _goToStep2(tester);

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();

      expect(find.text('Address Line 2 (Optional)'), findsOneWidget);
    });

    testWidgets('can enter email', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.pump();
      expect(find.text('test@example.com'), findsOneWidget);
    });

    testWidgets('Next disabled with empty fields', (tester) async {
      await _goToStep2(tester);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled with invalid email', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'invalidemail');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();

      // Even with phone filled, invalid email should keep Next disabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows city/state/zip fields', (tester) async {
      await _goToStep2(tester);

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();

      expect(find.text('City *'), findsOneWidget);
      expect(find.text('State *'), findsOneWidget);
      expect(find.text('ZIP Code *'), findsOneWidget);
    });

    testWidgets('60% Complete at step 2', (tester) async {
      await _goToStep2(tester);
      expect(find.text('60% Complete'), findsOneWidget);
    });

    testWidgets('Next disabled when only email and phone filled',
        (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      // Missing address fields
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('can fill address line 2', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      // Address Line 2 is at index 3
      await tester.ensureVisible(fields.at(3));
      await tester.pump();
      await tester.enterText(fields.at(3), 'Apt 4B');
      await tester.pump();
      expect(find.text('Apt 4B'), findsOneWidget);
    });

    testWidgets('Next enabled when all contact fields filled', (tester) async {
      await _goToStep2(tester);
      await _fillContactInfo(tester);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('RegistrationPage - step 3 (Security)', () {
    testWidgets('shows Security Setup heading', (tester) async {
      await _goToStep3(tester);
      expect(find.text('Security Setup'), findsOneWidget);
      expect(
        find.text('Set up your password to secure your account'),
        findsOneWidget,
      );
    });

    testWidgets('shows password and confirm password fields', (tester) async {
      await _goToStep3(tester);
      expect(find.text('Password *'), findsOneWidget);
      expect(find.text('Confirm Password *'), findsOneWidget);
    });

    testWidgets('shows password requirements', (tester) async {
      await _goToStep3(tester);
      expect(find.text('Password Requirements:'), findsOneWidget);
      expect(find.textContaining('At least 8 characters'), findsOneWidget);
    });

    testWidgets('shows Step 4 of 5', (tester) async {
      await _goToStep3(tester);
      expect(find.text('Step 4 of 5'), findsOneWidget);
    });

    testWidgets('password visibility toggle works', (tester) async {
      await _goToStep3(tester);
      // Initially passwords are hidden
      expect(find.byIcon(Icons.visibility_off), findsNWidgets(2));

      // Tap the first visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pump();

      // One should now be visible
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('confirm password visibility toggle works', (tester) async {
      await _goToStep3(tester);
      // Tap the second visibility toggle
      await tester.tap(find.byIcon(Icons.visibility_off).last);
      await tester.pump();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
    });

    testWidgets('can enter password', (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Password123');
      await tester.pump();
      expect(find.text('Password123'), findsOneWidget);
    });

    testWidgets('Next disabled with short password', (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'short');
      await tester.enterText(fields.at(1), 'short');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled when passwords mismatch', (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Password123');
      await tester.enterText(fields.at(1), 'DifferentPass');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next enabled when passwords match and >= 8 chars',
        (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Password123');
      await tester.enterText(fields.at(1), 'Password123');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Next disabled with empty password', (tester) async {
      await _goToStep3(tester);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('80% Complete at step 3', (tester) async {
      await _goToStep3(tester);
      expect(find.text('80% Complete'), findsOneWidget);
    });

    testWidgets('both password toggles can be toggled on', (tester) async {
      await _goToStep3(tester);
      // Toggle both visibility icons
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.visibility_off).first);
      await tester.pump();
      // Both should be visible now
      expect(find.byIcon(Icons.visibility), findsNWidgets(2));
    });

    testWidgets('password requirement mentions symbols', (tester) async {
      await _goToStep3(tester);
      expect(find.textContaining('symbols'), findsOneWidget);
    });

    testWidgets('Next disabled when only password filled but not confirm',
        (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Password123');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('RegistrationPage - step 4 (Review)', () {
    testWidgets('shows Review & Confirm heading', (tester) async {
      await _goToStep4(tester);
      expect(find.text('Review & Confirm'), findsOneWidget);
    });

    testWidgets('shows review information labels', (tester) async {
      await _goToStep4(tester);
      expect(find.text('Account Type'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('shows Sign Up instead of Next', (tester) async {
      await _goToStep4(tester);
      expect(find.text('Sign Up'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Next'), findsNothing);
    });

    testWidgets('shows Step 5 of 5 and 100% Complete', (tester) async {
      await _goToStep4(tester);
      expect(find.text('Step 5 of 5'), findsOneWidget);
      expect(find.text('100% Complete'), findsOneWidget);
    });

    testWidgets('shows filled-in data in review', (tester) async {
      await _goToStep4(tester);
      expect(find.text('Patient'), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
    });

    testWidgets('shows terms notice', (tester) async {
      await _goToStep4(tester);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(find.textContaining('Terms of Service'), findsOneWidget);
    });

    testWidgets('shows review subtitle', (tester) async {
      await _goToStep4(tester);
      expect(
        find.text(
            'Please review your information before creating your account'),
        findsOneWidget,
      );
    });

    testWidgets('shows Phone and Date of Birth labels', (tester) async {
      await _goToStep4(tester);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
    });

    testWidgets('shows Gender and Address labels', (tester) async {
      await _goToStep4(tester);

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();

      expect(find.text('Gender'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
    });

    testWidgets('shows check icon on Sign Up button', (tester) async {
      await _goToStep4(tester);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('shows info_outline icon in terms notice', (tester) async {
      await _goToStep4(tester);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('shows Privacy Policy text', (tester) async {
      await _goToStep4(tester);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(find.textContaining('Privacy Policy'), findsOneWidget);
    });

    testWidgets('shows John Doe as name', (tester) async {
      await _goToStep4(tester);
      expect(find.text('John Doe'), findsOneWidget);
    });

    testWidgets('shows Male as gender', (tester) async {
      await _goToStep4(tester);
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();
      expect(find.text('Male'), findsOneWidget);
    });
  });

  group('RegistrationPage - navigation back through steps', () {
    testWidgets('Previous from step 1 goes back to step 0', (tester) async {
      await _goToStep1(tester);
      await tester.tap(find.text('Previous'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Account Role'), findsOneWidget);
    });

    testWidgets('Previous from step 2 goes back to step 1', (tester) async {
      await _goToStep2(tester);
      await tester.ensureVisible(find.text('Previous'));
      await tester.pump();
      await tester.tap(find.text('Previous'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Personal Information'), findsOneWidget);
      expect(find.text('Step 2 of 5'), findsOneWidget);
    });

    testWidgets('Previous from step 3 goes back to step 2', (tester) async {
      await _goToStep3(tester);
      await tester.ensureVisible(find.text('Previous'));
      await tester.pump();
      await tester.tap(find.text('Previous'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Contact Information'), findsOneWidget);
      expect(find.text('Step 3 of 5'), findsOneWidget);
    });

    testWidgets('Previous from step 4 goes back to step 3', (tester) async {
      await _goToStep4(tester);
      await tester.ensureVisible(find.text('Previous'));
      await tester.pump();
      await tester.tap(find.text('Previous'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Security Setup'), findsOneWidget);
      expect(find.text('Step 4 of 5'), findsOneWidget);
    });
  });

  group('RegistrationPage - Caregiver flow', () {
    testWidgets('Caregiver step 1 shows Caregiver Type dropdown',
        (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      expect(find.text('Caregiver Type *'), findsOneWidget);
      // Should have two DropdownButtonFormFields: Gender and Caregiver Type
      expect(
          find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    });

    testWidgets('Caregiver Next disabled without caregiver type',
        (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Jane');
      await tester.enterText(fields.at(1), 'Nurse');
      await tester.pump();

      // Set DOB
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.tap(fields.at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Set gender
      final genderDropdown =
          find.byType(DropdownButtonFormField<String>).first;
      await tester.tap(genderDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female').last);
      await tester.pumpAndSettle();

      // Should still be disabled because caregiver type not selected
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Caregiver Next enabled with all fields including caregiver type',
        (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      await _fillCaregiverPersonalInfo(tester);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'Professional caregiver shows license fields on contact step',
        (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      await _fillCaregiverPersonalInfo(tester, caregiverType: 'Professional');
      await _tapNextButton(tester);

      // Should be on step 2 (Contact Information) now
      expect(find.text('Contact Information'), findsOneWidget);

      // Scroll down to see professional fields
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -500));
      await tester.pump();

      expect(find.text('Professional Information'), findsOneWidget);
      expect(find.text('License Number *'), findsOneWidget);
      expect(find.text('Issuing State *'), findsOneWidget);
      expect(find.text('Years of Experience *'), findsOneWidget);
    });

    testWidgets('Professional caregiver Next disabled without license info',
        (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      await _fillCaregiverPersonalInfo(tester, caregiverType: 'Professional');
      await _tapNextButton(tester);

      // Fill basic contact info only
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'jane@example.com');
      await tester.enterText(fields.at(1), '5551234567');
      await tester.pump();

      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '456 Oak Ave');
      await tester.pump();

      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'Baltimore');
      await tester.enterText(fields.at(5), 'MD');
      await tester.enterText(fields.at(6), '21201');
      await tester.pump();

      // Still disabled because professional fields are empty
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('RegistrationPage - mobile layout', () {
    testWidgets('renders in mobile layout (width < 600)', (tester) async {
      await tester.pumpWidget(_wrap(width: 400));
      await tester.pump();
      expect(find.byType(RegistrationPage), findsOneWidget);
      expect(
          find.text('Create Your CareConnect Account'), findsOneWidget);
    });

    testWidgets('renders in desktop layout (width >= 600)', (tester) async {
      await tester.pumpWidget(_wrap(width: 800));
      await tester.pump();
      expect(find.byType(RegistrationPage), findsOneWidget);
      expect(
          find.text('Create Your CareConnect Account'), findsOneWidget);
    });
  });

  group('RegistrationPage - Back to Login', () {
    testWidgets('Back to Login navigates to /login', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // Ensure the button is visible first
      final backBtn = find.text('Back to Login');
      await tester.ensureVisible(backBtn);
      await tester.pump();
      await tester.tap(backBtn);
      await tester.pumpAndSettle();

      // Should navigate to the login page
      expect(find.text('Login Page'), findsOneWidget);
    });
  });

  group('RegistrationPage - step title icons', () {
    testWidgets('step 0 shows person icon', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.byIcon(Icons.person), findsWidgets);
    });

    testWidgets('step 1 shows edit_document icon', (tester) async {
      await _goToStep1(tester);
      expect(find.byIcon(Icons.edit_document), findsOneWidget);
    });

    testWidgets('step 2 shows edit_document icon', (tester) async {
      await _goToStep2(tester);
      expect(find.byIcon(Icons.edit_document), findsOneWidget);
    });

    testWidgets('step 3 shows edit_document icon', (tester) async {
      await _goToStep3(tester);
      expect(find.byIcon(Icons.edit_document), findsOneWidget);
    });
  });

  group('RegistrationPage - arrow icons on buttons', () {
    testWidgets('Next button shows arrow_forward icon', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('Previous/Back button shows arrow_back icon', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });
  });

  group('RegistrationPage - review step with address line 2', () {
    testWidgets('review shows address with line 2 when filled',
        (tester) async {
      // Go through the full flow but fill address line 2
      await _goToStep1(tester);
      await _fillPersonalInfo(tester);
      await _tapNextButton(tester);

      // Fill contact info with address line 2
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '123 Main St');
      // Address Line 2
      await tester.ensureVisible(fields.at(3));
      await tester.pump();
      await tester.enterText(fields.at(3), 'Apt 5');
      await tester.pump();
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'Springfield');
      await tester.enterText(fields.at(5), 'IL');
      await tester.enterText(fields.at(6), '62701');
      await tester.pump();

      await _tapNextButton(tester);

      // Security step
      final secFields = find.byType(TextFormField);
      await tester.enterText(secFields.at(0), 'Password123');
      await tester.enterText(secFields.at(1), 'Password123');
      await tester.pump();
      await _tapNextButton(tester);

      // Review step - scroll to see address
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -200));
      await tester.pump();

      // Address should contain Apt 5
      expect(find.textContaining('Apt 5'), findsOneWidget);
    });
  });

  group('RegistrationPage - Caregiver review step', () {
    testWidgets('Caregiver review shows Caregiver Type label',
        (tester) async {
      // Full caregiver flow
      await _goToStep1(tester, role: 'Caregiver');
      await _fillCaregiverPersonalInfo(tester);
      await _tapNextButton(tester);

      // Contact info
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'jane@example.com');
      await tester.enterText(fields.at(1), '5551234567');
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '456 Oak Ave');
      await tester.pump();
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'Baltimore');
      await tester.enterText(fields.at(5), 'MD');
      await tester.enterText(fields.at(6), '21201');
      await tester.pump();
      await _tapNextButton(tester);

      // Security
      final secFields = find.byType(TextFormField);
      await tester.enterText(secFields.at(0), 'Password123');
      await tester.enterText(secFields.at(1), 'Password123');
      await tester.pump();
      await _tapNextButton(tester);

      // Review step
      expect(find.text('Review & Confirm'), findsOneWidget);
      expect(find.text('Caregiver'), findsOneWidget);
      expect(find.text('Caregiver Type'), findsOneWidget);
      expect(find.text('Family Member'), findsOneWidget);
    });
  });

  group('RegistrationPage - form validation on step 1 submit', () {
    testWidgets('form validation triggers on Next with partial data',
        (tester) async {
      await _goToStep1(tester);
      final fields = find.byType(TextFormField);
      // Fill first name and last name but not DOB/gender
      await tester.enterText(fields.at(0), 'John');
      await tester.enterText(fields.at(1), 'Doe');
      await tester.pump();

      // DOB and gender empty, so button is disabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('filling all step 1 fields enables Next', (tester) async {
      await _goToStep1(tester);
      await _fillPersonalInfo(tester);

      await tester.ensureVisible(
          find.widgetWithText(ElevatedButton, 'Next'));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('RegistrationPage - SingleChildScrollView', () {
    testWidgets('has SingleChildScrollView for scrollability', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });
  });

  group('RegistrationPage - logo and image', () {
    testWidgets('has ClipRRect for logo', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('logo image widget is present', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();
      // Image.asset is used for the logo
      expect(find.byType(Image), findsWidgets);
    });
  });

  group('RegistrationPage - step label text', () {
    testWidgets('step 0 shows "Account Role" label', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.text('Account Role'), findsOneWidget);
    });

    testWidgets('step 1 shows step 2 label text', (tester) async {
      await _goToStep1(tester);
      // The step title area shows "Step 2" and progress shows "Step 2 of 5"
      expect(find.textContaining('Step 2'), findsWidgets);
    });

    testWidgets('step 2 shows step 3 label text', (tester) async {
      await _goToStep2(tester);
      expect(find.textContaining('Step 3'), findsWidgets);
    });

    testWidgets('step 3 shows step 4 label text', (tester) async {
      await _goToStep3(tester);
      expect(find.textContaining('Step 4'), findsWidgets);
    });

    testWidgets('step 4 shows step 5 label text', (tester) async {
      await _goToStep4(tester);
      expect(find.textContaining('Step 5'), findsWidgets);
    });
  });

  group('RegistrationPage - role card selection', () {
    testWidgets('can select Patient via role card', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // Tap the Patient role card.
      await tester.ensureVisible(find.text('Patient'));
      await tester.tap(find.text('Patient'));
      await tester.pumpAndSettle();

      // Should show Patient role description
      expect(find.textContaining('track your health'), findsOneWidget);

      // Next should be enabled now
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('can select Caregiver via role card', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      // Tap the Caregiver role card.
      await tester.ensureVisible(find.text('Caregiver'));
      await tester.tap(find.text('Caregiver'));
      await tester.pumpAndSettle();

      // Should show Caregiver role description
      expect(find.textContaining('monitor and assist'), findsOneWidget);

      // Next should be enabled
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('RegistrationPage - form validation error messages on step 1', () {
    testWidgets('shows first name required when cleared after filling',
        (tester) async {
      await _goToStep1(tester);
      await _fillPersonalInfo(tester);

      // Clear first name
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '');
      await tester.pump();

      // Next should be disabled because _canProceed checks non-empty
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows last name required when cleared after filling',
        (tester) async {
      await _goToStep1(tester);
      await _fillPersonalInfo(tester);

      // Clear last name
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(1), '');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('step 1 validation fires when Next tapped with valid data',
        (tester) async {
      await _goToStep1(tester);
      await _fillPersonalInfo(tester);

      // Tap Next - this triggers _formKey.currentState!.validate()
      await _tapNextButton(tester);

      // Should advance to step 2
      expect(find.text('Contact Information'), findsOneWidget);
    });
  });

  group('RegistrationPage - step 2 email validation edge cases', () {
    testWidgets('Next disabled with email missing @ symbol', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'userexample.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '123 Main St');
      await tester.pump();
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'City');
      await tester.enterText(fields.at(5), 'ST');
      await tester.enterText(fields.at(6), '12345');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled when address line 1 is empty', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      // Skip address line 1
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'City');
      await tester.enterText(fields.at(5), 'ST');
      await tester.enterText(fields.at(6), '12345');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled when city is empty', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '123 Main St');
      await tester.pump();
      await tester.ensureVisible(fields.at(5));
      await tester.pump();
      // Skip city
      await tester.enterText(fields.at(5), 'ST');
      await tester.enterText(fields.at(6), '12345');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled when state is empty', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '123 Main St');
      await tester.pump();
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'City');
      // Skip state
      await tester.enterText(fields.at(6), '12345');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled when zip is empty', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      await tester.enterText(fields.at(1), '1234567890');
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '123 Main St');
      await tester.pump();
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'City');
      await tester.enterText(fields.at(5), 'ST');
      // Skip zip
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('Next disabled when phone is empty', (tester) async {
      await _goToStep2(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'test@example.com');
      // Skip phone
      await tester.pump();
      await tester.ensureVisible(fields.at(2));
      await tester.pump();
      await tester.enterText(fields.at(2), '123 Main St');
      await tester.pump();
      await tester.ensureVisible(fields.at(4));
      await tester.pump();
      await tester.enterText(fields.at(4), 'City');
      await tester.enterText(fields.at(5), 'ST');
      await tester.enterText(fields.at(6), '12345');
      await tester.pump();

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('RegistrationPage - password exactly 8 chars', () {
    testWidgets('Next enabled when password is exactly 8 chars',
        (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Abcd1234');
      await tester.enterText(fields.at(1), 'Abcd1234');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Next disabled when password is 7 chars', (tester) async {
      await _goToStep3(tester);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Abcd123');
      await tester.enterText(fields.at(1), 'Abcd123');
      await tester.pump();
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Next'),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('RegistrationPage - review step canProceed always true', () {
    testWidgets('Sign Up button is always enabled on review step',
        (tester) async {
      await _goToStep4(tester);
      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Sign Up'),
      );
      // _canProceed returns true for step 4
      expect(button.onPressed, isNotNull);
    });
  });

  group('RegistrationPage - Caregiver Friend type flow', () {
    testWidgets('Friend caregiver type does not show license fields',
        (tester) async {
      await _goToStep1(tester, role: 'Caregiver');
      await _fillCaregiverPersonalInfo(tester, caregiverType: 'Friend');
      await _tapNextButton(tester);

      // Should be on step 2 (Contact)
      expect(find.text('Contact Information'), findsOneWidget);

      // Scroll down
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -500));
      await tester.pump();

      // Should NOT show professional fields
      expect(find.text('Professional Information'), findsNothing);
      expect(find.text('License Number *'), findsNothing);
    });
  });

  group('RegistrationPage - Professional Caregiver full flow', () {
    testWidgets('Professional caregiver can reach review with all fields',
        (tester) async {
      // Step 0 -> Step 1
      await _goToStep1(tester, role: 'Caregiver');
      await _fillCaregiverPersonalInfo(tester, caregiverType: 'Professional');
      await _tapNextButton(tester);

      // Step 2 - Contact with professional fields
      expect(find.text('Contact Information'), findsOneWidget);
      final contactFields = find.byType(TextFormField);
      await tester.enterText(contactFields.at(0), 'pro@caregiver.com');
      await tester.enterText(contactFields.at(1), '5559876543');
      await tester.pump();

      await tester.ensureVisible(contactFields.at(2));
      await tester.pump();
      await tester.enterText(contactFields.at(2), '789 Care Blvd');
      await tester.pump();

      await tester.ensureVisible(contactFields.at(4));
      await tester.pump();
      await tester.enterText(contactFields.at(4), 'Rockville');
      await tester.enterText(contactFields.at(5), 'MD');
      await tester.enterText(contactFields.at(6), '20850');
      await tester.pump();

      // Professional fields - scroll to them
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -500));
      await tester.pump();

      // Find license, issuing state, years of experience fields
      final allFields = find.byType(TextFormField);
      // License Number is at index 7, Issuing State at 8, Years at 9
      await tester.ensureVisible(allFields.at(7));
      await tester.pump();
      await tester.enterText(allFields.at(7), 'LIC-12345');
      await tester.pump();

      await tester.ensureVisible(allFields.at(8));
      await tester.pump();
      await tester.enterText(allFields.at(8), 'Maryland');
      await tester.pump();

      await tester.ensureVisible(allFields.at(9));
      await tester.pump();
      await tester.enterText(allFields.at(9), '10');
      await tester.pump();

      // Next should now be enabled (all professional fields filled)
      final nextBtn = find.widgetWithText(ElevatedButton, 'Next');
      await tester.ensureVisible(nextBtn);
      await tester.pump();
      final button = tester.widget<ElevatedButton>(nextBtn);
      expect(button.onPressed, isNotNull);

      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump();

      // Step 3 - Security
      expect(find.text('Security Setup'), findsOneWidget);
      final secFields = find.byType(TextFormField);
      await tester.enterText(secFields.at(0), 'Password123');
      await tester.enterText(secFields.at(1), 'Password123');
      await tester.pump();
      await _tapNextButton(tester);

      // Step 4 - Review - should show professional info
      expect(find.text('Review & Confirm'), findsOneWidget);
      expect(find.text('Caregiver'), findsOneWidget);
      expect(find.text('Caregiver Type'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);

      // Scroll to see professional review fields
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -400));
      await tester.pump();

      expect(find.text('License Number'), findsOneWidget);
      expect(find.text('LIC-12345'), findsOneWidget);
      expect(find.text('Issuing State'), findsOneWidget);
      expect(find.text('Maryland'), findsOneWidget);
      expect(find.text('Years of Experience'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });
  });

  group('RegistrationPage - dispose cleanup', () {
    testWidgets('widget can be disposed without errors', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      // Dispose by pumping a different widget
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pump();
      // No errors means dispose worked
      expect(find.byType(Scaffold), findsOneWidget);
    });
  });

  group('RegistrationPage - FractionallySizedBox progress', () {
    testWidgets('progress bar uses FractionallySizedBox', (tester) async {
      await tester.pumpWidget(_wrap(initialRole: 'Patient'));
      await tester.pump();
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });
  });

  group('RegistrationPage – submit (Patient)', () {
    testWidgets('successful registration navigates to /login', (tester) async {
      HttpOverrides.global =
          FakeHttpOverrides((method, uri) => FakeResponse(200, '{}'));
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await _goToStep4(tester); // fill all steps, land on the review step

      final signUp = find.widgetWithText(ElevatedButton, 'Sign Up');
      await tester.ensureVisible(signUp);
      await tester.tap(signUp);
      await tester.pump(); // start the async submit
      await tester.pump(const Duration(seconds: 1)); // let http + navigation run

      expect(find.text('Login Page'), findsOneWidget);
    });

    testWidgets('failed registration shows a SnackBar', (tester) async {
      HttpOverrides.global = FakeHttpOverrides(
        (method, uri) => FakeResponse(400, '{"error":"bad"}'),
      );
      addTearDown(() => HttpOverrides.global = null);

      await tester.pumpWidget(_wrap());
      await tester.pump();
      await _goToStep4(tester);

      final signUp = find.widgetWithText(ElevatedButton, 'Sign Up');
      await tester.ensureVisible(signUp);
      await tester.tap(signUp);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Registration failed'), findsOneWidget);
    });
  });

  group('RegistrationPage – submit (Caregiver)', () {
    testWidgets('successful registration navigates to subscription tier',
        (tester) async {
      HttpOverrides.global =
          FakeHttpOverrides((method, uri) => FakeResponse(201, '{}'));
      addTearDown(() => HttpOverrides.global = null);

      await _goToCaregiverReview(tester);

      final signUp = find.widgetWithText(ElevatedButton, 'Sign Up');
      await tester.ensureVisible(signUp);
      await tester.tap(signUp);
      await tester.pump(); // start the async submit
      await tester.pump(const Duration(seconds: 1)); // let http + navigation run

      expect(find.text('Subscription Tier'), findsOneWidget);
    });
  });
}
