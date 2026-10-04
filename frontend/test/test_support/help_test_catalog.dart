// Shared offline Help fixtures for article rendering and navigation tests.
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';

const firstHelpTestId = 'first-guide';
const secondHelpTestId = 'second-guide';

/// Covers every section type and a related link; override text for scaling tests.
HelpRepository createHelpTestCatalog(
    {String paragraph = 'A helpful paragraph.'}) {
  return HelpRepository(
    popularArticleIds: const [firstHelpTestId, secondHelpTestId],
    categories: const [
      HelpCategory(
          id: 'getting-started', title: 'Getting Started', description: ''),
    ],
    articles: [
      HelpArticle(
        id: firstHelpTestId,
        categoryId: 'getting-started',
        title: 'First guide',
        summary: 'A short description.',
        roles: [HelpRole.patient],
        sections: [
          HelpParagraph(text: paragraph),
          HelpSteps(steps: ['First action', 'Second action']),
          HelpTroubleshooting(tips: [
            const HelpTroubleshootingTip(
                problem: 'Something failed', solution: 'Try this fix'),
          ]),
          HelpRelatedArticles(articleIds: [secondHelpTestId]),
        ],
      ),
      HelpArticle(
        id: secondHelpTestId,
        categoryId: 'getting-started',
        title: 'Second guide',
        summary: 'Another short description.',
        roles: [HelpRole.patient, HelpRole.caregiver],
        sections: const [HelpParagraph(text: 'Another helpful paragraph.')],
      ),
    ],
  );
}
