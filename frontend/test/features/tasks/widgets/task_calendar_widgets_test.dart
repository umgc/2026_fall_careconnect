// Tests for task widgets that depend on TaskTypeManager:
//   Legend          (lib/features/tasks/presentation/widgets/legend.dart)
//   LegendEditor    (lib/features/tasks/presentation/widgets/legend_editor.dart)
//
// CalendarCell and EventTile are not tested here because they require
// CalendarEventData from the calendar_view package which is only in
// dependency_overrides (not a direct dependency).
//
// SharedPreferences.setMockInitialValues({}) is used so TaskTypeManager's
// internal SharedPreferences load works without a platform channel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/legend.dart';
import 'package:care_connect_app/features/tasks/presentation/widgets/legend_editor.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

/// Wraps [child] with a MaterialApp and a ChangeNotifierProvider<TaskTypeManager>.
Widget _wrap(Widget child, TaskTypeManager manager) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChangeNotifierProvider<TaskTypeManager>.value(
          value: manager,
          child: child,
        ),
      ),
    );

void main() {
  late TaskTypeManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    manager = TaskTypeManager();
    await Future.delayed(Duration.zero); // let _loadFromPrefs settle
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Legend
  // ─────────────────────────────────────────────────────────────────────────
  group('Legend', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the Legend widget builds without error with a live manager.
      await tester.pumpWidget(_wrap(const Legend(), manager));
      await tester.pump();
      expect(find.byType(Legend), findsOneWidget);
    });

    testWidgets('shows "Task Types" header', (tester) async {
      // The section header must be visible.
      await tester.pumpWidget(_wrap(const Legend(), manager));
      await tester.pump();
      expect(find.text('Task Types'), findsOneWidget);
    });

    testWidgets('shows manage edit icon when showManageButton is true',
        (tester) async {
      // The edit icon is shown by default (showManageButton = true).
      await tester.pumpWidget(_wrap(const Legend(), manager));
      await tester.pump();
      expect(find.byIcon(Icons.edit), findsOneWidget);
    });

    testWidgets('hides manage icon when showManageButton is false',
        (tester) async {
      // Passing showManageButton=false must suppress the edit icon.
      await tester.pumpWidget(
          _wrap(const Legend(showManageButton: false), manager));
      await tester.pump();
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('shows default task type labels', (tester) async {
      // The default types (medication, appointment…) should appear as chips.
      await tester.pumpWidget(_wrap(const Legend(), manager));
      await tester.pump();
      // At least one capitalized type label should be visible.
      expect(find.textContaining('Medication'), findsOneWidget);
    });

    testWidgets('invokes onManage callback when edit tapped', (tester) async {
      // Tapping the manage icon must trigger the onManage callback.
      var managed = false;
      await tester.pumpWidget(
          _wrap(Legend(onManage: () => managed = true), manager));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.edit));
      expect(managed, isTrue);
    });

    testWidgets('shows Card widget', (tester) async {
      // Legend wraps its content in a Card.
      await tester.pumpWidget(_wrap(const Legend(), manager));
      await tester.pump();
      expect(find.byType(Card), findsWidgets);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // LegendEditor
  // ─────────────────────────────────────────────────────────────────────────
  group('LegendEditor', () {
    testWidgets('renders without crashing', (tester) async {
      // Verifies the LegendEditor dialog content builds without error.
      await tester.pumpWidget(_wrap(const LegendEditor(), manager));
      await tester.pump();
      expect(find.byType(LegendEditor), findsOneWidget);
    });

    testWidgets('shows "Task Types" label from nested Legend', (tester) async {
      // The LegendEditor reuses the Legend widget internally.
      await tester.pumpWidget(_wrap(const LegendEditor(), manager));
      await tester.pump();
      expect(find.text('Task Types'), findsWidgets);
    });

    testWidgets('renders a Dialog widget', (tester) async {
      // LegendEditor is displayed as a Dialog.
      await tester.pumpWidget(_wrap(const LegendEditor(), manager));
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
    });
  });
}
