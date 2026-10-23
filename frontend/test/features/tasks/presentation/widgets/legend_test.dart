import 'package:care_connect_app/features/tasks/presentation/widgets/legend.dart';
import 'package:care_connect_app/features/tasks/utils/task_type_manager.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrapWithProvider(Widget child, TaskTypeManager manager) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<TaskTypeManager>.value(
      value: manager,
      child: Scaffold(body: child),
    ),
  );
}

// ── Helpers from features/tasks/widgets/legend_test.dart (merged) ──

Widget _wrap(Widget child) {
  final manager = TaskTypeManager();
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: ChangeNotifierProvider<TaskTypeManager>.value(
      value: manager,
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() async {
    // Ensures no SharedPreferences initialization errors
    SharedPreferences.setMockInitialValues({});
  });

  group('Legend Widget', () {
    testWidgets('renders header, icons, and default task types', (
      WidgetTester tester,
    ) async {
      final manager = TaskTypeManager();

      await tester.pumpWidget(_wrapWithProvider(const Legend(), manager));
      await tester.pumpAndSettle();

      // Verify header
      expect(find.text('Task Types'), findsOneWidget);

      // Default task type names
      expect(find.text('Medication'), findsOneWidget);
      expect(find.text('Appointment'), findsOneWidget);
      expect(find.text('Exercise'), findsOneWidget);
      expect(find.text('Lab'), findsOneWidget);
      expect(find.text('Imported'), findsOneWidget);

      // Icons should render
      expect(find.byIcon(Icons.task), findsWidgets);
    });

    testWidgets('tapping manage button triggers onManage callback', (
      WidgetTester tester,
    ) async {
      bool tapped = false;
      final manager = TaskTypeManager();

      await tester.pumpWidget(
        _wrapWithProvider(Legend(onManage: () => tapped = true), manager),
      );

      await tester.pumpAndSettle();

      // Tap edit (manage) icon
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('hides manage button when showManageButton is false', (
      WidgetTester tester,
    ) async {
      final manager = TaskTypeManager();

      await tester.pumpWidget(
        _wrapWithProvider(const Legend(showManageButton: false), manager),
      );

      await tester.pumpAndSettle();

      // Edit icon should not appear
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('invokes onTypeTap when type chip tapped', (
      WidgetTester tester,
    ) async {
      String? tappedType;
      final manager = TaskTypeManager();

      await tester.pumpWidget(
        _wrapWithProvider(
          Legend(onTypeTap: (type) => tappedType = type),
          manager,
        ),
      );

      await tester.pumpAndSettle();

      // Tap one of the task labels (Medication)
      await tester.tap(find.text('Medication'));
      await tester.pumpAndSettle();

      expect(tappedType, isNotNull);
      expect(tappedType!.toLowerCase(), 'medication');
    });

    testWidgets('invokes onTypeLongPress when chip long-pressed', (
      WidgetTester tester,
    ) async {
      String? longPressedType;
      final manager = TaskTypeManager();

      await tester.pumpWidget(
        _wrapWithProvider(
          Legend(onTypeLongPress: (type) => longPressedType = type),
          manager,
        ),
      );

      await tester.pumpAndSettle();

      // Long press one of the task labels
      await tester.longPress(find.text('Appointment'));
      await tester.pumpAndSettle();

      expect(longPressedType, isNotNull);
      expect(longPressedType!.toLowerCase(), 'appointment');
    });
  });

  // Cases merged from features/tasks/widgets/legend_test.dart.
  group('merged from features/tasks/widgets/legend_test.dart', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    group('Legend – default render', () {
      testWidgets('renders without crashing', (tester) async {
        // Verifies the widget builds without error.
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump(); // let TaskTypeManager._loadFromPrefs complete
        expect(find.byType(Legend), findsOneWidget);
      });

      testWidgets('shows "Task Types" header text', (tester) async {
        // The header label must be visible.
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump();
        expect(find.text('Task Types'), findsOneWidget);
      });

      testWidgets('renders a Card', (tester) async {
        // Legend wraps its content in a Card.
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump();
        expect(find.byType(Card), findsOneWidget);
      });

      testWidgets('shows Divider below header', (tester) async {
        // A Divider separates the header from the task-type items.
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump();
        expect(find.byType(Divider), findsOneWidget);
      });

      testWidgets('shows manage IconButton when showManageButton is true',
          (tester) async {
        // Default showManageButton=true renders an edit IconButton.
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump();
        expect(find.byIcon(Icons.edit), findsOneWidget);
      });

      testWidgets('hides manage button when showManageButton is false',
          (tester) async {
        // When showManageButton=false the edit icon must not appear.
        await tester.pumpWidget(_wrap(const Legend(showManageButton: false)));
        await tester.pump();
        expect(find.byIcon(Icons.edit), findsNothing);
      });

      testWidgets('invokes onManage callback when manage button tapped',
          (tester) async {
        // Tapping the edit icon should fire the onManage callback.
        var called = false;
        await tester.pumpWidget(_wrap(Legend(onManage: () => called = true)));
        await tester.pump();
        await tester.tap(find.byIcon(Icons.edit));
        expect(called, isTrue);
      });

      testWidgets('manage button tooltip is "Manage Task Types"',
          (tester) async {
        // The IconButton tooltip must match the expected string.
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump();
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.byIcon(Icons.edit),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, 'Manage Task Types');
      });
    });

    group('Legend – onTypeTap / onTypeLongPress', () {
      testWidgets('wraps items in InkWell when onTypeTap provided',
          (tester) async {
        // When onTypeTap is supplied, each type item is wrapped in InkWell.
        await tester.pumpWidget(_wrap(Legend(onTypeTap: (type) {})));
        await tester.pump();
        expect(find.byType(InkWell), findsWidgets);
      });

      testWidgets('renders more InkWells when callbacks provided than without',
          (tester) async {
        // With callbacks each type item is wrapped in InkWell, so there are more
        // InkWells than in the no-callback case (which only has the IconButton).
        await tester.pumpWidget(_wrap(const Legend()));
        await tester.pump();
        final countWithout = tester.widgetList(find.byType(InkWell)).length;

        await tester.pumpWidget(_wrap(Legend(onTypeTap: (_) {})));
        await tester.pump();
        final countWith = tester.widgetList(find.byType(InkWell)).length;

        expect(countWith, greaterThan(countWithout));
      });
    });
  });
}
