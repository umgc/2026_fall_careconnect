import 'package:care_connect_app/features/tasks/presentation/widgets/recurrence_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picking a start date notifies onChanged', (tester) async {
    DateTime? reportedStart;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecurrenceForm(
              initialIsRecurring: true,
              initialStartDate: DateTime(2025, 6, 10),
              onChanged: ({
                bool? isRecurring,
                String? recurrenceType,
                List<bool>? daysOfWeek,
                int? interval,
                int? count,
                DateTime? startDate,
                DateTime? endDate,
                int? dayOfMonth,
                bool? applyToSeries,
              }) {
                reportedStart = startDate;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick Start Date'), findsOneWidget);
    await tester.ensureVisible(find.text('Pick Start Date'));
    await tester.tap(find.text('Pick Start Date'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(reportedStart, isNotNull);
    expect(reportedStart!.day, 15);
    expect(find.textContaining('Starts: 2025-06-15'), findsOneWidget);
  });
}
