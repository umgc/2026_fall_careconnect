// Widget tests for lib/features/help/presentation/widgets/help_article_content.dart.
import 'package:care_connect_app/features/help/presentation/widgets/help_article_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_test_catalog.dart';
import '../../../../test_support/help_widget_harness.dart';

void main() {
  final catalog = createHelpTestCatalog();
  final article = catalog.findArticle(firstHelpTestId)!;

  Future<List<String>> pumpContent(WidgetTester tester) async {
    final opened = <String>[];
    await pumpHelpWidget(
      tester,
      // The article page scrolls this content, so the test does too.
      (_) => Scaffold(
        body: SingleChildScrollView(
          child: HelpArticleContent(
            article: article,
            repository: catalog,
            onArticleSelected: opened.add,
          ),
        ),
      ),
    );
    return opened;
  }

  testWidgets('renders the title, paragraph, numbered steps and tips',
      (tester) async {
    await pumpContent(tester);
    expect(find.text('First guide'), findsWidgets);
    expect(find.text('A helpful paragraph.'), findsOneWidget);
    expect(find.textContaining('First action'), findsOneWidget);
    expect(find.textContaining('Second action'), findsOneWidget);
    expect(find.text('Troubleshooting'), findsWidgets);
    expect(find.textContaining('Something failed'), findsWidgets);
    expect(find.textContaining('Try this fix'), findsWidgets);
  });

  testWidgets('a related guide opens by its ID', (tester) async {
    final opened = await pumpContent(tester);
    expect(find.text('Related articles'), findsWidgets);
    final related = find.text('Second guide');
    await tester.ensureVisible(related.last);
    await tester.tap(related.last);
    await tester.pump();
    expect(opened, [secondHelpTestId]);
  });
}
