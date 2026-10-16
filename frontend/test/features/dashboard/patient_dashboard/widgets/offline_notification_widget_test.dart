// Tests for OfflineNotification widget
// (lib/features/dashboard/patient_dashboard/widgets/offline_notification_widget.dart).
//
// OfflineNotification is a pure StatelessWidget — no platform channels.
// Tests cover: renders correctly, shows "Never synced", and shows
// the time-since-sync label for different elapsed durations.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/offline_notification_widget.dart';

Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: child));

void main() {
  group('OfflineNotification', () {
    testWidgets('renders without crashing when lastSynced is null', (tester) async {
      // Verifies the widget builds without error when no sync time is provided.
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('shows "Offline Mode" heading', (tester) async {
      // Verifies the static "Offline Mode" title is always shown.
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.text('Offline Mode'), findsOneWidget);
    });

    testWidgets('shows wifi_off icon', (tester) async {
      // Verifies the offline status icon is present.
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows Never synced when lastSynced is null', (tester) async {
      // Verifies the "Never synced" message for the null case.
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.textContaining('Never synced'), findsOneWidget);
    });

    testWidgets('shows minutes ago for a recent sync', (tester) async {
      // Verifies time shown as "X minutes ago" for < 60 minutes difference.
      final recent = DateTime.now().subtract(const Duration(minutes: 30));
      await tester.pumpWidget(_wrap(OfflineNotification(lastSynced: recent)));
      expect(find.textContaining('minutes ago'), findsOneWidget);
    });

    testWidgets('shows hours ago for a sync done hours ago', (tester) async {
      // Verifies time shown as "X hours ago" for 1-23 hours difference.
      final hoursAgo = DateTime.now().subtract(const Duration(hours: 3));
      await tester.pumpWidget(_wrap(OfflineNotification(lastSynced: hoursAgo)));
      expect(find.textContaining('hours ago'), findsOneWidget);
    });

    testWidgets('shows days ago for a sync done days ago', (tester) async {
      // Verifies time shown as "X days ago" for >= 24 hours difference.
      final daysAgo = DateTime.now().subtract(const Duration(days: 2));
      await tester.pumpWidget(_wrap(OfflineNotification(lastSynced: daysAgo)));
      expect(find.textContaining('days ago'), findsOneWidget);
    });

    testWidgets('shows sync reconnect message', (tester) async {
      // Verifies the static reconnect message is present.
      await tester.pumpWidget(_wrap(const OfflineNotification()));
      expect(find.textContaining('sync when reconnected'), findsOneWidget);
    });
  });
}
