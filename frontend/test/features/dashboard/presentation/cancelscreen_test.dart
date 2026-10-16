// Tests for CancelScreen from lib/features/dashboard/presentation/cancelscreen.dart.
// Pure StatelessWidget — no HTTP, no Provider.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/presentation/cancelscreen.dart';

Widget _wrap() => const MaterialApp(locale: Locale('en'),localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,home: CancelScreen());

void main() {
  group('CancelScreen – initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CancelScreen), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows SOS Request Cancelled text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('Cancelled'), findsOneWidget);
    });

    testWidgets('shows cancel icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });

    testWidgets('shows AppBar with CareConnect title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('CareConnect'), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows caregiver not alerted message', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Your caregiver has not been alerted.'), findsOneWidget);
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
