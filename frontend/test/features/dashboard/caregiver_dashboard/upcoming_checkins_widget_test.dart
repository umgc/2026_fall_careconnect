// Tests for UpcomingCheckins widget
// (lib/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart)
//
// Covers: rendering, patient names, dates, View buttons, "View All Patients"
// button, "Start EV Session" button, icon, button taps with GoRouter, and
// structural properties (ElevatedButton styling, access_time icon).

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/upcoming-checkins-widget.dart';

/// Wraps [child] in a GoRouter so that context.push works without crashing.
Widget _wrapWithRouter(Widget child, {List<String> pushedRoutes = const []}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            Scaffold(body: SingleChildScrollView(child: child)),
      ),
      GoRoute(
        path: '/tasks',
        builder: (context, state) {
          pushedRoutes.add('/tasks');
          return const Scaffold(body: Text('Tasks Page'));
        },
      ),
      GoRoute(
        path: '/evv/select-patient',
        builder: (context, state) {
          pushedRoutes.add('/evv/select-patient');
          return const Scaffold(body: Text('EVV Page'));
        },
      ),
    ],
  );
  return MaterialApp.router(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, routerConfig: router);
}

/// Simple wrapper without GoRouter for pure rendering tests.
Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('UpcomingCheckins - rendering', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.byType(UpcomingCheckins), findsOneWidget);
    });

    testWidgets('shows "Upcoming Check-Ins" header text', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.text('Upcoming Check-Ins'), findsOneWidget);
    });

    testWidgets('shows calendar_today icon in header', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
    });

    testWidgets('shows all four patient names', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.text('Sarah Johnson'), findsOneWidget);
      expect(find.text('Robert Chen'), findsOneWidget);
      expect(find.text('Maria Rodriguez'), findsOneWidget);
      expect(find.text('David Thompson'), findsOneWidget);
    });

    testWidgets('shows date/time for each patient', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.text('12/28/2024 at 10:00 AM'), findsOneWidget);
      expect(find.text('12/28/2024 at 2:30 PM'), findsOneWidget);
      expect(find.text('12/29/2024 at 9:15 AM'), findsOneWidget);
      expect(find.text('12/29/2024 at 11:45 AM'), findsOneWidget);
    });

    testWidgets('shows four View buttons (one per patient)', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.text('View'), findsNWidgets(4));
    });

    testWidgets('shows "View All Patients" TextButton', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.text('View All Patients'), findsOneWidget);
      // It should be a TextButton
      final textButton = find.ancestor(
        of: find.text('View All Patients'),
        matching: find.byType(TextButton),
      );
      expect(textButton, findsOneWidget);
    });

    testWidgets('shows "Start EV Session" ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.text('Start EV Session'), findsOneWidget);
      final elevatedButton = find.ancestor(
        of: find.text('Start EV Session'),
        matching: find.byType(ElevatedButton),
      );
      expect(elevatedButton, findsOneWidget);
    });

    testWidgets('shows access_time icon next to "Start EV Session"',
        (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });
  });

  group('UpcomingCheckins - structure', () {
    testWidgets('is wrapped in a Container with rounded corners',
        (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      // The outermost Container has BoxDecoration with borderRadius 16
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(UpcomingCheckins),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration, isNotNull);
      expect(decoration!.borderRadius, BorderRadius.circular(16));
    });

    testWidgets('contains a Column as its main child', (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      expect(
        find.descendant(
          of: find.byType(UpcomingCheckins),
          matching: find.byType(Column),
        ),
        findsWidgets,
      );
    });

    testWidgets('each patient item has an Expanded column with name and date',
        (tester) async {
      await tester.pumpWidget(_wrap(const UpcomingCheckins()));
      // Should find 4 patient rows, each containing an Expanded widget
      // wrapping a Column (name + date)
      expect(
        find.descendant(
          of: find.byType(UpcomingCheckins),
          matching: find.byType(Expanded),
        ),
        findsWidgets,
      );
    });
  });

  group('UpcomingCheckins - navigation', () {
    testWidgets('"View All Patients" navigates to /tasks', (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(
          _wrapWithRouter(const UpcomingCheckins(), pushedRoutes: pushed));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View All Patients'));
      await tester.pumpAndSettle();

      expect(pushed, contains('/tasks'));
    });

    testWidgets('"Start EV Session" navigates to /evv/select-patient',
        (tester) async {
      final pushed = <String>[];
      await tester.pumpWidget(
          _wrapWithRouter(const UpcomingCheckins(), pushedRoutes: pushed));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start EV Session'));
      await tester.pumpAndSettle();

      expect(pushed, contains('/evv/select-patient'));
    });

    testWidgets('View button can be tapped without error', (tester) async {
      await tester.pumpWidget(
          _wrapWithRouter(const UpcomingCheckins()));
      await tester.pumpAndSettle();

      // Tap the first "View" button - it has an empty onPressed
      await tester.tap(find.text('View').first);
      await tester.pumpAndSettle();
      // No crash = success
    });
  });
}
