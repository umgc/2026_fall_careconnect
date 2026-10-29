// Widget tests for lib/features/help/presentation/widgets/help_back_to_top.dart.
import 'package:care_connect_app/features/help/presentation/widgets/help_back_to_top.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  testWidgets('shows "Back to top" and reports a press', (tester) async {
    var presses = 0;
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
          floatingActionButton: HelpBackToTop(onPressed: () => presses++)),
    );
    expect(find.text('Back to top'), findsOneWidget);
    await tester.tap(find.text('Back to top'));
    expect(presses, 1);
  });

  testWidgets('the arrow icon is hidden from screen readers', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(floatingActionButton: HelpBackToTop(onPressed: () {})),
    );
    expect(
        find.ancestor(
            of: find.byIcon(Icons.arrow_upward),
            matching: find.byType(ExcludeSemantics)),
        findsWidgets);
    expect(find.bySemanticsLabel('Back to top'), findsOneWidget);
    semantics.dispose();
  });
}
