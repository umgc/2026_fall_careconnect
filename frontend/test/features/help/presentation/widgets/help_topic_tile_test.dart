// Widget tests for lib/features/help/presentation/widgets/help_topic_tile.dart.
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_topic_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  const category = HelpCategory(
      id: 'medications',
      title: 'Medications',
      description: 'Doses, reminders and refills.');

  testWidgets('shows the topic with the open-topic hint and reports a tap',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
          body: HelpTopicTile(category: category, onTap: () => taps++)),
    );
    expect(find.text('Medications'), findsOneWidget);
    expect(find.text('Doses, reminders and refills.'), findsOneWidget);
    expect(
        tester.getSemantics(find.text('Medications')),
        isSemantics(
            hint: 'Opens articles in this topic',
            isButton: true,
            hasTapAction: true));

    await tester.tap(find.byType(HelpTopicTile));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('passes its focus node to the tile', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
          body: HelpTopicTile(
              category: category, onTap: () {}, focusNode: focus)),
    );
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });
}
