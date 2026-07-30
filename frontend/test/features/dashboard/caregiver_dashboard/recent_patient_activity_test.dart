// Tests for RecentPatientActivity widget
// (lib/features/dashboard/caregiver-dashboard/widgets/recent-patient-activity-widget.dart)

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/caregiver-dashboard/widgets/recent-patient-activity-widget.dart';

Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates,  supportedLocales: AppLocalizations.supportedLocales, home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('RecentPatientActivity', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(find.byType(RecentPatientActivity), findsOneWidget);
    });

    testWidgets('shows "Recent Patient Activity" header', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(find.text('Recent Patient Activity'), findsOneWidget);
    });

    testWidgets('shows monitor_heart_outlined icon', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(find.byIcon(Icons.monitor_heart_outlined), findsOneWidget);
    });

    testWidgets('shows Sarah Johnson activity via RichText', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Sarah Johnson')),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows Robert Chen activity via RichText', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Robert Chen')),
        findsAtLeastNWidgets(1),
      );
    });

    testWidgets('shows "completed check-in" action text', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('completed check-in')),
        findsOneWidget,
      );
    });

    testWidgets('shows time detail text', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(find.textContaining('hours ago'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows mood detail text', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(find.textContaining('Mood: Good'), findsOneWidget);
    });

    testWidgets('shows symptom detail text', (tester) async {
      await tester.pumpWidget(_wrap(const RecentPatientActivity()));
      expect(find.textContaining('Mild headache'), findsOneWidget);
    });
  });
}
