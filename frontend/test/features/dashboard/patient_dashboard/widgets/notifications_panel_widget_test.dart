// Tests for NotificationsPanel widget
// (lib/features/dashboard/patient_dashboard/widgets/notifications_panel_widget.dart).
// Pure stateful widget — no platform channels or network I/O.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/notifications_panel_widget.dart';

Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: child)));

NotificationItem _item({
  NotificationKind kind = NotificationKind.reminder,
  String title = 'Take medication',
  String? subtitle,
  String? ctaLabel,
  VoidCallback? onTapCTA,
}) =>
    NotificationItem(
      kind: kind,
      title: title,
      subtitle: subtitle,
      ctaLabel: ctaLabel,
      onTapCTA: onTapCTA,
    );

void main() {
  group('NotificationsPanel', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(notifications: [])));
      expect(find.byType(NotificationsPanel), findsOneWidget);
    });

    testWidgets('shows default heading Notifications', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(notifications: [])));
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('shows custom heading', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [],
        heading: 'Alerts',
      )));
      expect(find.text('Alerts'), findsOneWidget);
    });

    testWidgets('shows notification icon', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(notifications: [])));
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    });

    testWidgets('shows No notifications when empty and expanded', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [],
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('No notifications to show.'), findsOneWidget);
    });

    testWidgets('shows Hide button when initially expanded', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [],
        initiallyExpanded: true,
      )));
      expect(find.text('Hide'), findsOneWidget);
    });

    testWidgets('shows Show button when initially collapsed', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [],
        initiallyExpanded: false,
      )));
      expect(find.text('Show'), findsOneWidget);
    });

    testWidgets('shows notification title', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(title: 'Urgent Alert')],
      )));
      await tester.pumpAndSettle();
      expect(find.text('Urgent Alert'), findsOneWidget);
    });

    testWidgets('shows notification subtitle when provided', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(subtitle: 'Please take action')],
      )));
      await tester.pumpAndSettle();
      expect(find.text('Please take action'), findsOneWidget);
    });

    testWidgets('hides subtitle when not provided', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(subtitle: null)],
      )));
      await tester.pumpAndSettle();
      expect(find.text('Please take action'), findsNothing);
    });

    testWidgets('shows CTA button when ctaLabel provided', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(ctaLabel: 'Act Now')],
      )));
      await tester.pumpAndSettle();
      expect(find.text('Act Now'), findsOneWidget);
    });

    testWidgets('tapping CTA calls onTapCTA', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [
          _item(ctaLabel: 'Go', onTapCTA: () => tapped = true),
        ],
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('hides CTA when ctaLabel is null', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(ctaLabel: null)],
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('shows warning icon for each notification', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(), _item(title: 'Second')],
      )));
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.warning_amber_rounded),
        findsNWidgets(2),
      );
    });

    testWidgets('toggling Hide collapses the panel', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [_item(title: 'Hello')],
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);

      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(find.text('Show'), findsOneWidget);
    });

    testWidgets('renders multiple notification kinds', (tester) async {
      await tester.pumpWidget(_wrap(NotificationsPanel(
        notifications: [
          _item(kind: NotificationKind.urgent, title: 'Urgent'),
          _item(kind: NotificationKind.important, title: 'Important'),
          _item(kind: NotificationKind.reminder, title: 'Reminder'),
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.text('Urgent'), findsOneWidget);
      expect(find.text('Important'), findsOneWidget);
      expect(find.text('Reminder'), findsOneWidget);
    });
  });
}
