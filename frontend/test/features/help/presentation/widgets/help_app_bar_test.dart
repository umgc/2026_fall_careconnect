// Widget tests for lib/features/help/presentation/widgets/help_app_bar.dart.
import 'package:care_connect_app/features/help/presentation/widgets/help_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  testWidgets('shows the page title and the Help navigation buttons',
      (tester) async {
    await pumpHelpWidget(
      tester,
      (context) => Scaffold(
          appBar: helpAppBar(context, title: 'Medications'),
          body: const SizedBox()),
    );
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Help Center Home'), findsOneWidget);
    expect(find.text('Back to Settings'), findsOneWidget);
  });

  testWidgets('at 200% text on a phone the buttons still fit and work',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpHelpWidget(
      tester,
      (context) => Scaffold(
          appBar: helpAppBar(context, title: 'Account'),
          body: const SizedBox()),
      textScaler: const TextScaler.linear(2.0),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Back to Settings'));
    await tester.pumpAndSettle();
    expect(find.text(helpStubText('/settings')), findsOneWidget);
  });
}
