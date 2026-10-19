import 'package:care_connect_app/features/tasks/presentation/widgets/add_task_button.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Helpers from features/tasks/widgets/add_task_button_test.dart (merged) ──

Widget _wrap(Widget child, {double width = 800}) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: SizedBox(
            width: width,
            child: child,
          ),
        ),
      ),
    );

void main() {
  group('AddTaskButton Widget', () {
    testWidgets('renders labeled button on wide screens', (tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 800)), // wide screen
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 800,
                  height: 600,
                  child: AddTaskButton(onPressed: () => pressed = true),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // The button should show label text
      expect(find.text('Add Task'), findsOneWidget);

      // Tap by text (safe even if Flutter changes internal class)
      await tester.tap(find.text('Add Task'));
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
    });

    testWidgets('renders icon-only button on compact screens', (tester) async {
      bool pressed = false;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(300, 800)), // narrow screen
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 600,
                  child: AddTaskButton(onPressed: () => pressed = true),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show only the icon version (no text)
      expect(find.byType(IconButton), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Add Task'), findsNothing);

      // Tap the icon and verify callback fired
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(pressed, isTrue);
    });

    testWidgets('wide screen shows ElevatedButton', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 800)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 800,
                  height: 600,
                  child: AddTaskButton(onPressed: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ElevatedButton), findsOneWidget);
    });

    testWidgets('wide screen shows add icon in button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 800)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 800,
                  height: 600,
                  child: AddTaskButton(onPressed: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('compact screen does NOT show Add Task text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(300, 800)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 600,
                  child: AddTaskButton(onPressed: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add Task'), findsNothing);
    });

    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(size: Size(600, 800)),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 600,
                  child: AddTaskButton(onPressed: () {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddTaskButton), findsOneWidget);
    });
  });

  // Cases merged from features/tasks/widgets/add_task_button_test.dart.
  group('merged from features/tasks/widgets/add_task_button_test.dart', () {
    group('AddTaskButton – wide screen (≥ 500 px)', () {
      testWidgets('renders without crashing', (tester) async {
        // Verifies the widget builds without error on a wide screen.
        await tester.pumpWidget(_wrap(AddTaskButton(onPressed: () {})));
        expect(find.byType(AddTaskButton), findsOneWidget);
      });

      testWidgets('shows "Add Task" label on wide screen', (tester) async {
        // Wide screens should show the full labelled ElevatedButton.icon.
        await tester.pumpWidget(_wrap(AddTaskButton(onPressed: () {})));
        expect(find.text('Add Task'), findsOneWidget);
      });

      testWidgets('shows add icon on wide screen', (tester) async {
        // The add icon is part of the ElevatedButton.icon on wide screens.
        await tester.pumpWidget(_wrap(AddTaskButton(onPressed: () {})));
        expect(find.byIcon(Icons.add), findsOneWidget);
      });

      testWidgets('shows ElevatedButton on wide screen', (tester) async {
        // Wide screens use ElevatedButton (not plain IconButton).
        await tester.pumpWidget(_wrap(AddTaskButton(onPressed: () {})));
        expect(find.byType(ElevatedButton), findsOneWidget);
      });

      testWidgets('invokes callback when tapped on wide screen',
          (tester) async {
        // Verifies the onPressed callback fires on tap.
        var tapped = false;
        await tester.pumpWidget(_wrap(AddTaskButton(onPressed: () {
          tapped = true;
        })));
        await tester.tap(find.byType(ElevatedButton));
        expect(tapped, isTrue);
      });
    });

    group('AddTaskButton – compact screen (< 500 px)', () {
      testWidgets('renders without crashing on compact screen', (tester) async {
        // Verifies the widget builds on a phone-width screen.
        await tester.pumpWidget(_wrap(
          AddTaskButton(onPressed: () {}),
          width: 400,
        ));
        expect(find.byType(AddTaskButton), findsOneWidget);
      });

      testWidgets('shows IconButton on compact screen', (tester) async {
        // Compact screens should use a plain IconButton to save space.
        await tester.pumpWidget(_wrap(
          AddTaskButton(onPressed: () {}),
          width: 400,
        ));
        expect(find.byType(IconButton), findsOneWidget);
      });

      testWidgets('does NOT show "Add Task" label on compact screen',
          (tester) async {
        // Compact screens must NOT show the text label.
        await tester.pumpWidget(_wrap(
          AddTaskButton(onPressed: () {}),
          width: 400,
        ));
        expect(find.text('Add Task'), findsNothing);
      });

      testWidgets('invokes callback when tapped on compact screen',
          (tester) async {
        // Verifies the onPressed callback fires on compact screen too.
        var tapped = false;
        await tester.pumpWidget(_wrap(
          AddTaskButton(onPressed: () {
            tapped = true;
          }),
          width: 400,
        ));
        await tester.tap(find.byType(IconButton));
        expect(tapped, isTrue);
      });
    });
  });
}
