// Tests for CancelScreen and SosScreen widgets:
//   CancelScreen  (lib/features/dashboard/presentation/cancelscreen.dart)
//   SosScreen     (lib/features/dashboard/presentation/sosscreen.dart)
//
// Both are pure StatelessWidgets — no API calls, Provider, or platform channels.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/cancelscreen.dart';
import 'package:care_connect_app/features/dashboard/presentation/sosscreen.dart';

Widget _wrap(Widget child) => MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: child);

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // CancelScreen
  // ─────────────────────────────────────────────────────────────────────────
  group('CancelScreen', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the widget builds without error.
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.byType(CancelScreen), findsOneWidget);
    });

    testWidgets('shows "SOS Request Cancelled" heading', (tester) async {
      // The main status message must be visible.
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.text('SOS Request Cancelled'), findsOneWidget);
    });

    testWidgets('shows "Your caregiver has not been alerted." message',
        (tester) async {
      // The reassurance text must be visible.
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.text('Your caregiver has not been alerted.'), findsOneWidget);
    });

    testWidgets('shows cancel icon', (tester) async {
      // The large red cancel icon must appear.
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('shows "Back" button', (tester) async {
      // A "Back" button lets the user return to the previous screen.
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton', (tester) async {
      // The CTA must be an ElevatedButton.
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows "CareConnect" in app bar', (tester) async {
      // The AppBar title for the cancel screen is "CareConnect".
      await tester.pumpWidget(_wrap(const CancelScreen()));
      expect(find.text('CareConnect'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // SosScreen
  // ─────────────────────────────────────────────────────────────────────────
  group('SosScreen', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the widget builds without error.
      await tester.pumpWidget(_wrap(const SosScreen()));
      expect(find.byType(SosScreen), findsOneWidget);
    });

    testWidgets('shows "SOS Sent" heading', (tester) async {
      // The main status message must be visible.
      await tester.pumpWidget(_wrap(const SosScreen()));
      expect(find.text('SOS Sent'), findsOneWidget);
    });

    testWidgets('shows "Your caregiver has been notified." message',
        (tester) async {
      // The confirmation text must be visible.
      await tester.pumpWidget(_wrap(const SosScreen()));
      expect(find.text('Your caregiver has been notified.'), findsOneWidget);
    });

    testWidgets('shows warning_amber_rounded icon', (tester) async {
      // The SOS warning icon must appear.
      await tester.pumpWidget(_wrap(const SosScreen()));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows "Back" button', (tester) async {
      // A "Back" button lets the user return after the SOS is confirmed.
      await tester.pumpWidget(_wrap(const SosScreen()));
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton', (tester) async {
      // The CTA must be an ElevatedButton.
      await tester.pumpWidget(_wrap(const SosScreen()));
      expect(find.byType(ElevatedButton), findsOneWidget);
    });
  });
}
