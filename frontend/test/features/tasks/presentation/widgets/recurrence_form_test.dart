// Tests for RecurrenceForm widget
// (lib/features/tasks/presentation/widgets/recurrence_form.dart).
//
// Pure StatefulWidget — no API calls or Provider dependencies.
// Uses only RecurrenceUtils and TaskUtils which are pure Dart helpers.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/recurrence_form.dart';
import 'package:mockito/mockito.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// ── Helpers from calendar_assistant/recurrence_form_test.dart (merged) ──

class _OnChangedMock extends Mock {
  void call({
    bool? isRecurring,
    String? recurrenceType,
    List<bool>? daysOfWeek,
    int? interval,
    int? count,
    DateTime? startDate,
    DateTime? endDate,
    int? dayOfMonth,
    bool? applyToSeries,
  });
}

void main() {
  group('RecurrenceForm – non-recurring default', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the widget builds without error.
      await tester.pumpWidget(_wrap(RecurrenceForm(onChanged: ({
        bool? isRecurring,
        String? recurrenceType,
        List<bool>? daysOfWeek,
        int? interval,
        int? count,
        DateTime? startDate,
        DateTime? endDate,
        int? dayOfMonth,
        bool? applyToSeries,
      }) {})));
      expect(find.byType(RecurrenceForm), findsOneWidget);
    });

    testWidgets('shows "Recurring Task" checkbox', (tester) async {
      // The CheckboxListTile for enabling recurrence must be visible.
      await tester.pumpWidget(_wrap(RecurrenceForm(onChanged: ({
        bool? isRecurring,
        String? recurrenceType,
        List<bool>? daysOfWeek,
        int? interval,
        int? count,
        DateTime? startDate,
        DateTime? endDate,
        int? dayOfMonth,
        bool? applyToSeries,
      }) {})));
      expect(find.text('Recurring Task'), findsOneWidget);
    });

    testWidgets('recurring options hidden when not recurring', (tester) async {
      // Recurrence-specific controls must not appear when disabled.
      await tester.pumpWidget(_wrap(RecurrenceForm(onChanged: ({
        bool? isRecurring,
        String? recurrenceType,
        List<bool>? daysOfWeek,
        int? interval,
        int? count,
        DateTime? startDate,
        DateTime? endDate,
        int? dayOfMonth,
        bool? applyToSeries,
      }) {})));
      expect(find.text('Pick Start Date'), findsNothing);
      expect(find.text('Recurrence Type'), findsNothing);
    });
  });

  group('RecurrenceForm – enabling recurrence', () {
    testWidgets('toggling checkbox reveals recurrence controls', (tester) async {
      // Tapping the checkbox should expand the recurrence form.
      await tester.pumpWidget(_wrap(RecurrenceForm(onChanged: ({
        bool? isRecurring,
        String? recurrenceType,
        List<bool>? daysOfWeek,
        int? interval,
        int? count,
        DateTime? startDate,
        DateTime? endDate,
        int? dayOfMonth,
        bool? applyToSeries,
      }) {})));

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(find.text('Recurrence Type'), findsOneWidget);
    });

    testWidgets('shows recurrence type dropdown when recurring', (tester) async {
      // The dropdown for daily/weekly/monthly/yearly must appear.
      await tester.pumpWidget(_wrap(RecurrenceForm(
        initialIsRecurring: true,
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
        }) {},
      )));
      expect(find.text('Recurrence Type'), findsOneWidget);
    });

    testWidgets('shows "Pick Start Date" button when recurring', (tester) async {
      // The start date picker must be visible when recurrence is enabled.
      await tester.pumpWidget(_wrap(RecurrenceForm(
        initialIsRecurring: true,
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
        }) {},
      )));
      expect(find.text('Pick Start Date'), findsOneWidget);
    });

    testWidgets('shows missing type error when no type selected', (tester) async {
      // If recurring is on but no type is chosen, the error text must appear.
      await tester.pumpWidget(_wrap(RecurrenceForm(
        initialIsRecurring: true,
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
        }) {},
      )));
      expect(
        find.text('Please select a recurrence type'),
        findsOneWidget,
      );
    });

    testWidgets('invokes onChanged callback when checkbox toggled',
        (tester) async {
      // Verifies the callback is called with isRecurring=true on toggle.
      bool? capturedIsRecurring;
      await tester.pumpWidget(_wrap(RecurrenceForm(onChanged: ({
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
        capturedIsRecurring = isRecurring;
      })));

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(capturedIsRecurring, isTrue);
    });
  });

  group('RecurrenceForm – weekly type', () {
    testWidgets('shows days-of-week chips when Weekly is selected',
        (tester) async {
      // Selecting "Weekly" should reveal the day-of-week filter chips.
      await tester.pumpWidget(_wrap(RecurrenceForm(
        initialIsRecurring: true,
        initialRecurrenceType: 'Weekly',
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
        }) {},
      )));

      expect(find.text('Select Days of Week'), findsOneWidget);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Fri'), findsOneWidget);
    });

    testWidgets('shows weekly-invalid error when no days selected',
        (tester) async {
      // Weekly with zero days selected must show the error text.
      await tester.pumpWidget(_wrap(RecurrenceForm(
        initialIsRecurring: true,
        initialRecurrenceType: 'Weekly',
        initialDaysOfWeek: List.filled(7, false),
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
        }) {},
      )));

      expect(
        find.text('Please select at least one day of the week'),
        findsOneWidget,
      );
    });
  });

  group('RecurrenceForm – initialIsRecurring=false', () {
    testWidgets('checkbox is unchecked by default', (tester) async {
      // Confirms the Checkbox widget value is false when not pre-set.
      await tester.pumpWidget(_wrap(RecurrenceForm(onChanged: ({
        bool? isRecurring,
        String? recurrenceType,
        List<bool>? daysOfWeek,
        int? interval,
        int? count,
        DateTime? startDate,
        DateTime? endDate,
        int? dayOfMonth,
        bool? applyToSeries,
      }) {})));
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, isFalse);
    });
  });

  // Cases merged from calendar_assistant/recurrence_form_test.dart.
  group('merged from calendar_assistant/recurrence_form_test.dart', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    group('RecurrenceForm Widget', () {
      void verifyCalled(_OnChangedMock mock) {
        verify(
          mock.call(
            isRecurring: anyNamed('isRecurring'),
            recurrenceType: anyNamed('recurrenceType'),
            daysOfWeek: anyNamed('daysOfWeek'),
            interval: anyNamed('interval'),
            count: anyNamed('count'),
            startDate: anyNamed('startDate'),
            endDate: anyNamed('endDate'),
            dayOfMonth: anyNamed('dayOfMonth'),
            applyToSeries: anyNamed('applyToSeries'),
          ),
        ).called(greaterThan(0));
      }

      testWidgets('renders and toggles Recurring Task checkbox', (tester) async {
        final mockCallback = _OnChangedMock();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RecurrenceForm(onChanged: mockCallback.call)),
          ),
        );

        expect(find.text('Recurring Task'), findsOneWidget);

        await tester.tap(find.text('Recurring Task'));
        await tester.pumpAndSettle();

        verifyCalled(mockCallback);
        expect(find.text('Recurrence Type'), findsOneWidget);
      });

      testWidgets('selecting recurrence type updates state', (tester) async {
        final mockCallback = _OnChangedMock();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RecurrenceForm(onChanged: mockCallback.call)),
          ),
        );

        await tester.tap(find.text('Recurring Task'));
        await tester.pumpAndSettle();

        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Weekly').last);
        await tester.pumpAndSettle();

        verifyCalled(mockCallback);
        expect(find.text('Select Days of Week'), findsOneWidget);
      });

      testWidgets('weekly recurrence allows selecting days of week', (
        tester,
      ) async {
        final mockCallback = _OnChangedMock();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecurrenceForm(
                onChanged: mockCallback.call,
                initialIsRecurring: true,
                initialRecurrenceType: 'Weekly',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('Mon'));
        await tester.pumpAndSettle();

        verifyCalled(mockCallback);
      });

      testWidgets('monthly recurrence allows selecting day of month', (
        tester,
      ) async {
        final mockCallback = _OnChangedMock();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecurrenceForm(
                onChanged: mockCallback.call,
                initialIsRecurring: true,
                initialRecurrenceType: 'Monthly',
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Day of Month:'), findsOneWidget);
        await tester.tap(find.byType(DropdownButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5').last);
        await tester.pumpAndSettle();

        verifyCalled(mockCallback);
      });

      testWidgets('applyToSeries checkbox triggers callback', (tester) async {
        final mockCallback = _OnChangedMock();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecurrenceForm(
                onChanged: mockCallback.call,
                initialIsRecurring: true,
                initialRecurrenceType: 'Daily',
                showApplyToSeries: true,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        await tester.tap(find.text('Apply changes to entire series'));
        await tester.pumpAndSettle();

        verifyCalled(mockCallback);
      });

      testWidgets('yearly recurrence allows selecting year', (tester) async {
        final mockCallback = _OnChangedMock();
        final now = DateTime.now();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecurrenceForm(
                onChanged: mockCallback.call,
                initialIsRecurring: true,
                initialRecurrenceType: 'Yearly',
                initialStartDate: now,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        expect(find.text('Ends in Year:'), findsOneWidget);
        await tester.tap(find.byType(DropdownButton<int>));
        await tester.pumpAndSettle();

        await tester.tap(find.text((now.year + 1).toString()).last);
        await tester.pumpAndSettle();

        verifyCalled(mockCallback);
      });

      testWidgets('shows validation when missing recurrence type', (
        tester,
      ) async {
        final mockCallback = _OnChangedMock();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecurrenceForm(
                onChanged: mockCallback.call,
                initialIsRecurring: true,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text('Please select a recurrence type'), findsOneWidget);
      });
    });
  });
}
