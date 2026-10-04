# Help Center feature

Help lives under Settings > General > Help at `/help`. Any article can be opened
at `/help/articles/:articleId`; article paths use permanent IDs rather than titles.

```text
help/
  models/                 Articles, categories, audience roles, and typed sections
  data/
    help_content_ids.dart Permanent IDs shared by content and screens
    bundled_help_content.dart Local article and category entries
    help_repository.dart  Validated catalog and lookups by ID
  help_routes.dart         Shared stable route paths
  presentation/
    pages/                Screens and navigation
    widgets/              Reusable article presentation
```

The initial catalog is compiled into the app as local Dart data. It requires no
backend request, credentials, database, new dependency, or asset download. Help
remains readable without a network connection. The activities described by
future articles may still require connectivity.

The home screen lists Opening Help and Reading Help articles. Selecting either
opens the same reusable article screen. Related links open another article by
ID, and unknown IDs display a return-to-Help-Center action. Patient-focused
featured articles, category navigation, and search are later steps.

## Add content

1. Add a lowercase, hyphen-separated ID to `help_content_ids.dart`.
2. Add a `HelpCategory` to `bundledHelpCategories` if creating a new topic.
3. Add a `HelpArticle` to `bundledHelpArticles`, using the category's ID. Supply
   its title, summary (short description), relevant `HelpRole` values, and sections.
4. Run `flutter test test/features/help --no-pub`.

Supported sections:

- `HelpParagraph`: a paragraph, optionally with a heading.
- `HelpSteps`: a list of steps, rendered with numbering by the shared widget.
- `HelpTroubleshooting`: problem/solution tips.
- `HelpRelatedArticles`: related article IDs; link labels use current titles.

All sections support optional headings. Generic Troubleshooting and Related
articles headings use app localization when no custom heading is supplied.
Article roles are audience metadata for future home-screen filtering, not access
control. Roles cover Patient, Caregiver, Family Member, and Admin audiences.

```dart
HelpArticle(
  id: 'example-guide',
  categoryId: HelpCategoryIds.gettingStarted,
  title: 'Example guide',
  summary: 'A short description of the guide.',
  roles: [HelpRole.patient, HelpRole.caregiver],
  sections: [
    const HelpParagraph(text: 'An introductory paragraph.'),
    HelpSteps(steps: ['First action.', 'Second action.']),
    HelpTroubleshooting(tips: [
      const HelpTroubleshootingTip(problem: 'A problem.', solution: 'A solution.'),
    ]),
    HelpRelatedArticles(articleIds: [HelpArticleIds.openingHelp]),
  ],
)
```

IDs are permanent and independent of display text. For example, keep
`opening-help` when changing the article title. Article/category routes and
related links should use these IDs, never titles or list positions. The repository
rejects duplicate IDs, invalid URL slugs, missing category/related-article
references, and articles with no roles or sections. Related links can point to
articles declared later in the catalog. Missing ID lookups return null.

Models defensively copy roles, sections, steps, tips, and related IDs into
unmodifiable collections. Callers cannot mutate published content after the
catalog is validated.

`HelpArticleContent` renders sections and delegates related-link selection to
its caller. `HelpArticlePage` resolves an ID through the repository and owns
article navigation. Both screens accept a catalog for previews and tests; their
default is the bundled catalog. Future screens should use the same repository API.

The starter article content is English. Screen labels use the existing app
localization system. Future translated catalogs should preserve the same IDs
across locales; translation must not affect article links.
