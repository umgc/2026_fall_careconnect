// Widget tests for lib/features/help/presentation/widgets/help_navigation_bar.dart.
import 'package:care_connect_app/features/help/presentation/widgets/help_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  Future<void> pumpBar(WidgetTester tester) =>
      pumpHelpWidget(tester, (_) => const Scaffold(body: HelpNavigationBar()));

  testWidgets('offers Help Center Home and Back to Settings, 48 dp tall',
      (tester) async {
    await pumpBar(tester);
    expect(find.text('Help Center Home'), findsOneWidget);
    expect(find.text('Back to Settings'), findsOneWidget);
    for (final label in ['Help Center Home', 'Back to Settings']) {
      final button = find.ancestor(
          of: find.text(label), matching: find.byType(OutlinedButton));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('Help Center Home goes to /help', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Help Center Home'));
    await tester.pumpAndSettle();
    expect(find.text(helpStubText('/help')), findsOneWidget);
  });

  testWidgets('Back to Settings goes to /settings', (tester) async {
    await pumpBar(tester);
    await tester.tap(find.text('Back to Settings'));
    await tester.pumpAndSettle();
    expect(find.text(helpStubText('/settings')), findsOneWidget);
  });
}
