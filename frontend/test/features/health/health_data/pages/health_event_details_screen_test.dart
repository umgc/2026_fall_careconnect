// HealthEventDetailsScreen: one record in full, including where it came from
// (the source moved here from the cards, per the M2 feedback).
// Test IDs TC-HDATA-034..036 and TC-HDATA-041 are permanent.
// Never renumber or reuse them.

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_event_details_screen.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(
  WidgetTester t,
  HealthRecord record, {
  Locale locale = const Locale('en'),
}) =>
    t.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HealthEventDetailsScreen(record: record),
      ),
    );

void main() {
  testWidgets(
      'TC-HDATA-034: shows the type, title, status, date, source and every detail',
      (t) async {
    await _show(
        t,
        HealthRecord.single(
          id: 'claim-1',
          source: RecordSource.medicare,
          type: RecordType.appointment,
          title: 'Office visit',
          date: DateTime(2026, 9, 15),
          status: 'Paid',
          details: const [
            RecordDetail('Provider', 'Dr. Sarah Mitchell'),
            RecordDetail('Amount', '\$120.00'),
          ],
        ));

    expect(find.text('Health Event Details'), findsOneWidget);
    expect(
        find.text(RecordType.appointment.label.toUpperCase()), findsOneWidget);
    expect(find.text('Office visit'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('September 15, 2026'), findsOneWidget);
    expect(find.text('Where this came from'), findsOneWidget);
    expect(find.text('Medicare'), findsOneWidget);
    expect(find.text('Dr. Sarah Mitchell'), findsOneWidget);
    expect(find.text('\$120.00'), findsOneWidget);
  });

  testWidgets(
      'TC-HDATA-035: a record without a date or status leaves those rows out instead of showing blanks',
      (t) async {
    await _show(
        t,
        HealthRecord.single(
          id: 'r-2',
          source: RecordSource.epic,
          type: RecordType.condition,
          title: 'Hypertension',
        ));

    expect(find.text('Hypertension'), findsOneWidget);
    expect(find.text('Date'), findsNothing);
    expect(find.text('Epic'), findsOneWidget);
  });

  testWidgets('TC-HDATA-036: every month is spelled out in the date',
      (t) async {
    await _show(
        t,
        HealthRecord.single(
          id: 'r-3',
          source: RecordSource.cerner,
          type: RecordType.appointment,
          title: 'Check-up',
          date: DateTime(2026, 1, 3),
        ));

    expect(find.text('January 3, 2026'), findsOneWidget);
  });

  testWidgets(
      'TC-HDATA-041: Spanish localizes the details interface while '
      'keeping the Cerner provider name unchanged', (t) async {
    await _show(
      t,
      HealthRecord.single(
        id: 'cerner-allergy-1',
        source: RecordSource.cerner,
        type: RecordType.allergy,
        title: 'Penicillin',
        date: DateTime(2026, 9, 10),
        status: 'active',
      ),
      locale: const Locale('es'),
    );

    expect(find.text('Detalles del evento de salud'), findsOneWidget);
    expect(find.text('ALERGIA'), findsOneWidget);
    expect(find.text('Fecha'), findsOneWidget);
    expect(find.text('10 de septiembre de 2026'), findsOneWidget);
    expect(find.text('De dónde proviene'), findsOneWidget);

    // Provider names are proper names and are not translated.
    expect(find.text('Oracle Health'), findsOneWidget);
    expect(find.text('Health Event Details'), findsNothing);
  });
}
