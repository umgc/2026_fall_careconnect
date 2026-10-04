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
remains readable without a network connection. Activities described by the
articles may still require connectivity. On web, loading/reloading the app itself
can still require a connection; reading the already-loaded catalog does not.

The Patient-focused home shows Help Center, a search field, Popular Help, and
Browse Topics. The six popular guides appear in the explicit order in
`patientPopularHelpArticleIds`, independent of catalog declaration order or
titles. This is an editorial selection, not a measured usage ranking. Future
ranking logic can replace selection without changing article content or routes.

Search matches all query words, ignoring case and extra whitespace, against
Patient article titles, summaries, optional keywords, topic titles, section
headings, paragraphs, steps, and troubleshooting tips. Results keep catalog
order. While searching,
results replace the popular/topic lists; clearing search restores the home.
An empty-result Browse Topics button clears the query, brings topics into view,
and moves keyboard focus to the first topic. Search result counts are announced
through a localized live region. Standard Material controls provide focus
feedback and keyboard activation; article/topic/related links expose button roles
and combined text labels for screen readers.
Browse Topics includes only categories with Patient articles and opens a separate
topic screen. All article entries use `HelpArticleTile` and open the existing
reusable article screen. Related links resolve by ID. Unknown article/topic IDs
offer a return-to-Help-Center action.

The existing Opening Help and Reading Help articles remain available through
Getting Started and search. No content ID from earlier steps was removed.

The Daily Check-In guide describes the current native app's mock submission:
the confirmation does not save or send mood/notes. It directs users to Messages
to share an update. Review this guide when real check-in submission ships.
Reading Help articles explains Windows preview, mobile, and web differences.
See the [content verification record](../../../../docs/help/content-verification.md)
for sources, code-inspection boundaries, and remaining live-platform checks.

## Add content

1. Add a lowercase, hyphen-separated ID to `help_content_ids.dart`.
2. Add a `HelpCategory` to `bundledHelpCategories` if creating a new topic.
3. Add a `HelpArticle` to `bundledHelpArticles`, using the category's ID. Supply
   its title, summary (short description), relevant `HelpRole` values, sections,
   and optional keyword synonyms. Keywords are defensively copied and searched
   locally; existing articles can omit them.
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
  keywords: ['synonym', 'alternate phrase'],
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

New content requires no new screen, widget branch, or route. The existing
`HelpArticlePage` renders every model by ID. The topic screen lists new entries
automatically, and the home lists categories with Patient content.

## Add a category, related link, or featured entry

For a new category, add its permanent constant to `HelpCategoryIds` and its
entry to `bundledHelpCategories`, for example:

```dart
// In HelpCategoryIds:
static const dailyRoutines = 'daily-routines';

// In bundledHelpCategories:
HelpCategory(
  id: HelpCategoryIds.dailyRoutines,
  title: 'Daily Routines',
  description: 'Guides for everyday care tasks.',
),
```

Add an article ID constant, then a `HelpArticle` with that `categoryId`, Patient
roles, and at least one section. Categories display in their configured catalog
order and appear only when they contain relevant articles. Do not add a router
case for the new category.

For related content, add a section to the referring article:

```dart
HelpRelatedArticles(articleIds: [
  HelpArticleIds.recordingDose,
  HelpArticleIds.messagingCaregiver,
]),
```

The target may be declared later in the catalog. Link labels resolve the
target's current title. Use IDs rather than copied titles or URLs; a missing
target fails repository validation.

For a featured article, insert its permanent ID into
`patientPopularHelpArticleIds` in `data/help_home_config.dart` at the desired
position. Do not append duplicates or change an existing ID. Ensure it includes
`HelpRole.patient`; selection filters by audience. Update the ordering test if
the editorial selection intentionally changes. Category and featured
configuration are separate from screen layout and remain bundled offline.

## Required checks when extending content

The [glossary guide](../../../../docs/help/glossary.md) covers the shared 75-term
catalog, plain-language aliases, article definitions, combined search, permanent
term links, and the glossary validation/accessibility checks. Edit definitions
once in `data/bundled_glossary_content.dart`; articles reference them through
`glossaryTermIds`. Glossary guide backlinks are generated from those references.

- Construct `HelpRepository.bundled()` and run `flutter test test/features/help --no-pub`.
  Validation rejects malformed/duplicate IDs, missing categories or related
  targets, missing/duplicate featured targets, and articles without roles or sections.
- Add focused assertions for a new keyword synonym, related link, or intentional
  popular-order change. Keep test catalogs explicit about `popularArticleIds`.
- Check any new instructions against the app and update the content verification
  record with sources, platforms checked, and unresolved instructions.
- Review large text, keyboard access, theme contrast, and supported locales if
  adding or changing presentation. Run `dart analyze lib/features/help test/features/help`.

IDs are permanent and independent of display text. For example, keep
`opening-help` when changing the article title. Article/category routes and
related links should use these IDs, never titles or list positions. The repository
rejects duplicate IDs, invalid URL slugs, missing category/related-article
references, and articles with no roles or sections. Related links can point to
articles declared later in the catalog. Missing ID lookups return null.
Popular selections also reject missing or duplicate article IDs.

Models defensively copy roles, sections, keywords, glossary IDs, aliases, steps, tips, and related IDs
into unmodifiable collections. Callers cannot mutate published content after the
catalog is validated.

`HelpArticleContent` renders sections and delegates related-link selection to
its caller. `HelpArticlePage` resolves an ID through the repository and owns
article navigation. All Help screens accept a catalog for previews and tests;
their default is the bundled catalog. For custom catalogs, pass
`popularArticleIds` to the repository to select home entries explicitly.
Future screens should use the same repository API.

## Complete-flow verification

`test/features/help/help_flow_test.dart` uses the production route definitions
and real Settings/Help screens with test providers and disconnected platform
channels. It refuses HTTP, checks Help's placement, taps the full navigation
sequence, verifies search/fallback recovery, and opens every bundled ID and
related link. Run it with the rest of the focused suite:

```powershell
flutter test test/features/help --no-pub
dart analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

The [Step 9 verification report](../../../../docs/help/verification-step-9.md)
records results, optional readable screenshot capture commands, live Windows
preview checks, and outstanding physical-device/browser/screen-reader checks.
Widget viewport sizes and refused HTTP are automated evidence, not proof of
physical-device disconnection or real assistive-technology behavior.

The starter article content is English. Screen labels use the existing app
localization system. Future translated catalogs should preserve the same IDs
across locales; translation must not affect article links.
See the [localization guide](../../../../docs/help/localization.md) for translating current ARB labels,
the explicit English fallback, and the locale-selection design for future
article/category catalogs. The translated-content resolver described there is
future wiring, not an API available in the current repository.
