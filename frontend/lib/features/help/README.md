# Help Center feature

Help lives under Settings > General > Help at `/help`. Any article can be opened
at `/help/articles/:articleId`; article paths use permanent IDs rather than titles.
Topics open at `/help/topics/:categoryId`.

```text
help/
  models/                 Articles, categories, audience roles, and typed sections
  data/
    help_content_ids.dart Permanent IDs shared by content and screens
    help_home_config.dart Explicit Patient Popular Help ordering
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

The Patient-focused home shows Help Center, a search field, Popular Help, and
Browse Topics. The six popular guides appear in the explicit order in
`patientPopularHelpArticleIds`, independent of catalog declaration order or
titles. This is an editorial selection, not a measured usage ranking. Future
ranking logic can replace selection without changing article content or routes.

Search matches all query words, ignoring case and extra whitespace, against
Patient article titles, summaries, topic titles, section headings, paragraphs,
steps, and troubleshooting tips. Results keep catalog order. While searching,
results replace the popular/topic lists; clearing search restores the home.
Browse Topics includes only categories with Patient articles and opens a separate
topic screen. All article entries use `HelpArticleTile` and open the existing
reusable article screen. Related links resolve by ID. Unknown article/topic IDs
offer a return-to-Help-Center action.

The existing Opening Help and Reading Help articles remain available through
Getting Started and search. No content ID from earlier steps was removed.

The Daily Check-In guide describes the current native app's mock submission:
the confirmation does not save or send mood/notes. It directs users to Messages
to share an update. Review this guide when real check-in submission ships.

## Add content

1. Add a lowercase, hyphen-separated ID to `help_content_ids.dart`.
2. Add a `HelpCategory` to `bundledHelpCategories` if creating a new topic.
3. Add a `HelpArticle` to `bundledHelpArticles`, using the category's ID. Supply
   its title, summary (short description), relevant `HelpRole` values, and sections.
4. To feature a Patient guide, add its ID to `patientPopularHelpArticleIds` at
   the intended position. Each selected article must include `HelpRole.patient`.
5. Run `flutter test test/features/help --no-pub`.

Supported sections:

- `HelpParagraph`: a paragraph, optionally with a heading.
- `HelpSteps`: a list of steps, rendered with numbering by the shared widget.
- `HelpTroubleshooting`: problem/solution tips.
- `HelpRelatedArticles`: related article IDs; link labels use current titles.

All sections support optional headings. Generic Troubleshooting and Related
articles headings use app localization when no custom heading is supplied.
Article roles filter the Patient home, search, and topic screens; they are not
access control. Direct article links remain readable for any role. The Help home
is Patient-focused even when opened by a different account role. Roles cover
Patient, Caregiver, Family Member, and Admin audiences.

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
Popular selections also reject missing or duplicate article IDs.

Models defensively copy roles, sections, steps, tips, and related IDs into
unmodifiable collections. Callers cannot mutate published content after the
catalog is validated.

`HelpArticleContent` renders sections and delegates related-link selection to
its caller. `HelpArticlePage` resolves an ID through the repository and owns
article navigation. All Help screens accept a catalog for previews and tests;
their default is the bundled catalog. For custom catalogs, pass
`popularArticleIds` to the repository to select home entries explicitly.
Future screens should use the same repository API.

The starter article content is English. Screen labels use the existing app
localization system. Future translated catalogs should preserve the same IDs
across locales; translation must not affect article links.
