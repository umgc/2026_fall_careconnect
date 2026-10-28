// Widget tests for lib/features/help/presentation/widgets/help_glossary_entry.dart.
import 'package:care_connect_app/features/help/models/help_glossary_term.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_glossary_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  final term = HelpGlossaryTerm(
    id: 'caregiver',
    term: 'Caregiver',
    definition: 'A person who helps you manage your care.',
    aliases: const ['carer'],
  );

  testWidgets('an entry shows the word as a heading and its definition',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpHelpWidget(
      tester,
      (_) =>
          Scaffold(body: ListView(children: [HelpGlossaryEntry(term: term)])),
    );
    expect(find.text('Caregiver'), findsOneWidget);
    expect(
        find.text('A person who helps you manage your care.'), findsOneWidget);
    expect(tester.getSemantics(find.text('Caregiver')),
        isSemantics(isHeader: true));
    semantics.dispose();
  });

  testWidgets('an entry shows the guides it is given', (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
          body: ListView(children: [
        HelpGlossaryEntry(term: term, guides: const [Text('A related guide')]),
      ])),
    );
    expect(find.text('A related guide'), findsOneWidget);
  });

  testWidgets('a search result tile shows the word and reports a tap',
      (tester) async {
    var taps = 0;
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
          body: HelpGlossaryResultTile(term: term, onTap: () => taps++)),
    );
    expect(find.text('Caregiver'), findsOneWidget);
    await tester.tap(find.text('Caregiver'));
    expect(taps, 1);
  });
}
