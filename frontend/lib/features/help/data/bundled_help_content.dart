import '../models/help_article.dart';
import '../models/help_category.dart';
import '../models/help_role.dart';
import '../models/help_section.dart';
import 'help_content_ids.dart';

/// Compiled into the app: reading Help needs no network, database, or plugin.
const bundledHelpCategories = <HelpCategory>[
  HelpCategory(
    id: HelpCategoryIds.gettingStarted,
    title: 'Getting Started',
    description: 'Learn where to find help in CareConnect.',
  ),
];

final bundledHelpArticles = List<HelpArticle>.unmodifiable([
  HelpArticle(
    id: HelpArticleIds.openingHelp,
    categoryId: HelpCategoryIds.gettingStarted,
    title: 'Opening Help',
    summary: 'Find the Help Center from Settings.',
    roles: HelpRole.values,
    sections: [
      const HelpParagraph(
        text: 'The Help Center provides guides for using CareConnect.',
      ),
      HelpSteps(
        heading: 'Open Help',
        steps: [
          'Open Settings.',
          'Scroll down to General.',
          'Select Help, above Offline Persistence.',
        ],
      ),
      HelpTroubleshooting(
        tips: [
          const HelpTroubleshootingTip(
            problem: 'I cannot see the General section.',
            solution: 'Scroll down in Settings until you reach General.',
          ),
        ],
      ),
      HelpRelatedArticles(articleIds: [HelpArticleIds.readingHelp]),
    ],
  ),
  HelpArticle(
    id: HelpArticleIds.readingHelp,
    categoryId: HelpCategoryIds.gettingStarted,
    title: 'Reading Help articles',
    summary: 'Open a guide and follow links to other useful articles.',
    roles: HelpRole.values,
    sections: [
      const HelpParagraph(
        text: 'You can read Help articles without an internet connection. '
            'Some app features described in a guide may still require a connection.',
      ),
      HelpSteps(
        steps: [
          'Select an article on the Help Center home screen.',
          'Follow the numbered steps in the article.',
          'Select a related article to read another guide.',
          'Use the back button to return to the previous screen.',
        ],
      ),
      HelpTroubleshooting(
        tips: [
          const HelpTroubleshootingTip(
            problem: 'An article is unavailable.',
            solution:
                'Return to the Help Center and select an available article.',
          ),
        ],
      ),
      HelpRelatedArticles(articleIds: [HelpArticleIds.openingHelp]),
    ],
  ),
]);
