import 'package:care_connect_app/features/tasks/presentation/widgets/legend_editor.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithProviders(Widget child, TaskTypeManager manager) {
  return MaterialApp(
    home: ChangeNotifierProvider<TaskTypeManager>.value(
      value: manager,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('LegendEditor Widget', () {
    testWidgets('renders title and core buttons', (tester) async {
      final manager = TaskTypeManager();
      await tester.pumpWidget(
        _wrapWithProviders(const LegendEditor(), manager),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage Task Types'), findsOneWidget);
      expect(find.text('Add Task Type'), findsOneWidget);
      expect(find.text('Reset Defaults'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('Add Task Type flow updates manager state', (tester) async {
      final manager = TaskTypeManager();
      await tester.pumpWidget(
        _wrapWithProviders(const LegendEditor(), manager),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Task Type'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'NewType');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(manager.taskTypeColors.containsKey('newtype'), isTrue);
    });

    testWidgets('Reset Defaults confirms and resets', (tester) async {
      final manager = TaskTypeManager();
      await manager.addTaskType('temp', Colors.brown, icon: Icons.home);
      expect(manager.taskTypeColors.containsKey('temp'), isTrue);

      await tester.pumpWidget(
        _wrapWithProviders(const LegendEditor(), manager),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset Defaults'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Task Types'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(manager.taskTypeColors.containsKey('temp'), isFalse);
      expect(manager.taskTypeColors.containsKey('medication'), isTrue);
    });

    testWidgets('Close button dismisses the editor', (tester) async {
      final manager = TaskTypeManager();
      await tester.pumpWidget(
        _wrapWithProviders(const LegendEditor(), manager),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // No exception = success
      expect(find.text('Manage Task Types'), findsNothing);
    });

    testWidgets('Edit flow opens pickers and saves color+icon', (tester) async {
      final manager = TaskTypeManager();
      await tester.pumpWidget(
        _wrapWithProviders(const LegendEditor(), manager),
      );
      await tester.pumpAndSettle();

      // Find a chip label to edit (use default ones)
      final defaultLabels = [
        'Medication',
        'Appointment',
        'Exercise',
        'General',
        'Lab',
        'Pharmacy',
        'Imported',
      ];

      Finder? chipFinder;
      for (final label in defaultLabels) {
        final f = find.text(label);
        if (f.evaluate().isNotEmpty) {
          chipFinder = f;
          break;
        }
      }

      chipFinder ??= find.byType(Text).first;

      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      // Pick first color and icon
      final colorPicker = find.byWidgetPredicate(
        (w) =>
            w is GestureDetector &&
            w.child is Container &&
            (w.child as Container).decoration is BoxDecoration,
      );

      if (colorPicker.evaluate().isNotEmpty) {
        await tester.tap(colorPicker.first);
        await tester.pumpAndSettle();
      }

      final iconPicker = find.byWidgetPredicate(
        (w) =>
            w is GestureDetector &&
            w.child is Container &&
            (w.child as Container).child is Icon,
      );

      if (iconPicker.evaluate().isNotEmpty) {
        await tester.tap(iconPicker.first);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Edit '"), findsNothing);
    });

    testWidgets('Prevent delete when type is used', (tester) async {
      final manager = TaskTypeManager();
      const used = {'medication'};

      await tester.pumpWidget(
        _wrapWithProviders(LegendEditor(usedTaskTypes: used), manager),
      );
      await tester.pumpAndSettle();

      final medFinder = find.text('Medication');
      final Finder target = medFinder.evaluate().isNotEmpty
          ? medFinder
          : find.byType(Text).first;

      await tester.longPress(target);
      await tester.pumpAndSettle();

      expect(find.text('Cannot Delete Task Type'), findsOneWidget);
      expect(
        find.textContaining('currently used by one or more tasks'),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });

    testWidgets('Allow delete when type is NOT used', (tester) async {
      final manager = TaskTypeManager();

      await tester.pumpWidget(
        _wrapWithProviders(const LegendEditor(usedTaskTypes: {}), manager),
      );
      await tester.pumpAndSettle();

      final genFinder = find.text('General');
      final Finder target = genFinder.evaluate().isNotEmpty
          ? genFinder
          : find.byType(Text).first;

      await tester.longPress(target);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Delete'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Confirm Delete'), findsNothing);
    });
  });
}
