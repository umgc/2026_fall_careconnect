// Tests for MedicationRemindersWidget
// (lib/features/dashboard/patient_dashboard/widgets/medication_reminder_widget.dart).
//
// Pure StatelessWidget — no Provider, no HTTP.
// With empty reminders list shows "No active medication reminders".

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/medication_reminder_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';

final _sampleItem = MedicationReminderItem(
  medicationId: 1,
  medicationName: 'Aspirin',
  dosage: '100 mg',
  frequency: 'Once daily',
  nextDueAt: DateTime(2025, 1, 1, 9),
  isTakenForCurrentWindow: false,
);

Widget _wrapEmpty() => const MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, 
      home: Scaffold(body: MedicationRemindersWidget(reminders: [])),
    );

Widget _wrapWithReminder() => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales, 
      home: Scaffold(
        body: MedicationRemindersWidget(reminders: [_sampleItem]),
      ),
    );

void main() {
  group('MedicationRemindersWidget – empty list', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrapEmpty());
      expect(find.byType(MedicationRemindersWidget), findsOneWidget);
    });

    testWidgets('shows empty-state message when list is empty', (tester) async {
      await tester.pumpWidget(_wrapEmpty());
      expect(find.textContaining('No active medication reminders'), findsOneWidget);
    });

    testWidgets('does NOT show medication icon when list is empty', (tester) async {
      await tester.pumpWidget(_wrapEmpty());
      expect(find.byIcon(Icons.medication), findsNothing);
    });

    testWidgets('does NOT show Mark Taken button when list is empty', (tester) async {
      await tester.pumpWidget(_wrapEmpty());
      expect(find.text('Mark Taken'), findsNothing);
    });
  });

  group('MedicationRemindersWidget – with reminder', () {
    testWidgets('shows medication name', (tester) async {
      await tester.pumpWidget(_wrapWithReminder());
      expect(find.text('Aspirin'), findsOneWidget);
    });

    testWidgets('shows Medication Reminders heading', (tester) async {
      await tester.pumpWidget(_wrapWithReminder());
      expect(find.text('Medication Reminders'), findsOneWidget);
    });

    testWidgets('shows medication icon', (tester) async {
      await tester.pumpWidget(_wrapWithReminder());
      expect(find.byIcon(Icons.medication), findsOneWidget);
    });

    testWidgets('shows Mark Taken button', (tester) async {
      await tester.pumpWidget(_wrapWithReminder());
      expect(find.text('Mark Taken'), findsOneWidget);
    });

    testWidgets('shows Mark Missed button', (tester) async {
      await tester.pumpWidget(_wrapWithReminder());
      expect(find.text('Mark Missed'), findsOneWidget);
    });

    testWidgets('shows two OutlinedButton widgets', (tester) async {
      await tester.pumpWidget(_wrapWithReminder());
      expect(find.byType(OutlinedButton), findsNWidgets(2));
    });

    testWidgets('calls onMarkTaken with medicationId when tapped', (tester) async {
      int? takenId;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MedicationRemindersWidget(
            reminders: [_sampleItem],
            onMarkTaken: (id) => takenId = id,
          ),
        ),
      ));
      await tester.tap(find.text('Mark Taken'));
      expect(takenId, equals(1));
    });

    testWidgets('calls onMarkMissed with medicationId when tapped', (tester) async {
      int? missedId;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MedicationRemindersWidget(
            reminders: [_sampleItem],
            onMarkMissed: (id) => missedId = id,
          ),
        ),
      ));
      await tester.tap(find.text('Mark Missed'));
      expect(missedId, equals(1));
    });
  });
}
