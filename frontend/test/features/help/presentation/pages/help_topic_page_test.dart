// Widget tests for lib/features/help/presentation/pages/help_topic_page.dart.
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:care_connect_app/features/help/presentation/pages/help_topic_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../test_support/help_test_catalog.dart';
import '../../../../test_support/help_widget_harness.dart';

void main() {
  testWidgets('lists the guides in a topic and opens one by its ID',
      (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => HelpTopicPage(
          categoryId: 'getting-started', repository: createHelpTestCatalog()),
    );
    expect(find.text('Getting Started'), findsWidgets);
    expect(find.text('First guide'), findsOneWidget);
    expect(find.text('Second guide'), findsOneWidget);

    await tester.tap(find.text('Second guide'));
    await tester.pumpAndSettle();
    expect(find.text(helpStubText(HelpRoutes.article(secondHelpTestId))),
        findsOneWidget);
  });

  testWidgets('an unknown topic ID shows a not-found title and no guides',
      (tester) async {
    await pumpHelpWidget(
      tester,
      (_) => HelpTopicPage(
          categoryId: 'no-such-topic', repository: createHelpTestCatalog()),
    );
    expect(find.text('First guide'), findsNothing);
    expect(find.text('Help Center Home'), findsOneWidget);
  });
}
