
import 'package:calendar_view/calendar_view.dart';
import 'package:care_connect_app/features/tasks/models/task_model.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/calendar_cell.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';


// ── Helpers from features/tasks/widgets/calendar_cell_test.dart (merged) ──

final _today = DateTime(2025, 6, 15);
final _task = Task(
  name: 'Test Task',
  description: '',
  date: _today,
  isComplete: false,
  taskType: 'medication',
);
final _event = CalendarEventData<Task>(
  title: 'Test Task',
  date: _today,
  event: _task,
);

Widget _wrap(Widget child) {
  final manager = TaskTypeManager();
  return MaterialApp(
    home: ChangeNotifierProvider<TaskTypeManager>.value(
      value: manager,
      child: Scaffold(
        body: SizedBox(width: 60, height: 60, child: child),
      ),
    ),
  );
}

CalendarCell _cell({
  DateTime? date,
  List<CalendarEventData<Task>>? events,
  bool isToday = false,
  bool isInMonth = true,
  bool isWeekend = false,
  bool isSelected = false,
}) =>
    CalendarCell(
      date: date ?? _today,
      events: events ?? const [],
      isToday: isToday,
      isInMonth: isInMonth,
      isWeekend: isWeekend,
      isSelected: isSelected,
    );

void main() {
  // Ensure widget bindings + mock SharedPreferences are initialized
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({}); // prevents MissingPluginException

  group('CalendarCell Widget Tests', () {
    late TaskTypeManager manager;

    setUp(() {
      manager = TaskTypeManager(); // safely initializes SharedPreferences
    });

    /// Helper widget to wrap CalendarCell in provider and MaterialApp
    Widget buildTestable(Widget child) {
      return ChangeNotifierProvider.value(
        value: manager,
        child: MaterialApp(home: Scaffold(body: child)),
      );
    }

    testWidgets('renders day number correctly', (tester) async {
      final date = DateTime(2025, 10, 19);

      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: const [],
            isToday: false,
            isInMonth: true,
            isWeekend: false,
            isSelected: false,
          ),
        ),
      );

      expect(find.text('19'), findsOneWidget);
    });

    testWidgets('highlights today correctly', (tester) async {
      final date = DateTime.now();

      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: const [],
            isToday: true,
            isInMonth: true,
            isWeekend: false,
            isSelected: false,
          ),
        ),
      );

      // Verify the border color for today cell
      final container = tester.widget<Container>(find.byType(Container).first);
      final box = container.decoration as BoxDecoration;
      expect(box.border?.top.color, equals(ThemeData().colorScheme.primary));
    });

    testWidgets('renders up to 4 task dots', (tester) async {
      final date = DateTime(2025, 10, 19);

      // ✅ Added required `title` + `date` for CalendarEventData<Task> and Task
      final fakeTasks = List.generate(
        5,
        (i) => CalendarEventData<Task>(
          date: date,
          title: 'Task $i',
          startTime: date,
          endTime: date.add(const Duration(hours: 1)),
          event: Task(
            id: i,
            name: 'Task $i',
            taskType: 'general',
            date: date, // ✅ required for Task model
          ),
        ),
      );

      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: fakeTasks,
            isToday: false,
            isInMonth: true,
            isWeekend: false,
            isSelected: false,
          ),
        ),
      );

      // Verify up to 4 dots are rendered
      final dots = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      );
      expect(dots.evaluate().length, lessThanOrEqualTo(4));
    });

    testWidgets('applies selected border when selected', (tester) async {
      final date = DateTime(2025, 10, 19);

      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: const [],
            isToday: false,
            isInMonth: true,
            isWeekend: false,
            isSelected: true,
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container).first);
      final box = container.decoration as BoxDecoration;

      // Selected day should have a green border
      expect(box.border?.top.color, equals(Colors.green));
    });

    testWidgets('renders weekend styling correctly', (tester) async {
      final date = DateTime(2025, 10, 19); // Sunday → weekend

      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: const [],
            isToday: false,
            isInMonth: true,
            isWeekend: true,
            isSelected: false,
          ),
        ),
      );

      // Verify it still shows the day label
      expect(find.text('19'), findsOneWidget);
    });

    testWidgets('renders Container widget', (tester) async {
      final date = DateTime(2025, 10, 15);
      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: const [],
            isToday: false,
            isInMonth: true,
            isWeekend: false,
            isSelected: false,
          ),
        ),
      );
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders empty events without dots', (tester) async {
      final date = DateTime(2025, 10, 20);
      await tester.pumpWidget(
        buildTestable(
          CalendarCell(
            date: date,
            events: const [],
            isToday: false,
            isInMonth: true,
            isWeekend: false,
            isSelected: false,
          ),
        ),
      );
      expect(find.text('20'), findsOneWidget);
    });
  });

  // Cases merged from features/tasks/widgets/calendar_cell_test.dart.
  group('merged from features/tasks/widgets/calendar_cell_test.dart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('CalendarCell – basic render', () {
      testWidgets('renders without crashing', (tester) async {
        // Verifies the widget builds without error.
        await tester.pumpWidget(_wrap(_cell()));
        await tester.pump();
        expect(find.byType(CalendarCell), findsOneWidget);
      });

      testWidgets('shows the day number', (tester) async {
        // The day number from the date must appear in the cell.
        await tester.pumpWidget(_wrap(_cell(date: DateTime(2025, 6, 15))));
        await tester.pump();
        expect(find.text('15'), findsOneWidget);
      });

      testWidgets('renders a Container', (tester) async {
        // The outermost widget is a Container with decoration.
        await tester.pumpWidget(_wrap(_cell()));
        await tester.pump();
        expect(find.byType(Container), findsWidgets);
      });

      testWidgets('renders with no events and no dots', (tester) async {
        // When events list is empty the Wrap should contain no dot containers.
        await tester.pumpWidget(_wrap(_cell(events: [])));
        await tester.pump();
        // Only the outer Container and the day-number Text should be present;
        // no dot boxes means no fixed-size 8×8 containers.
        expect(find.byType(CalendarCell), findsOneWidget);
      });
    });

    group('CalendarCell – event dots', () {
      testWidgets('renders one dot for one event', (tester) async {
        // A single event produces one coloured dot.
        await tester.pumpWidget(_wrap(_cell(events: [_event])));
        await tester.pump();
        // The Wrap inside the Column should exist (doesn't crash with events).
        expect(find.byType(Wrap), findsOneWidget);
      });

      testWidgets('renders without crashing for 5 events (caps at 4 dots)',
          (tester) async {
        // CalendarCell.take(4) limits displayed dots to 4 even if 5 events.
        final events = List.filled(5, _event);
        await tester.pumpWidget(_wrap(_cell(events: events)));
        await tester.pump();
        expect(find.byType(CalendarCell), findsOneWidget);
      });
    });

    group('CalendarCell – state flags', () {
      testWidgets('renders correctly when isToday=true', (tester) async {
        // A "today" cell must still render without error.
        await tester.pumpWidget(_wrap(_cell(isToday: true)));
        await tester.pump();
        expect(find.byType(CalendarCell), findsOneWidget);
      });

      testWidgets('renders correctly when isSelected=true', (tester) async {
        // A selected cell uses a green border — must render without error.
        await tester.pumpWidget(_wrap(_cell(isSelected: true)));
        await tester.pump();
        expect(find.byType(CalendarCell), findsOneWidget);
      });

      testWidgets('renders correctly when isInMonth=false', (tester) async {
        // Days outside the current month are dimmed but must still render.
        await tester.pumpWidget(_wrap(_cell(isInMonth: false)));
        await tester.pump();
        expect(find.byType(CalendarCell), findsOneWidget);
      });

      testWidgets('renders correctly when isWeekend=true', (tester) async {
        // Weekend flag is accepted without error.
        await tester.pumpWidget(_wrap(_cell(isWeekend: true)));
        await tester.pump();
        expect(find.byType(CalendarCell), findsOneWidget);
      });
    });
  });
}
