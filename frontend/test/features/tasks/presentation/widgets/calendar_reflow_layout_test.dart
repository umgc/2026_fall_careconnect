// Tests for CalendarReflowLayout and CalendarFilterLayout
// (lib/features/tasks/presentation/widgets/calendar_reflow_layout.dart).
import 'package:care_connect_app/features/tasks/presentation/widgets/calendar_reflow_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child,
      {double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: child),
      ),
    ));
  }

  const scrollKey = ValueKey('calendar-page-scroll');

  group('CalendarReflowLayout', () {
    testWidgets('wide and tall: a plain Column, no page scroll',
        (tester) async {
      await pumpAt(
          tester,
          const Size(1200, 900),
          const CalendarReflowLayout(isMonth: true, children: [
            Text('Filters'),
            Expanded(child: Text('Grid')),
          ]));
      expect(find.byKey(scrollKey), findsNothing);
      expect(find.text('Grid'), findsOneWidget);
    });

    testWidgets('320 px wide: scrolls and gives the month grid a fixed height',
        (tester) async {
      await pumpAt(
          tester,
          const Size(320, 640),
          const CalendarReflowLayout(isMonth: true, children: [
            Text('Filters'),
            Expanded(child: Text('Grid')),
          ]));
      expect(find.byKey(scrollKey), findsOneWidget);
      expect(find.byType(Expanded), findsNothing);
      final box = tester.widget<SizedBox>(find
          .ancestor(of: find.text('Grid'), matching: find.byType(SizedBox))
          .first);
      expect(box.height, greaterThan(0));
    });

    testWidgets('200% text on a wide screen also reflows (week view)',
        (tester) async {
      await pumpAt(
          tester,
          const Size(1200, 900),
          const CalendarReflowLayout(isMonth: false, children: [
            Expanded(child: Text('Week')),
          ]),
          textScale: 2);
      expect(find.byKey(scrollKey), findsOneWidget);
      final box = tester.widget<SizedBox>(find
          .ancestor(of: find.text('Week'), matching: find.byType(SizedBox))
          .first);
      expect(box.height, greaterThanOrEqualTo(400));
    });
  });

  group('CalendarFilterLayout', () {
    testWidgets('wide: filter and Today side by side', (tester) async {
      await pumpAt(
          tester,
          const Size(1200, 900),
          const CalendarFilterLayout(children: [
            Flexible(child: Text('Filters')),
            Text('Today'),
          ]));
      expect(find.byType(Flexible), findsOneWidget);
      expect(tester.getTopLeft(find.text('Today')).dy,
          tester.getTopLeft(find.text('Filters')).dy);
    });

    testWidgets('narrow: stacked, Today aligned right', (tester) async {
      await pumpAt(
          tester,
          const Size(320, 640),
          const CalendarFilterLayout(children: [
            Flexible(child: Text('Filters')),
            Text('Today'),
          ]));
      expect(find.byType(Flexible), findsNothing);
      final align = tester.widget<Align>(find
          .ancestor(of: find.text('Today'), matching: find.byType(Align))
          .first);
      expect(align.alignment, Alignment.centerRight);
      expect(tester.getTopLeft(find.text('Today')).dy,
          greaterThan(tester.getTopLeft(find.text('Filters')).dy));
    });
  });
}
