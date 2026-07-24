// Tests for DashboardAppHeader widget
// (lib/shared/widgets/dashboard_appheader_widget.dart).
//
// DashboardAppHeader is a PreferredSizeWidget that renders a custom AppBar.
// Provider.of<UserProvider> is only accessed in onPressed callbacks, never
// in build(), so a plain MaterialApp wrapper suffices for render tests.

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/shared/widgets/dashboard_appheader_widget.dart';

Widget _wrap(DashboardAppHeader header) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(appBar: header));

void main() {
  group('DashboardAppHeader', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byType(DashboardAppHeader), findsOneWidget);
    });

    testWidgets('shows CARECONNECT logo text', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.text('CARECONNECT'), findsOneWidget);
    });

    testWidgets('shows welcome message with userName', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'John',
        role: 'CAREGIVER',
      )));
      expect(find.textContaining('Welcome back John'), findsOneWidget);
    });

    testWidgets('shows caregiver summary text for CAREGIVER role', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.textContaining("patients' health summary"), findsOneWidget);
    });

    testWidgets('shows patient greeting for PATIENT role', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Bob',
        role: 'PATIENT',
      )));
      expect(find.textContaining('How are you feeling today?'), findsOneWidget);
    });

    testWidgets('shows settings icon', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('shows local_hospital icon (emergency QR)', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byIcon(Icons.local_hospital), findsAtLeastNWidgets(1));
    });

    testWidgets('shows person icon when profileImageUrl is empty', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
        profileImageUrl: '',
      )));
      expect(find.byIcon(Icons.person), findsOneWidget);
    });

    testWidgets('preferredSize height is 210', (tester) async {
      const header = DashboardAppHeader(userName: 'Alice', role: 'CAREGIVER');
      expect(header.preferredSize.height, 210);
    });

    testWidgets('renders AppBar widget', (tester) async {
      await tester.pumpWidget(_wrap(const DashboardAppHeader(
        userName: 'Alice',
        role: 'CAREGIVER',
      )));
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
