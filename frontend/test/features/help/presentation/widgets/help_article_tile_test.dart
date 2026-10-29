// Widget tests for lib/features/help/presentation/widgets/help_article_tile.dart.
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:care_connect_app/features/help/presentation/widgets/help_article_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_widget_harness.dart';

void main() {
  final article = HelpArticle(
    id: 'a',
    categoryId: 'c',
    title: 'Recording a dose',
    summary: 'Mark a medicine as taken.',
    roles: [HelpRole.patient],
    sections: const [HelpParagraph(text: 'x')],
  );

  testWidgets('shows the guide in a card with the open-article hint',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await pumpHelpWidget(
      tester,
      (_) => Scaffold(
          body: HelpArticleTile(article: article, onTap: () => taps++)),
    );
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('Recording a dose'), findsOneWidget);
    expect(find.text('Mark a medicine as taken.'), findsOneWidget);
    expect(
        tester.getSemantics(find.text('Recording a dose')),
        isSemantics(
            hint: 'Opens a Help article', isButton: true, hasTapAction: true));

    await tester.tap(find.byType(HelpArticleTile));
    expect(taps, 1);
    semantics.dispose();
  });
}
