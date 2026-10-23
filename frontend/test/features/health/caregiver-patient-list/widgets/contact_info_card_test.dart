// Tests for ContactInfoCard widget
// (lib/features/health/caregiver-patient-list/widgets/contact_info_card.dart).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/contact_info_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// Installs a mock handler on the url_launcher MethodChannels so that
/// `canLaunchUrl` / `launchUrl` calls do not throw MissingPluginException.
/// Returns a list that records every MethodCall for assertions.
List<MethodCall> _installUrlLauncherMock() {
  final log = <MethodCall>[];
  handler(MethodCall call) async {
    log.add(call);
    if (call.method == 'canLaunch') return true;
    if (call.method == 'launch') return true;
    return null;
  }

  // Register the mock on all known url_launcher channel names.
  for (final channel in [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
    'plugins.flutter.io/url_launcher_windows',
    'plugins.flutter.io/url_launcher_linux',
    'plugins.flutter.io/url_launcher_macos',
    'plugins.flutter.io/url_launcher_ios',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channel), handler);
  }

  return log;
}

/// Removes the mock handlers installed by [_installUrlLauncherMock].
void _removeUrlLauncherMock() {
  for (final channel in [
    'plugins.flutter.io/url_launcher',
    'plugins.flutter.io/url_launcher_android',
    'plugins.flutter.io/url_launcher_windows',
    'plugins.flutter.io/url_launcher_linux',
    'plugins.flutter.io/url_launcher_macos',
    'plugins.flutter.io/url_launcher_ios',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(channel), null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('ContactInfoCard', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.byType(ContactInfoCard), findsOneWidget);
    });

    testWidgets('shows Contact Information header', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.text('Contact Information'), findsOneWidget);
    });

    testWidgets('shows info_outline icon in header', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('shows phone row when phone provided', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(phone: '(555) 123-4567')));
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('(555) 123-4567'), findsOneWidget);
      expect(find.byIcon(Icons.phone), findsOneWidget);
    });

    testWidgets('hides phone row when phone is null', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.text('Phone'), findsNothing);
    });

    testWidgets('shows email row when email provided', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(email: 'user@example.com')));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('user@example.com'), findsOneWidget);
      expect(find.byIcon(Icons.email_outlined), findsOneWidget);
    });

    testWidgets('hides email row when email is null', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('shows date of birth row when provided', (tester) async {
      await tester.pumpWidget(_wrap(ContactInfoCard(
        dateOfBirth: DateTime(1990, 7, 4),
      )));
      expect(find.text('Date of Birth'), findsOneWidget);
      expect(find.text('Jul 4, 1990'), findsOneWidget);
      expect(find.byIcon(Icons.cake_outlined), findsOneWidget);
    });

    testWidgets('hides date of birth row when null', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.text('Date of Birth'), findsNothing);
    });

    testWidgets('shows address row when address provided', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(
        addressLine1: '123 Main St',
        city: 'Springfield',
        state: 'IL',
        postalCode: '62701',
      )));
      expect(find.text('Address'), findsOneWidget);
      expect(find.textContaining('123 Main St'), findsOneWidget);
      expect(find.byIcon(Icons.home_outlined), findsOneWidget);
    });

    testWidgets('hides address row when all address fields are null', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard()));
      expect(find.text('Address'), findsNothing);
    });

    testWidgets('shows addressLine2 in address when provided', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(
        addressLine1: '456 Oak Ave',
        addressLine2: 'Apt 3B',
        city: 'Chicago',
        state: 'IL',
      )));
      expect(find.textContaining('Apt 3B'), findsOneWidget);
    });

    testWidgets('renders all fields together', (tester) async {
      await tester.pumpWidget(_wrap(ContactInfoCard(
        phone: '(555) 999-0000',
        email: 'test@test.com',
        dateOfBirth: DateTime(1985, 12, 25),
        addressLine1: '789 Pine Rd',
        city: 'Naperville',
        state: 'IL',
        postalCode: '60540',
      )));
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
      expect(find.text('Address'), findsOneWidget);
    });

    testWidgets('hides phone row when phone is empty string', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(phone: '')));
      expect(find.text('Phone'), findsNothing);
    });

    testWidgets('hides email row when email is empty string', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(email: '')));
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('hides phone row when phone is whitespace only', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(phone: '   ')));
      expect(find.text('Phone'), findsNothing);
    });

    testWidgets('hides email row when email is whitespace only', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(email: '   ')));
      expect(find.text('Email'), findsNothing);
    });

    testWidgets('shows address with only city and state', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(
        city: 'Denver',
        state: 'CO',
      )));
      expect(find.text('Address'), findsOneWidget);
      expect(find.textContaining('Denver'), findsOneWidget);
      expect(find.textContaining('CO'), findsOneWidget);
    });

    testWidgets('shows address with only postalCode', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(
        postalCode: '80202',
      )));
      expect(find.text('Address'), findsOneWidget);
      expect(find.textContaining('80202'), findsOneWidget);
    });

    testWidgets('shows tooltip on phone icon', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(phone: '555-1234')));
      expect(find.byType(Tooltip), findsWidgets);
    });

    testWidgets('shows tooltip on email icon', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(email: 'a@b.com')));
      expect(find.byType(Tooltip), findsWidgets);
    });

    testWidgets('shows "Open in Google Maps" tooltip on address icon', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(
        addressLine1: '100 Main',
        city: 'Denver',
        state: 'CO',
      )));
      expect(find.byTooltip('Open in Google Maps'), findsOneWidget);
    });

    testWidgets('formats December date correctly', (tester) async {
      await tester.pumpWidget(_wrap(ContactInfoCard(
        dateOfBirth: DateTime(1985, 12, 25),
      )));
      expect(find.text('Dec 25, 1985'), findsOneWidget);
    });

    testWidgets('formats January date correctly', (tester) async {
      await tester.pumpWidget(_wrap(ContactInfoCard(
        dateOfBirth: DateTime(2000, 1, 1),
      )));
      expect(find.text('Jan 1, 2000'), findsOneWidget);
    });

    testWidgets('uses InkWell for icon taps', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(phone: '555-9999')));
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('uses MouseRegion for hover effects', (tester) async {
      await tester.pumpWidget(_wrap(const ContactInfoCard(phone: '555-9999')));
      expect(find.byType(MouseRegion), findsWidgets);
    });

    testWidgets('onCallPhone callback provided via constructor', (tester) async {
      await tester.pumpWidget(_wrap(ContactInfoCard(
        phone: '555-0000',
        onCallPhone: () {},
      )));
      // The widget accepts the callback (doesn't crash)
      expect(find.text('Phone'), findsOneWidget);
    });

    testWidgets('onSendEmail callback provided via constructor', (tester) async {
      await tester.pumpWidget(_wrap(ContactInfoCard(
        email: 'test@test.com',
        onSendEmail: () {},
      )));
      expect(find.text('Email'), findsOneWidget);
    });
  });

  group('ContactInfoCard url_launcher actions', () {
    late List<MethodCall> launcherLog;

    setUp(() {
      launcherLog = _installUrlLauncherMock();
    });

    tearDown(() {
      _removeUrlLauncherMock();
    });

    testWidgets('tapping phone icon calls _callPhone without crashing',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ContactInfoCard(phone: '(555) 123-4567'),
      ));

      // The phone icon is wrapped in an InkWell inside a Tooltip with 'Call'.
      final callTooltip = find.byTooltip('Call');
      expect(callTooltip, findsOneWidget);
      await tester.tap(callTooltip);
      await tester.pumpAndSettle();

      // Should not crash; the mock channel handled the call.
      expect(find.byType(ContactInfoCard), findsOneWidget);
    });

    testWidgets('tapping email icon calls _sendEmail without crashing',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ContactInfoCard(email: 'user@example.com'),
      ));

      // The email icon tooltip is 'Email'.
      final emailTooltip = find.byTooltip('Email');
      expect(emailTooltip, findsOneWidget);
      await tester.tap(emailTooltip);
      await tester.pumpAndSettle();

      expect(find.byType(ContactInfoCard), findsOneWidget);
    });

    testWidgets('tapping address icon calls _openMaps without crashing',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ContactInfoCard(
          addressLine1: '123 Main St',
          city: 'Springfield',
          state: 'IL',
          postalCode: '62701',
        ),
      ));

      final mapsTooltip = find.byTooltip('Open in Google Maps');
      expect(mapsTooltip, findsOneWidget);
      await tester.tap(mapsTooltip);
      await tester.pumpAndSettle();

      expect(find.byType(ContactInfoCard), findsOneWidget);
    });

    testWidgets('_callPhone does not launch when phone is null',
        (tester) async {
      launcherLog.clear();
      await tester.pumpWidget(_wrap(
        const ContactInfoCard(),
      ));

      // No phone row at all, so nothing to tap.
      expect(find.byTooltip('Call'), findsNothing);
    });

    testWidgets('_sendEmail does not launch when email is null',
        (tester) async {
      launcherLog.clear();
      await tester.pumpWidget(_wrap(
        const ContactInfoCard(),
      ));

      expect(find.byTooltip('Email'), findsNothing);
    });

    testWidgets('_openMaps does not launch when address is null',
        (tester) async {
      launcherLog.clear();
      await tester.pumpWidget(_wrap(
        const ContactInfoCard(),
      ));

      expect(find.byTooltip('Open in Google Maps'), findsNothing);
    });
  });
}
