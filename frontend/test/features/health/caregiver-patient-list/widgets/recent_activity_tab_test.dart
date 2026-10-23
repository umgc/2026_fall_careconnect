// Tests for RecentActivityTab widget and ActivityEntry model
// (lib/features/health/caregiver-patient-list/widgets/recent_activity_tab.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/widgets/recent_activity_tab.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // ActivityEntry
  // ───────────────────────────────────────────────────────────────────────────
  group('ActivityEntry', () {
    test('stores title and when fields', () {
      const entry = ActivityEntry(title: 'Check-in completed', when: '2 hours ago');
      expect(entry.title, 'Check-in completed');
      expect(entry.when, '2 hours ago');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // RecentActivityTab
  // ───────────────────────────────────────────────────────────────────────────
  group('RecentActivityTab', () {
    testWidgets('renders without crashing with empty list', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: []),
      ));
      expect(find.byType(RecentActivityTab), findsOneWidget);
    });

    testWidgets('shows "Recent Activity" header', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: []),
      ));
      expect(find.text('Recent Activity'), findsOneWidget);
    });

    testWidgets('shows activity title', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: [
          ActivityEntry(title: 'Medication taken', when: '10 min ago'),
        ]),
      ));
      expect(find.text('Medication taken'), findsOneWidget);
    });

    testWidgets('shows activity timestamp', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: [
          ActivityEntry(title: 'Medication taken', when: '10 min ago'),
        ]),
      ));
      expect(find.text('10 min ago'), findsOneWidget);
    });

    testWidgets('shows multiple activity entries', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: [
          ActivityEntry(title: 'Check-in', when: '1 hour ago'),
          ActivityEntry(title: 'Symptom logged', when: '3 hours ago'),
          ActivityEntry(title: 'Medication taken', when: '5 hours ago'),
        ]),
      ));
      expect(find.text('Check-in'), findsOneWidget);
      expect(find.text('Symptom logged'), findsOneWidget);
      expect(find.text('Medication taken'), findsOneWidget);
    });

    testWidgets('shows dividers between items (n-1 dividers for n items)', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: [
          ActivityEntry(title: 'Event A', when: 'now'),
          ActivityEntry(title: 'Event B', when: 'later'),
          ActivityEntry(title: 'Event C', when: 'even later'),
        ]),
      ));
      // 3 items → 2 dividers
      expect(find.byType(Divider), findsNWidgets(2));
    });

    testWidgets('shows no dividers for a single item', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentActivityTab(items: [
          ActivityEntry(title: 'Solo Event', when: 'just now'),
        ]),
      ));
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('renders without crashing with many items', (tester) async {
      final items = List.generate(
        10,
        (i) => ActivityEntry(title: 'Activity $i', when: '$i hours ago'),
      );
      await tester.pumpWidget(_wrap(RecentActivityTab(items: items)));
      expect(find.byType(RecentActivityTab), findsOneWidget);
    });
  });
}
