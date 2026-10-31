// Tests for WrappingBottomNavigationBar
// (lib/widgets/wrapping_bottom_navigation_bar.dart).
import 'package:care_connect_app/widgets/wrapping_bottom_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const labels = [
    'Home',
    'Patients',
    'Analytics',
    'Schedule',
    'Messages',
    'Menu'
  ];

  Future<List<int>> pumpBar(WidgetTester tester, double width,
      {int selected = 0}) async {
    final taps = <int>[];
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: WrappingBottomNavigationBar(
          labels: labels,
          icons: [for (final _ in labels) const Icon(Icons.circle)],
          selectedIndex: selected,
          onSelected: taps.add,
          selectedColor: Colors.blue,
          unselectedColor: Colors.grey,
        ),
      ),
    ));
    return taps;
  }

  int rowsOf(WidgetTester tester) => {
        for (final l in labels) tester.getTopLeft(find.text(l)).dy.round()
      }.length;

  testWidgets('shows every label in full, one row on a wide screen',
      (tester) async {
    await pumpBar(tester, 1200);
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
    expect(rowsOf(tester), 1);
  });

  testWidgets('wraps onto more rows at 320 px instead of truncating',
      (tester) async {
    await pumpBar(tester, 320);
    expect(rowsOf(tester), greaterThan(1));
    for (final l in labels) {
      expect(find.text(l), findsOneWidget);
    }
  });

  testWidgets('tapping a label reports its index; targets are 48 px tall',
      (tester) async {
    final taps = await pumpBar(tester, 1200);
    await tester.tap(find.text('Messages'));
    expect(taps, [4]);
    final button = find.ancestor(
        of: find.text('Messages'), matching: find.byType(TextButton));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
  });

  testWidgets('the selected item is marked selected for screen readers',
      (tester) async {
    await pumpBar(tester, 1200, selected: 2);
    // The bar's own Semantics wrapper is the ancestor that sets `selected`.
    bool? selectedFor(String label) => tester
        .widgetList<Semantics>(find.ancestor(
            of: find.text(label), matching: find.byType(Semantics)))
        .map((s) => s.properties.selected)
        .firstWhere((s) => s != null, orElse: () => null);
    expect(selectedFor('Analytics'), isTrue);
    expect(selectedFor('Home'), isFalse);
  });
}
