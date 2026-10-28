import 'dart:ui' show Tristate;

import 'package:care_connect_app/features/tasks/presentation/widgets/calendar_keyboard_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        home: Scaffold(
          body: ScrollConfiguration(
            behavior: const CalendarKeyboardScrollBehavior(label: 'Calendar'),
            child: child,
          ),
        ),
      );

  testWidgets('Tab reaches the region; arrows, paging, Home and End scroll it',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(SingleChildScrollView(
      controller: controller,
      child: const SizedBox(height: 3000),
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'Calendar scroll region');
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Calendar'))
          .getSemanticsData()
          .flagsCollection.isFocused,
      Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(0));
    final afterArrow = controller.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(afterArrow));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    semantics.dispose();
  });

  testWidgets('page-view arrows move a whole page', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(PageView(
      controller: controller,
      children: const [SizedBox(), SizedBox(), SizedBox()],
    )));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(controller.page, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(controller.page, 0);
  });

  testWidgets('Tab and Shift+Tab leave the region; child controls retain keys',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final before = FocusNode(debugLabel: 'Before');
    final after = FocusNode(debugLabel: 'After');
    final field = FocusNode(debugLabel: 'Field');
    addTearDown(before.dispose);
    addTearDown(after.dispose);
    addTearDown(field.dispose);
    await tester.pumpWidget(app(Column(children: [
      TextButton(
          focusNode: before, onPressed: () {}, child: const Text('Before')),
      Expanded(
          child: SingleChildScrollView(
        controller: controller,
        child: Column(children: [
          TextField(focusNode: field),
          const SizedBox(height: 3000),
        ]),
      )),
      TextButton(
          focusNode: after, onPressed: () {}, child: const Text('After')),
    ])));
    before.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'Calendar scroll region');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(before.hasPrimaryFocus, isTrue);
    field.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(after.hasPrimaryFocus, isTrue);
  });
}
