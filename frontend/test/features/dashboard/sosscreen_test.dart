// Tests for SosScreen from lib/features/dashboard/presentation/sosscreen.dart.
// Pure StatelessWidget — no HTTP, no Provider.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/sosscreen.dart';

Widget _wrap() => const MaterialApp(locale: Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: SosScreen());

void main() {
  group('SosScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SosScreen), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows SOS Sent text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('SOS Sent'), findsOneWidget);
    });

    testWidgets('shows warning icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('shows AppBar with CarConnect title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('CareConnect'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows caregiver notified message', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Your caregiver has been notified.'), findsOneWidget);
    });

    testWidgets('shows Back button', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('shows ElevatedButton', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows Center widget', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });
  });
}
