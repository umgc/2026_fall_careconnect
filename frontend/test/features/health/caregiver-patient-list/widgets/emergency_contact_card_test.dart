// Tests for EmergencyContactCard widget
// (lib/features/health/caregiver-patient-list/widgets/emergency_contact_card.dart)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/emergency_contact_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// Installs a mock handler on the url_launcher MethodChannels so that
/// `canLaunchUrl` / `launchUrl` calls do not throw MissingPluginException.
List<MethodCall> _installUrlLauncherMock() {
  final log = <MethodCall>[];
  handler(MethodCall call) async {
    log.add(call);
    if (call.method == 'canLaunch') return true;
    if (call.method == 'launch') return true;
    return null;
  }

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
  group('EmergencyContactCard', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Jane Doe',
        relationship: 'Spouse',
      )));
      expect(find.byType(EmergencyContactCard), findsOneWidget);
    });

    testWidgets('shows Emergency Contact header', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Jane Doe',
        relationship: 'Spouse',
      )));
      expect(find.text('Emergency Contact'), findsOneWidget);
    });

    testWidgets('shows contact name', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Michael Johnson',
        relationship: 'Son',
      )));
      expect(find.text('Michael Johnson'), findsOneWidget);
    });

    testWidgets('shows relationship', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Susan Lee',
        relationship: 'Daughter',
      )));
      expect(find.text('Daughter'), findsOneWidget);
    });

    testWidgets('shows phone number when provided', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Bob',
        relationship: 'Brother',
        phone: '(555) 123-4567',
      )));
      expect(find.text('(555) 123-4567'), findsOneWidget);
    });

    testWidgets('does not show phone when not provided', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Alice',
        relationship: 'Sister',
      )));
      expect(find.text('(555) 123-4567'), findsNothing);
    });

    testWidgets('shows email when provided', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Carol',
        relationship: 'Mother',
        email: 'carol@example.com',
      )));
      expect(find.text('carol@example.com'), findsOneWidget);
    });

    testWidgets('shows phone icon button', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Dan',
        relationship: 'Father',
      )));
      expect(find.byIcon(Icons.phone), findsOneWidget);
    });

    testWidgets('shows chat icon button', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Eve',
        relationship: 'Spouse',
      )));
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('shows contact_emergency icon in header', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Frank',
        relationship: 'Uncle',
      )));
      expect(find.byIcon(Icons.contact_emergency), findsOneWidget);
    });

    testWidgets('calls onCall callback when phone button tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(EmergencyContactCard(
        contactName: 'Grace',
        relationship: 'Aunt',
        onCall: () => called = true,
      )));
      await tester.tap(find.byIcon(Icons.phone));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('calls onMessage callback when message button tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(EmergencyContactCard(
        contactName: 'Henry',
        relationship: 'Cousin',
        onMessage: () => called = true,
      )));
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('shows both phone and email together', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Ivy',
        relationship: 'Friend',
        phone: '555-9999',
        email: 'ivy@example.com',
      )));
      expect(find.text('555-9999'), findsOneWidget);
      expect(find.text('ivy@example.com'), findsOneWidget);
    });

    testWidgets('does not show email when not provided', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Jack',
        relationship: 'Neighbor',
        phone: '555-1111',
      )));
      expect(find.text('555-1111'), findsOneWidget);
      // No email text should appear
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('does not show phone when empty string', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Kate',
        relationship: 'Colleague',
        phone: '',
      )));
      // Empty phone should be treated as not having a value
      expect(find.text(''), findsNothing);
    });

    testWidgets('does not show email when empty string', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Leo',
        relationship: 'Friend',
        email: '',
      )));
      // Empty email should not render
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('shows Call tooltip on phone button', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Meg',
        relationship: 'Spouse',
      )));
      expect(find.byTooltip('Call'), findsOneWidget);
    });

    testWidgets('shows Message tooltip on chat button', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Ned',
        relationship: 'Spouse',
      )));
      expect(find.byTooltip('Message'), findsOneWidget);
    });

    testWidgets('tapping message without onMessage opens compose dialog', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Olivia',
        relationship: 'Sister',
        phone: '555-4444',
      )));
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      expect(find.text('Send Message'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('compose dialog has TextField with hint', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Pat',
        relationship: 'Brother',
        phone: '555-5555',
      )));
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Cancel dismisses compose dialog', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Quinn',
        relationship: 'Spouse',
        phone: '555-6666',
      )));
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Send Message'), findsNothing);
    });

    testWidgets('uses InkWell for action buttons', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Rose',
        relationship: 'Aunt',
      )));
      expect(find.byType(InkWell), findsWidgets);
    });

    testWidgets('does not show phone when whitespace only', (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Sam',
        relationship: 'Uncle',
        phone: '   ',
      )));
      // Whitespace-only phone treated as no value
      expect(find.text('   '), findsNothing);
    });
  });

  group('EmergencyContactCard url_launcher actions', () {
    late List<MethodCall> launcherLog;

    setUp(() {
      launcherLog = _installUrlLauncherMock();
    });

    tearDown(() {
      _removeUrlLauncherMock();
    });

    testWidgets('tap phone icon without onCall callback exercises _launchTel',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Tina',
        relationship: 'Spouse',
        phone: '(555) 999-0000',
      )));
      await tester.tap(find.byIcon(Icons.phone));
      await tester.pumpAndSettle();
      // Should not crash; url_launcher mock handles the call
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tap chat icon without onMessage, type message, tap Send exercises _launchSms',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Uma',
        relationship: 'Daughter',
        phone: '(555) 888-1111',
      )));
      // Open compose dialog
      await tester.tap(find.byIcon(Icons.chat_bubble_outline));
      await tester.pumpAndSettle();
      expect(find.text('Send Message'), findsOneWidget);

      // Type a message and tap Send
      await tester.enterText(find.byType(TextField), 'Hello there');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // Should not crash; url_launcher mock handles the sms launch
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'tap phone icon with empty/whitespace phone shows SnackBar',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmergencyContactCard(
        contactName: 'Victor',
        relationship: 'Brother',
        phone: '   ',
      )));
      await tester.tap(find.byIcon(Icons.phone));
      await tester.pumpAndSettle();
      expect(find.text('No phone number available'), findsOneWidget);
    });
  });
}
