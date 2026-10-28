// Widget tests for lib/features/help/presentation/pages/help_glossary_page.dart.
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_glossary_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  final repository = HelpRepository.bundled();
  final caregiver = repository.findGlossaryTerm('caregiver')!;

  testWidgets('opened on a term, shows that term and its definition',
      (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => HelpGlossaryPage(termId: 'caregiver', repository: repository),
    );
    expect(find.text(caregiver.term), findsWidgets);
    expect(find.text(caregiver.definition), findsOneWidget);
  });

  testWidgets('searching narrows the list to matching words', (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => HelpGlossaryPage(repository: repository),
    );
    await tester.enterText(find.byType(TextField), caregiver.term);
    await tester.pumpAndSettle();
    expect(find.text(caregiver.term), findsWidgets);
    expect(repository.searchGlossary(caregiver.term).first.id, caregiver.id);
  });

  testWidgets('a search with no matches says so instead of an empty page',
      (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => HelpGlossaryPage(repository: repository),
    );
    await tester.enterText(find.byType(TextField), 'zzqqxx');
    await tester.pumpAndSettle();
    expect(find.text(caregiver.definition), findsNothing);
    expect(find.textContaining('zzqqxx'), findsWidgets);
  });
}
