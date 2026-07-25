// Tests for remaining patient dashboard widgets:
//   OfflineNotification      (offline_notification_widget.dart)
//   NotificationsPanel       (notifications_panel_widget.dart)
//   NotificationItem model   (notifications_panel_widget.dart)

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/offline_notification_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/notifications_panel_widget.dart';

Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: child)));

// ─────────────────────────────────────────────────────────────────────────────
// OfflineNotification
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  group('OfflineNotification', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.byType(OfflineNotification), findsOneWidget);
    });

    testWidgets('shows "Offline Mode" text', (tester) async {
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.text('Offline Mode'), findsOneWidget);
    });

    testWidgets('shows wifi_off icon', (tester) async {
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows "Never synced" when lastSynced is null', (tester) async {
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.textContaining('Never synced'), findsOneWidget);
    });

    testWidgets('shows "minutes ago" for recent sync', (tester) async {
      final recent = DateTime.now().subtract(const Duration(minutes: 15));
      await tester.pumpWidget(_wrap(OfflineNotification(lastSynced: recent)));
      expect(find.textContaining('minutes ago'), findsOneWidget);
    });

    testWidgets('shows "hours ago" for sync earlier today', (tester) async {
      final earlier = DateTime.now().subtract(const Duration(hours: 3));
      await tester.pumpWidget(_wrap(OfflineNotification(lastSynced: earlier)));
      expect(find.textContaining('hours ago'), findsOneWidget);
    });

    testWidgets('shows "days ago" for old sync', (tester) async {
      final old = DateTime.now().subtract(const Duration(days: 2));
      await tester.pumpWidget(_wrap(OfflineNotification(lastSynced: old)));
      expect(find.textContaining('days ago'), findsOneWidget);
    });

    testWidgets('shows sync message text', (tester) async {
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.textContaining('sync when reconnected'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // NotificationsPanel
  // ───────────────────────────────────────────────────────────────────────────
  group('NotificationsPanel', () {
    testWidgets('renders without crashing with empty list', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(notifications: []),
      ));
      expect(find.byType(NotificationsPanel), findsOneWidget);
    });

    testWidgets('shows default heading "Notifications"', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(notifications: []),
      ));
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('shows custom heading when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(
          notifications: [],
          heading: 'Alerts',
        ),
      ));
      expect(find.text('Alerts'), findsOneWidget);
    });

    testWidgets('shows "No notifications to show." when list is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(notifications: [], initiallyExpanded: true),
      ));
      await tester.pump();
      expect(find.text('No notifications to show.'), findsOneWidget);
    });

    testWidgets('shows notification title when expanded', (tester) async {
      await tester.pumpWidget(_wrap(
        NotificationsPanel(
          initiallyExpanded: true,
          notifications: [
            NotificationItem(
              kind: NotificationKind.urgent,
              title: 'Doctor appointment tomorrow',
            ),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Doctor appointment tomorrow'), findsOneWidget);
    });

    testWidgets('shows notification subtitle when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        NotificationsPanel(
          initiallyExpanded: true,
          notifications: [
            NotificationItem(
              kind: NotificationKind.important,
              title: 'Lab results ready',
              subtitle: 'Review with your doctor',
            ),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Review with your doctor'), findsOneWidget);
    });

    testWidgets('shows CTA button when ctaLabel is provided', (tester) async {
      await tester.pumpWidget(_wrap(
        NotificationsPanel(
          initiallyExpanded: true,
          notifications: [
            NotificationItem(
              kind: NotificationKind.urgent,
              title: 'Take medication',
              ctaLabel: 'Mark Taken',
              onTapCTA: () {},
            ),
          ],
        ),
      ));
      await tester.pump();
      expect(find.text('Mark Taken'), findsOneWidget);
    });

    testWidgets('does not show CTA button when ctaLabel is null', (tester) async {
      await tester.pumpWidget(_wrap(
        NotificationsPanel(
          initiallyExpanded: true,
          notifications: [
            const NotificationItem(
              kind: NotificationKind.reminder,
              title: 'Reminder',
            ),
          ],
        ),
      ));
      await tester.pump();
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('shows "Hide" when expanded and "Show" when collapsed', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(
          notifications: [],
          initiallyExpanded: true,
        ),
      ));
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Show'), findsNothing);
    });

    testWidgets('toggles between Hide and Show on tap', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(
          notifications: [],
          initiallyExpanded: true,
        ),
      ));
      expect(find.text('Hide'), findsOneWidget);
      await tester.tap(find.text('Hide'));
      await tester.pumpAndSettle();
      expect(find.text('Show'), findsOneWidget);
    });

    testWidgets('shows notifications_none icon', (tester) async {
      await tester.pumpWidget(_wrap(
        const NotificationsPanel(notifications: []),
      ));
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // NotificationItem model
  // ───────────────────────────────────────────────────────────────────────────
  group('NotificationItem', () {
    test('stores all fields', () {
      bool tapped = false;
      final item = NotificationItem(
        kind: NotificationKind.urgent,
        title: 'Alert title',
        subtitle: 'Alert subtitle',
        ctaLabel: 'Act Now',
        onTapCTA: () => tapped = true,
      );
      expect(item.kind, NotificationKind.urgent);
      expect(item.title, 'Alert title');
      expect(item.subtitle, 'Alert subtitle');
      expect(item.ctaLabel, 'Act Now');
      item.onTapCTA!();
      expect(tapped, isTrue);
    });

    test('optional fields default to null', () {
      const item = NotificationItem(
        kind: NotificationKind.reminder,
        title: 'Simple reminder',
      );
      expect(item.subtitle, isNull);
      expect(item.ctaLabel, isNull);
      expect(item.onTapCTA, isNull);
    });
  });
}
