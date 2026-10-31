// Widget tests for MedicationRemindersWidget frequency/date formatting and
// RecentCheckInsWidget mood translations
// (lib/features/dashboard/patient_dashboard/widgets/).

import 'package:care_connect_app/features/dashboard/patient_dashboard/models/medication_reminder_item.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/medication_reminder_widget.dart';
import 'package:care_connect_app/features/dashboard/patient_dashboard/widgets/recent_checkin_widget.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

MedicationReminderItem _item(int id, String frequency, {DateTime? due}) =>
    MedicationReminderItem(
      medicationId: id,
      medicationName: 'Med $id',
      dosage: '5 mg',
      frequency: frequency,
      nextDueAt: due ?? DateTime.now(),
      isTakenForCurrentWindow: false,
    );

void main() {
  group('MedicationRemindersWidget', () {
    testWidgets('translates frequency phrases and shows overflow count',
        (tester) async {
      final reminders = [
        _item(1, 'Three times a day'),
        _item(2, '4x per day'),
        _item(3, 'Every 4 hours'),
        _item(4, 'Weekly'),
        _item(5, 'Once a month'),
        _item(6, 'Daily at bedtime'),
        _item(7, 'As needed'),
        _item(8, 'Custom schedule'),
      ];
      await _pump(tester, MedicationRemindersWidget(reminders: reminders));
      expect(find.text('5 mg • Three times daily'), findsOneWidget);
      expect(find.text('5 mg • Four times daily'), findsOneWidget);
      expect(find.text('5 mg • Hourly'), findsOneWidget);
      expect(find.text('5 mg • Weekly'), findsOneWidget);
      expect(find.text('5 mg • Monthly'), findsOneWidget);
      expect(find.text('5 mg • Once daily at bedtime'), findsOneWidget);
      // Only six reminders are shown; the rest are summarised.
      expect(find.text('+2 more medications'), findsOneWidget);
    });

    testWidgets('shows as-needed and custom frequencies', (tester) async {
      await _pump(
        tester,
        MedicationRemindersWidget(
          reminders: [_item(1, 'As needed'), _item(2, 'Custom schedule')],
        ),
      );
      expect(find.text('5 mg • As needed'), findsOneWidget);
      expect(find.text('5 mg • Custom schedule'), findsOneWidget);
    });

    testWidgets('formats tomorrow and later due dates', (tester) async {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
      final later = DateTime(now.year, now.month, now.day + 5, 15, 30);
      await _pump(
        tester,
        MedicationRemindersWidget(
          reminders: [
            _item(1, 'daily', due: tomorrow),
            _item(2, 'daily', due: later),
          ],
        ),
      );
      expect(find.textContaining('Tomorrow'), findsOneWidget);
      expect(find.textContaining('${later.month}/${later.day}'), findsOneWidget);
    });
  });

  group('RecentCheckInsWidget', () {
    testWidgets('translates every known mood label', (tester) async {
      final now = DateTime.now();
      for (final batch in [
        ['Happy', 'Great', 'Excellent'],
        ['Down', 'Okay', 'Custom'],
      ]) {
        final checkIns = [
          for (final status in batch)
            CheckIn(date: now, status: status, emoji: ':)'),
        ];
        await _pump(tester, RecentCheckInsWidget(checkIns: checkIns));
        for (final s in batch) {
          expect(find.text(s), findsOneWidget, reason: s);
        }
        expect(RecentCheckInsWidget.totalCheckIns, 3);
      }
    });

    test('CheckIn.fromJson parses fields with defaults', () {
      final c = CheckIn.fromJson({'date': '2026-02-03T04:05:06'});
      expect(c.date, DateTime(2026, 2, 3, 4, 5, 6));
      expect(c.status, '');
      expect(c.emoji, '');
      final d = CheckIn.fromJson(
        {'date': '2026-02-03', 'status': 'Okay', 'emoji': 'x'},
      );
      expect(d.status, 'Okay');
      expect(d.emoji, 'x');
    });
  });
}
