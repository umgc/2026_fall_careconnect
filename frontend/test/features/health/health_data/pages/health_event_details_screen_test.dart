// HealthEventDetailsScreen: one record in full, including where it came from
// (the source moved here from the cards, per the M2 feedback).

import 'package:care_connect_app/features/health/health_data/models/health_record.dart';
import 'package:care_connect_app/features/health/health_data/pages/health_event_details_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester t, HealthRecord record) =>
    t.pumpWidget(MaterialApp(home: HealthEventDetailsScreen(record: record)));

void main() {
  testWidgets('shows the type, title, status, date, source and every detail', (t) async {
    await _show(t, HealthRecord.single(
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
    expect(find.text(RecordType.appointment.label.toUpperCase()), findsOneWidget);
    expect(find.text('Office visit'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('September 15, 2026'), findsOneWidget);
    expect(find.text('Where this came from'), findsOneWidget);
    expect(find.text('Medicare'), findsOneWidget);
    expect(find.text('Dr. Sarah Mitchell'), findsOneWidget);
    expect(find.text('\$120.00'), findsOneWidget);
  });

  testWidgets('a record without a date or status leaves those rows out instead of showing blanks', (t) async {
    await _show(t, HealthRecord.single(
      id: 'r-2',
      source: RecordSource.epic,
      type: RecordType.condition,
      title: 'Hypertension',
    ));

    expect(find.text('Hypertension'), findsOneWidget);
    expect(find.text('Date'), findsNothing);
    expect(find.text('Epic'), findsOneWidget);
  });

  testWidgets('every month is spelled out in the date', (t) async {
    await _show(t, HealthRecord.single(
      id: 'r-3',
      source: RecordSource.cerner,
      type: RecordType.appointment,
      title: 'Check-up',
      date: DateTime(2026, 1, 3),
    ));

    expect(find.text('January 3, 2026'), findsOneWidget);
  });
}
