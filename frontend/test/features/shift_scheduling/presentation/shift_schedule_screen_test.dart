// Tests for CaregiverShiftSchedulingScreen
// (lib/features/shift_scheduling/presentation/shift_schedule_screen.dart).
//
// Pure StatefulWidget — no API calls, no Provider.
// Contains a SwitchListTile for recurring toggle, Start/End time pickers,
// ChoiceChips for days of the week, and a Save ElevatedButton.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/shift_schedule_screen.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/calendar_view.dart';
import 'package:care_connect_app/features/shift_scheduling/presentation/widgets/schedule_visit_dialog.dart';
import 'package:care_connect_app/services/api_client.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Returns an empty calendar for any request — keeps CalendarView off the network.
class _EmptyCalendarAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode({'days': {}}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const MethodChannel _connectivityChannel =
    MethodChannel('dev.fluttercommunity.plus/connectivity');

void main() {
  group('CaregiverShiftSchedulingScreen', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the screen builds without error.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.byType(CaregiverShiftSchedulingScreen), findsOneWidget);
    });

    testWidgets('shows "Caregiver Shift Scheduling" in AppBar', (tester) async {
      // The AppBar title must identify the screen.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('Caregiver Shift Scheduling'), findsOneWidget);
    });

    testWidgets('shows "Recurring Shift" SwitchListTile', (tester) async {
      // The recurring shift toggle must be visible.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('Recurring Shift'), findsOneWidget);
    });

    testWidgets('recurring shift toggle is OFF by default', (tester) async {
      // The switch starts unchecked (isRecurring = false).
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      final switchTile = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchTile.value, isFalse);
    });

    testWidgets('toggling switch turns recurring ON', (tester) async {
      // Tapping the SwitchListTile calls setState and flips the value.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      final switchTile = tester.widget<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      expect(switchTile.value, isTrue);
    });

    testWidgets('shows "Start Time" label', (tester) async {
      // The Start Time section header must be visible.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('Start Time'), findsOneWidget);
    });

    testWidgets('shows "End Time" label', (tester) async {
      // The End Time section header must be visible.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('End Time'), findsOneWidget);
    });

    testWidgets('shows "No time selected" for start time initially',
        (tester) async {
      // Before any time is picked, the ListTile shows a placeholder.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('No time selected'), findsWidgets);
    });

    testWidgets('shows "Days" section label', (tester) async {
      // The days-of-the-week section header must be present.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('Days'), findsOneWidget);
    });

    testWidgets('shows 7 ChoiceChips for days of the week', (tester) async {
      // One ChoiceChip per day: S M T W T F S.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.byType(ChoiceChip), findsNWidgets(7));
    });

    testWidgets('no day chip is selected by default', (tester) async {
      // selectedDayIndexes starts empty, so all chips are unselected.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.every((c) => c.selected == false), isTrue);
    });

    testWidgets('tapping a day chip selects it', (tester) async {
      // Selecting the first chip (Sunday) marks it as selected.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pump();
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect(chips.first.selected, isTrue);
    });

    testWidgets('shows ElevatedButton "Save"', (tester) async {
      // The Save button must be visible at the bottom.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('shows at least one access_time icon', (tester) async {
      // Each time picker tile has an access_time leading icon.
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.byIcon(Icons.access_time), findsWidgets);
    });

    testWidgets('tapping start time tile opens time picker', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      // Tap the first "No time selected" text (start time ListTile)
      await tester.tap(find.text('No time selected').first);
      await tester.pumpAndSettle();
      // TimePicker dialog should appear — look for the dialog
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('selecting start time updates display', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      await tester.tap(find.text('No time selected').first);
      await tester.pumpAndSettle();
      // Find and tap the OK/confirm button in the dialog
      final okFinder = find.widgetWithText(TextButton, 'OK');
      if (okFinder.evaluate().isNotEmpty) {
        await tester.tap(okFinder);
      } else {
        // Try material 3 style
        await tester.tap(find.text('OK'));
      }
      await tester.pumpAndSettle();
      // One "No time selected" should remain (end time)
      expect(find.text('No time selected'), findsOneWidget);
    });

    testWidgets('tapping end time tile opens time picker', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      await tester.tap(find.text('No time selected').at(1));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('selecting end time updates display', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      await tester.tap(find.text('No time selected').at(1));
      await tester.pumpAndSettle();
      final okFinder = find.widgetWithText(TextButton, 'OK');
      if (okFinder.evaluate().isNotEmpty) {
        await tester.tap(okFinder);
      } else {
        await tester.tap(find.text('OK'));
      }
      await tester.pumpAndSettle();
      expect(find.text('No time selected'), findsOneWidget);
    });

    testWidgets('cancelling time picker does not update time', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      await tester.tap(find.text('No time selected').first);
      await tester.pumpAndSettle();
      final cancelFinder = find.widgetWithText(TextButton, 'Cancel');
      if (cancelFinder.evaluate().isNotEmpty) {
        await tester.tap(cancelFinder);
      } else {
        await tester.tap(find.text('CANCEL'));
      }
      await tester.pumpAndSettle();
      expect(find.text('No time selected'), findsNWidgets(2));
    });

    testWidgets('tapping selected day chip deselects it', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      // Select first chip
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pump();
      expect(
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).first.selected,
        isTrue,
      );
      // Deselect it
      await tester.tap(find.byType(ChoiceChip).first);
      await tester.pump();
      expect(
        tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).first.selected,
        isFalse,
      );
    });

    testWidgets('can select multiple day chips', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      // Select first and third chips
      await tester.tap(find.byType(ChoiceChip).at(0));
      await tester.pump();
      await tester.tap(find.byType(ChoiceChip).at(2));
      await tester.pump();
      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips[0].selected, isTrue);
      expect(chips[1].selected, isFalse);
      expect(chips[2].selected, isTrue);
    });

    testWidgets('tapping Save pops the screen', (tester) async {
      // Wrap with a Navigator so pop() has somewhere to go
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CaregiverShiftSchedulingScreen(),
              ),
            ),
            child: const Text('Go'),
          ),
        ),
      ));
      // Navigate to the shift screen
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.byType(CaregiverShiftSchedulingScreen), findsOneWidget);
      // Tap Save
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      // Should have popped back
      expect(find.byType(CaregiverShiftSchedulingScreen), findsNothing);
      expect(find.text('Go'), findsOneWidget);
    });

    testWidgets('shows two Card widgets for time pickers', (tester) async {
      await tester.pumpWidget(
          _wrap(const CaregiverShiftSchedulingScreen()));
      expect(find.byType(Card), findsNWidgets(2));
    });
  });

  group('ShiftScheduleScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_secureStorageChannel, (call) async {
        if (call.method == 'readAll') return <String, String>{};
        return null;
      });
      messenger.setMockMethodCallHandler(_connectivityChannel, (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      });
      ApiClient.instance.debugSetHttpClientAdapter(_EmptyCalendarAdapter());
    });

    tearDown(() {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(_secureStorageChannel, null);
      messenger.setMockMethodCallHandler(_connectivityChannel, null);
    });

    testWidgets('renders a FAB over the calendar', (tester) async {
      await tester.pumpWidget(_wrap(const ShiftScheduleScreen(caregiverId: 1)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byType(CalendarView), findsOneWidget);
    });

    testWidgets('tapping the FAB opens the schedule dialog', (tester) async {
      await tester.pumpWidget(_wrap(const ShiftScheduleScreen(caregiverId: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleVisitDialog), findsOneWidget);
    });

    testWidgets('saving a visit shows a confirmation snackbar', (tester) async {
      await tester.pumpWidget(_wrap(const ShiftScheduleScreen(caregiverId: 1)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'John Doe');
      await tester.enterText(fields.at(1), 'Nursing');
      final createBtn = find.widgetWithText(ElevatedButton, 'Create');
      await tester.ensureVisible(createBtn);
      await tester.tap(createBtn);
      await tester.pump(); // surface the SnackBar

      expect(find.textContaining('Visit saved: John Doe'), findsOneWidget);
    });
  });
}
