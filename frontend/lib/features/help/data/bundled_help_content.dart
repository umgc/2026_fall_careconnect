import '../models/help_article.dart';
import '../models/help_category.dart';
import 'help_content_ids.dart';

/// Compiled into the app: reading Help needs no network, database, or plugin.
const bundledHelpCategories = <HelpCategory>[
  HelpCategory(
    id: HelpCategoryIds.gettingStarted,
    title: 'Getting Started',
    description: 'Learn where to find help in CareConnect.',
  ),
];

const bundledHelpArticles = <HelpArticle>[
  HelpArticle(
    id: HelpArticleIds.openingHelp,
    categoryId: HelpCategoryIds.gettingStarted,
    title: 'Opening Help',
    summary: 'Find the Help Center from Settings.',
    body: '1. Open Settings.\n'
        '2. Scroll down to General.\n'
        '3. Select Help, above Offline Persistence.\n\n'
        'Use the back button to return to Settings.',
  ),
];
