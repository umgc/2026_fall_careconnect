// Tests for pure patient-dashboard widgets:
//   AlertNotification         (alter_notification_widget.dart)
//   PrimaryCareProviderWidget (primary_care_provider_widget.dart)
//   MedicationRemindersWidget (medication_reminder_widget.dart)
//   RecentCheckInsWidget      (recent_checkin_widget.dart)
//   CheckIn model             (recent_checkin_widget.dart)

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/alter_notification_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/primary_care_provider_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/medication_reminder_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/recent_checkin_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';

Widget _wrap(Widget child) =>
    MaterialApp(locale: const Locale('en'), localizationsDelegates: AppLocalizations.localizationsDelegates, supportedLocales: AppLocalizations.supportedLocales,  home: Scaffold(body: SingleChildScrollView(child: child)));

// ─────────────────────────────────────────────────────────────────────────────
// AlertNotification
// ─────────────────────────────────────────────────────────────────────────────
void main() {
  group('AlertNotification', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.info,
        message: 'This is an info message.',
      )));
      expect(find.byType(AlertNotification), findsOneWidget);
    });

    testWidgets('shows the message text via RichText', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.info,
        message: 'Take your medication',
      )));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText &&
            w.text.toPlainText().contains('Take your medication')),
        findsOneWidget,
      );
    });

    testWidgets('shows "Important:" title for important type', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.important,
        message: 'Urgent alert',
      )));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Important:')),
        findsOneWidget,
      );
    });

    testWidgets('shows "Reminder:" title for reminder type', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.reminder,
        message: 'Take medication',
      )));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Reminder:')),
        findsOneWidget,
      );
    });

    testWidgets('shows "Success:" title for success type', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.success,
        message: 'Task complete',
      )));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Success:')),
        findsOneWidget,
      );
    });

    testWidgets('shows "Info:" title for info type', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.info,
        message: 'FYI',
      )));
      expect(
        find.byWidgetPredicate((w) =>
            w is RichText && w.text.toPlainText().contains('Info:')),
        findsOneWidget,
      );
    });

    testWidgets('shows close button when onDismiss is provided', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.info,
        message: 'Dismissible',
        onDismiss: () {},
      )));
      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('does not show close button when onDismiss is null', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.info,
        message: 'Not dismissible',
      )));
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('calls onDismiss when close button tapped', (tester) async {
      bool dismissed = false;
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.reminder,
        message: 'Dismiss me',
        onDismiss: () => dismissed = true,
      )));
      await tester.tap(find.byIcon(Icons.close));
      expect(dismissed, isTrue);
    });

    testWidgets('shows warning_amber_rounded icon', (tester) async {
      await tester.pumpWidget(_wrap(AlertNotification(
        type: AlertType.important,
        message: 'Warning',
      )));
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // PrimaryCareProviderWidget
  // ───────────────────────────────────────────────────────────────────────────
  group('PrimaryCareProviderWidget', () {
    PrimaryCareProviderWidget makeWidget({
      DateTime? nextAppointment,
      String? appointmentType,
      VoidCallback? onContactProvider,
    }) =>
        PrimaryCareProviderWidget(
          providerName: 'Dr. Jane Doe',
          specialty: 'Internal Medicine',
          organization: 'City Health Clinic',
          phone: '555-9090',
          email: 'jane.doe@clinic.example',
          nextAppointment: nextAppointment,
          appointmentType: appointmentType,
          onContactProvider: onContactProvider,
        );

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.byType(PrimaryCareProviderWidget), findsOneWidget);
    });

    testWidgets('shows "Your Primary Care Provider" title', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('Your Primary Care Provider'), findsOneWidget);
    });

    testWidgets('shows provider name', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('Dr. Jane Doe'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows specialty', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('Internal Medicine'), findsOneWidget);
    });

    testWidgets('shows organization', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('City Health Clinic'), findsOneWidget);
    });

    testWidgets('shows phone number', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('555-9090'), findsOneWidget);
    });

    testWidgets('shows email', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('jane.doe@clinic.example'), findsOneWidget);
    });

    testWidgets('shows Contact Provider button', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('Contact Provider'), findsOneWidget);
    });

    testWidgets('calls onContactProvider callback when button tapped', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(makeWidget(onContactProvider: () => called = true)));
      await tester.tap(find.text('Contact Provider'));
      expect(called, isTrue);
    });

    testWidgets('shows "Next Appointment" section when nextAppointment provided', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget(
        nextAppointment: DateTime(2024, 6, 15, 14, 30),
      )));
      expect(find.text('Next Appointment'), findsOneWidget);
    });

    testWidgets('hides "Next Appointment" section when nextAppointment is null', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('Next Appointment'), findsNothing);
    });

    testWidgets('shows appointment type when provided', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget(
        nextAppointment: DateTime(2024, 6, 15, 14, 30),
        appointmentType: 'Follow-up',
      )));
      expect(find.textContaining('Follow-up'), findsOneWidget);
    });

    testWidgets('shows initials from provider name in CircleAvatar', (tester) async {
      // "Dr. Jane Doe" → first two words' initials = "DJ"
      await tester.pumpWidget(_wrap(makeWidget()));
      expect(find.text('DJ'), findsOneWidget);
    });

    testWidgets('shows formatted date for June 2024', (tester) async {
      await tester.pumpWidget(_wrap(makeWidget(
        nextAppointment: DateTime(2024, 6, 15, 10, 0),
      )));
      expect(find.textContaining('June 15, 2024'), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // MedicationRemindersWidget
  // ───────────────────────────────────────────────────────────────────────────
  group('MedicationRemindersWidget', () {
    final sampleItem = MedicationReminderItem(
      medicationId: 1,
      medicationName: 'Aspirin',
      dosage: '100 mg',
      frequency: 'Once daily',
      nextDueAt: DateTime(2024, 6, 15, 9, 0),
      isTakenForCurrentWindow: false,
    );

    testWidgets('renders without crashing when list is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        const MedicationRemindersWidget(reminders: []),
      ));
      expect(find.byType(MedicationRemindersWidget), findsOneWidget);
    });

    testWidgets('shows empty-state message when list is empty', (tester) async {
      await tester.pumpWidget(_wrap(
        const MedicationRemindersWidget(reminders: []),
      ));
      expect(find.textContaining('No active medication reminders'), findsOneWidget);
    });

    testWidgets('renders without crashing when reminder is provided', (tester) async {
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(reminders: [sampleItem]),
      ));
      expect(find.byType(MedicationRemindersWidget), findsOneWidget);
    });

    testWidgets('shows medication name when reminder is provided', (tester) async {
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(reminders: [sampleItem]),
      ));
      expect(find.text('Aspirin'), findsOneWidget);
    });

    testWidgets('shows dosage and frequency when reminder is provided', (tester) async {
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(reminders: [sampleItem]),
      ));
      expect(find.textContaining('100 mg'), findsOneWidget);
    });

    testWidgets('shows Mark Taken button', (tester) async {
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(reminders: [
          MedicationReminderItem(
            medicationId: 2,
            medicationName: 'Metformin',
            dosage: '500 mg',
            frequency: 'Twice daily',
            nextDueAt: DateTime(2024, 6, 15, 8, 0),
            isTakenForCurrentWindow: false,
          ),
        ]),
      ));
      expect(find.text('Mark Taken'), findsOneWidget);
    });

    testWidgets('shows Mark Missed button', (tester) async {
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(reminders: [
          MedicationReminderItem(
            medicationId: 3,
            medicationName: 'Metformin',
            dosage: '500 mg',
            frequency: 'Twice daily',
            nextDueAt: DateTime(2024, 6, 15, 8, 0),
            isTakenForCurrentWindow: false,
          ),
        ]),
      ));
      expect(find.text('Mark Missed'), findsOneWidget);
    });

    testWidgets('calls onMarkTaken with medicationId when Mark Taken tapped', (tester) async {
      int? takenId;
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(
          reminders: [sampleItem],
          onMarkTaken: (id) => takenId = id,
        ),
      ));
      await tester.tap(find.text('Mark Taken'));
      expect(takenId, equals(1));
    });

    testWidgets('calls onMarkMissed with medicationId when Mark Missed tapped', (tester) async {
      int? missedId;
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(
          reminders: [sampleItem],
          onMarkMissed: (id) => missedId = id,
        ),
      ));
      await tester.tap(find.text('Mark Missed'));
      expect(missedId, equals(1));
    });

    testWidgets('shows medication icon', (tester) async {
      await tester.pumpWidget(_wrap(
        MedicationRemindersWidget(reminders: [
          MedicationReminderItem(
            medicationId: 4,
            medicationName: 'Ibuprofen',
            dosage: '200 mg',
            frequency: 'As needed',
            nextDueAt: DateTime(2024, 6, 15, 12, 0),
            isTakenForCurrentWindow: false,
          ),
        ]),
      ));
      expect(find.byIcon(Icons.medication), findsOneWidget);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // RecentCheckInsWidget
  // ───────────────────────────────────────────────────────────────────────────
  group('RecentCheckInsWidget', () {
    testWidgets('renders without crashing with empty list', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentCheckInsWidget(checkIns: []),
      ));
      expect(find.byType(RecentCheckInsWidget), findsOneWidget);
    });

    testWidgets('shows "Recent Check-Ins" header', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentCheckInsWidget(checkIns: []),
      ));
      expect(find.text('Recent Check-Ins'), findsOneWidget);
    });

    testWidgets('shows Open Check-In button', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentCheckInsWidget(checkIns: []),
      ));
      expect(find.text('Open Check-In'), findsOneWidget);
    });

    testWidgets('shows show_chart icon', (tester) async {
      await tester.pumpWidget(_wrap(
        const RecentCheckInsWidget(checkIns: []),
      ));
      expect(find.byIcon(Icons.show_chart), findsOneWidget);
    });

    testWidgets('shows check-in status text', (tester) async {
      final checkIns = [
        CheckIn(date: DateTime(2024, 6, 15), status: 'Feeling good', emoji: '😊'),
      ];
      await tester.pumpWidget(_wrap(
        RecentCheckInsWidget(checkIns: checkIns),
      ));
      expect(find.text('Feeling good'), findsOneWidget);
    });

    testWidgets('shows formatted date for check-in', (tester) async {
      final checkIns = [
        CheckIn(date: DateTime(2024, 6, 15), status: 'OK', emoji: '🙂'),
      ];
      await tester.pumpWidget(_wrap(
        RecentCheckInsWidget(checkIns: checkIns),
      ));
      expect(find.textContaining('Jun 15'), findsOneWidget);
    });

    testWidgets('shows only up to 3 check-ins', (tester) async {
      final checkIns = List.generate(
        5,
        (i) => CheckIn(date: DateTime(2024, 6, i + 1), status: 'Status $i', emoji: '😐'),
      );
      await tester.pumpWidget(_wrap(
        RecentCheckInsWidget(checkIns: checkIns),
      ));
      // Only first 3 statuses should appear
      expect(find.text('Status 0'), findsOneWidget);
      expect(find.text('Status 2'), findsOneWidget);
      expect(find.text('Status 3'), findsNothing);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // CheckIn.fromJson
  // ───────────────────────────────────────────────────────────────────────────
  group('CheckIn.fromJson', () {
    test('parses date, status and emoji', () {
      final json = {
        'date': '2024-06-15T10:30:00.000',
        'status': 'Feeling great',
        'emoji': '😄',
      };
      final checkIn = CheckIn.fromJson(json);
      expect(checkIn.date, DateTime.parse('2024-06-15T10:30:00.000'));
      expect(checkIn.status, 'Feeling great');
      expect(checkIn.emoji, '😄');
    });

    test('status defaults to empty string when missing', () {
      final json = {'date': '2024-06-15T00:00:00.000'};
      final checkIn = CheckIn.fromJson(json);
      expect(checkIn.status, '');
    });

    test('emoji defaults to empty string when missing', () {
      final json = {'date': '2024-06-15T00:00:00.000'};
      final checkIn = CheckIn.fromJson(json);
      expect(checkIn.emoji, '');
    });
  });
}
