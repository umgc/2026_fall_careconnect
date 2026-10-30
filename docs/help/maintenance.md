# Help Center maintenance handbook

This handbook is for developers maintaining CareConnect's Help Center. It lives
in repository documentation and is not loaded into the app. Code examples below
are authoring templates; verify their instructions against the actual app before
publishing them as Help content.

Paths in the file map are relative to `frontend/lib/features/help/`. Shell
commands specify whether to run from the repository root or `frontend/`.

## Quick task index

| Task | Instructions |
| --- | --- |
| Add or edit a guide | [Articles](#articles) |
| Change paragraphs, steps, troubleshooting, or headings | [Sections and article contents](#sections-and-article-contents) |
| Add or edit a topic; move an article | [Topics and categories](#topics-and-categories) |
| Change Popular Help selection or ordering | [Featured articles and ordering](#featured-articles-and-ordering) |
| Add or edit a meaning, alias, or article term reference | [Glossary](#glossary) |
| Improve search matches | [Search](#search) |
| Remove content or combine entries | [Removal and replacement](#removal-and-replacement) |
| Recover previously removed content | [Restoration](#restoration) |
| Change shared controls or typography | [Presentation and navigation](#presentation-and-navigation) |
| Translate labels or prepare translated content | [Localization](#localization) |
| Refresh a running preview | [Preview and refresh](#preview-and-refresh) |
| Check a change before review | [Validation and review](#validation-and-review) |
| Diagnose a problem | [Troubleshooting](#troubleshooting) |

## Files and responsibilities

| File or directory | Owns |
| --- | --- |
| [`data/bundled_help_content.dart`](../../frontend/lib/features/help/data/bundled_help_content.dart) | Category entries and article content, including roles, keywords, sections, and glossary references. |
| [`data/help_content_ids.dart`](../../frontend/lib/features/help/data/help_content_ids.dart) | Permanent category/article ID constants. |
| [`data/help_home_config.dart`](../../frontend/lib/features/help/data/help_home_config.dart) | Explicit Patient Popular Help selection and ordering. |
| [`data/bundled_glossary_content.dart`](../../frontend/lib/features/help/data/bundled_glossary_content.dart) | Glossary IDs, labels, definitions, aliases, and optional explicit guide links. |
| [`data/help_repository.dart`](../../frontend/lib/features/help/data/help_repository.dart) | Validation, indexing, audience filtering, search, generated definition sections, and glossary backlinks. |
| [`data/help_search.dart`](../../frontend/lib/features/help/data/help_search.dart) | Shared query normalization and question-word handling. |
| [`models/`](../../frontend/lib/features/help/models) | Immutable article, category, role, glossary, and section models. |
| [`help_routes.dart`](../../frontend/lib/features/help/help_routes.dart) | Stable Help route patterns and encoded route builders. |
| [`presentation/pages/`](../../frontend/lib/features/help/presentation/pages) | Home, topic, article, and glossary screens. |
| [`presentation/widgets/`](../../frontend/lib/features/help/presentation/widgets) | Shared entry tiles, definitions, article rendering, header layout, and navigation controls. |
| [`frontend/lib/config/router/app_router.dart`](../../frontend/lib/config/router/app_router.dart) | Production Help route registration. |
| [`frontend/lib/config/theme/app_theme.dart`](../../frontend/lib/config/theme/app_theme.dart) | Shared application text styles and colors. |
| [`frontend/lib/l10n/app_en.arb`](../../frontend/lib/l10n/app_en.arb) | English UI-label template, placeholders, and plural messages. Other locale ARB files hold translations. |
| [`frontend/l10n.yaml`](../../frontend/l10n.yaml) | Localization generation configuration. |
| [`frontend/test/features/help/`](../../frontend/test/features/help) | Focused catalog, screen, contents-menu, and production-route tests. |
| [`frontend/test/test_support/help_test_catalog.dart`](../../frontend/test/test_support/help_test_catalog.dart) | Shared explicit test fixtures. |

Article and glossary text is compiled from Dart data. Editing this handbook or
another repository Markdown file does not change an in-app article. The
[alias review](glossary-aliases.md) records the original glossary review; edit
the Dart glossary catalog for subsequent content changes. Historical commit
notes describe their own changes rather than current authoring instructions.

## Catalog relationships and permanent IDs

Each article belongs to one category through `categoryId`. Article sections can
reference other articles through `HelpRelatedArticles.articleIds`. The separate
Popular Help configuration references article IDs. An article's
`glossaryTermIds` references shared definitions; terms can optionally reference
guides through `relatedArticleIds`.

The repository generates article definition sections and glossary guide
backlinks. The article renderer generates contents-menu entries from section
headings. These outputs should not be maintained as separate copied lists.

Use lowercase URL slugs such as `reviewing-profile`. Keep an existing ID when
changing a title, meaning, heading, wording, or list position. Do not reuse a
previously published ID for a different concept. Glossary IDs currently live
directly on their entries; article/category IDs also have constants in
`help_content_ids.dart`.

| Destination | Route |
| --- | --- |
| Help home | `/help` |
| Topic | `/help/topics/<category-id>` |
| Article | `/help/articles/<article-id>` |
| Glossary | `/help/glossary` |
| Particular word | `/help/glossary?term=<term-id>` |

Use `HelpRoutes.topic`, `HelpRoutes.article`, and `HelpRoutes.glossaryTerm`
when adding app links. They encode IDs appropriately. Ordinary content additions
use the existing screens and require no new route or renderer branch.

Current home/topic listings, article search, and glossary guide backlinks use
`HelpRole.patient`. Articles may declare `patient`, `caregiver`, `familyMember`,
and `admin` audiences. Roles affect those listings; they do not authorize access
to direct article links. Keep confidential information out of this bundled
catalog. Glossary terms have no role field.

## Articles

### Add an article

1. Verify the workflow in current source and, where possible, a running build.
   Identify the entry point, platform differences, and any incomplete behavior.
2. Add a unique constant to `HelpArticleIds` in `data/help_content_ids.dart`:

   ```dart
   static const reviewingProfile = 'reviewing-profile';
   ```

3. Add a `HelpArticle` to `bundledHelpArticles`. Choose an existing category or
   [add a topic](#topics-and-categories). Supply a useful title/summary, nonempty
   roles and sections, relevant keywords, and optional glossary IDs.
4. Add incoming related links or a featured placement where relevant. Avoid
   adding a link merely because a new article exists.
5. Run the focused checks and inspect the direct route, topic listing, search,
   generated contents, and definitions. Update the content verification record.

Example entry, inserted in `bundledHelpArticles` after declaring its ID:

```dart
HelpArticle(
  id: HelpArticleIds.reviewingProfile,
  categoryId: HelpCategoryIds.gettingStarted,
  title: 'Reviewing your profile',
  summary: 'Find and check the information in your profile.',
  roles: [HelpRole.patient, HelpRole.caregiver],
  keywords: ['personal details', 'account information'],
  glossaryTermIds: ['profile'],
  sections: [
    const HelpParagraph(
      heading: 'About your profile',
      text: 'Your profile contains information about you.',
    ),
    HelpSteps(
      heading: 'Check your information',
      steps: ['Open your profile.', 'Review the information shown.'],
    ),
    HelpTroubleshooting(tips: [
      const HelpTroubleshootingTip(
        problem: 'The information does not look right.',
        solution: 'Check that you are using the correct account.',
      ),
    ]),
    HelpRelatedArticles(articleIds: [HelpArticleIds.openingHelp]),
  ],
)
```

The template uses an existing category, glossary term, and related guide. Its
new ID constant must be declared before using it in the real catalog. The
sample instructions still require workflow review before publication.

### Edit, rename, move, or reorder an article

Edit the entry in `bundled_help_content.dart`. Keep the same ID for revisions
to the same guide. Related-link titles resolve from the current target article,
and keyword/body edits affect local search automatically.

To move a guide, change `categoryId` to a valid category ID. Check the old and
new topic pages, topic visibility on home, and search: category titles contribute
to article search. A category with no Patient articles stops appearing in
Browse Topics, but its existing direct topic route can still show an empty list.

Reordering the article catalog affects topic listing and article search order.
It does not reorder Popular Help. Change `roles` only to describe the article's
audience; check the current Patient-focused surfaces after the change.

Models defensively copy collections. Make authoring edits in the source
initializer rather than trying to mutate a repository/model list at runtime.
Refresh with a hot restart when testing catalog edits because screens retain
bundled repository instances.

## Sections and article contents

| Section | Authoring guidance |
| --- | --- |
| `HelpParagraph` | Supply paragraph text; add a concise heading when readers need a navigation target. |
| `HelpSteps` | Supply each instruction separately. The renderer numbers steps, so do not put numbers in the strings. |
| `HelpTroubleshooting` | Supply problem/solution pairs. A localized Troubleshooting heading is generated unless overridden. |
| `HelpRelatedArticles` | Supply existing article IDs in intentional order. Current titles become link labels. |
| `HelpGlossaryTerms` | Normally generated from `glossaryTermIds`. Prefer article references instead of manually inserting this section. |

All sections accept an optional `heading`. Blank or whitespace-only authored
headings are invalid. Repeated nonempty headings are supported because each
section has its own scroll anchor and programmatic focus target.

An article with at least two named sections gets an expanded On this page menu.
Unnamed paragraphs/step groups stay readable without menu entries. Generated
troubleshooting, related-article, and glossary headings count as named sections.
Changing section order updates menu order; changing a heading updates its label.

Selecting a contents entry scrolls to its section and transfers focus. Keep
`helpSectionHeading` as the shared heading source for menu and body. Remove an
obsolete section from `sections` and check remaining content/menu order; no
separate menu deletion is required. Do not repeat a glossary ID across an
article's references and authored glossary sections.

See [article-contents.md](article-contents.md) for rendering and focus details.

## Topics and categories

To add a topic, declare a constant in `HelpCategoryIds`:

```dart
static const careRoutines = 'care-routines';
```

Add its entry to `bundledHelpCategories`:

```dart
HelpCategory(
  id: HelpCategoryIds.careRoutines,
  title: 'Care routines',
  description: 'Guides for everyday care tasks.',
)
```

Give relevant articles that `categoryId`. Categories display in catalog order;
home includes only categories with Patient articles. An empty category is valid
data but does not produce a Browse Topics entry. A new category needs no router
case.

Edit its title or description in the category entry and retain its ID. Reorder
category entries to change Browse Topics order. When combining topics, move
articles to the surviving category, check incoming references and old bookmarks,
then remove the obsolete entry using the [removal procedure](#removal-and-replacement).

## Featured articles and ordering

Edit `patientPopularHelpArticleIds` in `data/help_home_config.dart`:

- Add an existing Patient article ID to feature it.
- Move an ID to change its position.
- Remove an ID to remove only its Popular Help placement.

Each ID must resolve to an article and appear only once in this configuration.
Patient filtering determines whether it is shown. An article removed from this
list remains available through its topic, search, related links, and direct
route. Update the editorial-order assertion in `help_home_catalog_test.dart`
and any home/flow tests tied to the intended selection.

| Surface | Ordering source |
| --- | --- |
| Popular Help | Explicit featured configuration. |
| Browse Topics | Category catalog order after audience filtering. |
| Articles within a topic | Article catalog order after filtering. |
| Article search | Matching article catalog order. |
| Related-article section | Authored `articleIds` order. |
| Words in an article | Authored glossary reference order. |
| Glossary browsing | Alphabetical display labels. |
| Glossary search | Match priority, then alphabetical labels. |
| Glossary guide backlinks | Matching article catalog order. |

## Glossary

### Add or edit a term

Add a `HelpGlossaryTerm` to `bundledHelpGlossary` in
`data/bundled_glossary_content.dart`. Give it a permanent slug ID, a unique label
after normalization, a nonblank meaning, and relevant aliases:

```dart
HelpGlossaryTerm(
  id: 'guide',
  term: 'Guide',
  definition: 'Instructions that help you do something in the app.',
  aliases: ['help guide', 'how-to guide', 'what is a guide'],
  relatedArticleIds: [HelpArticleIds.openingHelp],
)
```

The current glossary file imports its model; add the `help_content_ids.dart`
import if this is its first use of article ID constants. Explicit guide links
are optional. Use only relevant existing targets.

Edit an existing label, meaning, or aliases in its entry while retaining the
ID. Meanings in articles and word-search tiles update from that same entry.
Adding or removing a term changes alphabetical browsing and catalog-count
expectations; update the intentional assertions in
`help_glossary_catalog_test.dart` and `help_flow_test.dart`.

Write a short first sentence in familiar language. Explain abbreviations and
use a concrete example when useful. Keep distinct concepts separate, such as
dose/dosage and cache/synchronization. A task-shaped search alias helps find a
meaning; it does not promise a supported workflow or successful operation.

### Maintain aliases and search phrases

Aliases can be everyday phrases, questions, plural forms, abbreviations, and
alternative names. Prefer useful reader vocabulary over enumerating every
possible typo. The current model trims aliases, rejects blank normalized values,
and removes duplicates including forms equivalent to the display term.

Case, straight/curly apostrophes, punctuation, repeated spaces, and hyphenation
are normalized. Different entries may share an alias. Do not remove useful
phrases solely because another concept shares them; check their ranked results.
Remove an obsolete alias from its entry and test remaining representative
searches. Search does not currently provide general typo correction.

### Connect a term to an article

Add existing term IDs to the article's `glossaryTermIds`, in reading order:

```dart
glossaryTermIds: ['profile', 'account'],
```

This generates Words in this article, its contents-menu link, the shared
meanings, and glossary guide backlinks. Each meaning includes a link to its
selected glossary entry. Removing an ID removes that article reference; the
term still exists globally. Its backlink disappears unless another reference
or explicit guide link still establishes that connection.

Use a term's `relatedArticleIds` only for additional relevant guides not already
covered by article references. Backlinks combine both sources, deduplicate
articles, and filter by the current Patient audience. There is no separate
backlink list to keep synchronized. See [glossary.md](glossary.md) for details.

## Search

Help home searches articles and terms locally and displays separate Articles
and Words and meanings groups. The live announcement includes both counts.
The shared empty state is shown only when both groups have no matches.

Article search matches all significant query words across titles, summaries,
keywords, category titles, section headings/content, and referenced glossary
labels/aliases. It returns Patient articles in catalog order. Whole glossary
definitions are not added to article search text.

Glossary search includes labels, aliases, and definitions. Its priority is exact
label, exact alias, all-word label/alias match, then all-word definition match;
ties sort alphabetically. A blank glossary query browses every term.

Common English question filler is ignored for word matching. Meaningful
negatives such as `no`, `not`, `without`, and normalized `cant` remain. Exact
label/alias comparisons use the complete normalized query. Normalization is
shared in `help_search.dart`; avoid implementing different rules in screens.

To improve a match, add relevant article keywords or term aliases at the content
entry. Test a concrete everyday phrase and an abbreviated/technical form where
relevant. Check that broader aliases do not make unrelated guides confusing.
Editing a section or definition can also change its respective search matches.

## Removal and replacement

### Inspect incoming references first

Run these from the repository root, substituting the actual constant and ID.
Search both: Dart references often use a constant while routes/tests may use
the literal ID.

```powershell
rg -n -F 'HelpArticleIds.viewingAppointments' frontend/lib frontend/test docs
rg -n -F 'viewing-appointments' frontend/lib frontend/test docs
rg -n -F "'profile'" frontend/lib/features/help frontend/test/features/help docs/help
```

| Entry to remove | Dependencies to inspect |
| --- | --- |
| Article | Popular Help configuration, other articles' related sections, term explicit guide IDs, ID constants, direct links, and tests. Generated backlinks disappear with the article. |
| Glossary term | Every article's `glossaryTermIds`, authored glossary sections, direct term links, useful aliases to retain on a replacement, and tests. |
| Category | Every article's `categoryId`, category constants, direct topic links, and ordering tests. |
| Section | References contained in it, contents order/targets, text searches, and section-specific tests. |
| Keyword or alias | Search coverage and existing useful reader phrases. |

Search results in historical commit notes are context, not necessarily live
references. Preserve historical records rather than rewriting them to describe
a different commit. Update ongoing maintenance and verification documents when
their current instructions become inaccurate.

### Delete an article

1. Remove its Popular Help ID, incoming related links, and explicit glossary
   guide references. Replace a link only with a genuinely relevant existing guide.
2. Remove its entry from `bundledHelpArticles`.
3. Keep its published ID reserved, for example by retaining the ID constant
   with a retirement comment. Do not assign that slug to unrelated new content.
4. Review tests and current documentation; rerun reference searches and checks.
5. Verify remaining topics, search, links, and glossary guide lists. An old
   direct article URL now uses the existing Article not found recovery screen.
6. Record the removal and any recommended replacement in the PR/commit notes.

To reverse the change, restore the record and intended incoming references
from Git history using the [restoration procedure](#restoration).

### Delete a glossary term

1. Remove its references from all articles and any authored glossary sections.
   Remove a now-empty authored glossary section rather than leaving it blank.
2. Update app links or tests that intentionally open that term.
3. Remove the glossary entry. Record the retired ID and replacement, if any,
   in the change notes; do not reuse the old ID for a different meaning.
4. Update intended count assertions and verify generated sections, contents,
   search, and backlinks. An article with no remaining glossary references
   generates no Words in this article section.
5. Verify the old selected-term URL: it shows the unknown-word message while
   retaining the glossary for browsing. Run the focused checks.

Removing a definition entry before removing references causes catalog validation
to fail. Definitions are shared; deleting one affects every referring article.

### Delete a category

Move its articles to a surviving category or remove them with the article
procedure first. Then remove the category entry, reserve its published ID,
and update ordering/tests/current documentation. The old topic URL uses the
existing Topic not found recovery. Verify the new category destinations and
home topic list.

### Split or combine content

Keep the surviving ID when updating the same concept. Give a genuinely new
concept a new ID. Repoint catalog references before removing an obsolete entry.
For glossary combinations, move useful aliases to the surviving term and review
the resulting definition so it still explains one accurate concept.

For article splits, decide which guide retains the original ID and add related
links to the new guides. Document what happens to old bookmarks. The current
router does not automatically redirect removed IDs; deletion uses the recovery
behavior described above. Implement and test any deliberate route migration
separately if the product requires it.

## Restoration

Use Git history to recover the intended record rather than replacing a whole
catalog file and overwriting unrelated newer edits. From the repository root:

```powershell
git log -p -S 'viewing-appointments' -- frontend/lib/features/help/data/help_content_ids.dart frontend/lib/features/help/data/bundled_help_content.dart
git log -p -S "id: 'profile'" -- frontend/lib/features/help/data/bundled_glossary_content.dart
```

Restore the entry under its original ID, ensure its category and referenced
targets exist, and restore only the intended featured/related/term references.
Check that older workflow instructions still describe the current app. Rerun
validation and direct-route/search/contents checks. Restoration does not mean
every historic reference or outdated instruction should also be reinstated.

## Presentation and navigation

For ordinary content edits, keep shared UI behavior in its existing components:

| Concern | Implementation |
| --- | --- |
| Article section layout and contents targets | `presentation/widgets/help_article_content.dart` |
| Authored/default section headings | `presentation/widgets/help_section_heading.dart` |
| Article entries across home/topics/backlinks | `presentation/widgets/help_article_tile.dart` |
| Shared meanings and word result tiles | `presentation/widgets/help_glossary_entry.dart` |
| Topic entries | `presentation/widgets/help_topic_tile.dart` |
| Header layout and wrapped shortcut sizing | `presentation/widgets/help_app_bar.dart` |
| Help Center Home and Back to Settings actions | `presentation/widgets/help_navigation_bar.dart` |
| Article and glossary scroll controls | `presentation/pages/help_article_page.dart`, `help_glossary_page.dart` |

Use the shared app text styles and colors, and localized visible labels. New
controls should preserve keyboard activation, meaningful semantics, target
focus, and wrapping with enlarged text. Contents toggles expose expanded state;
destination headings have header semantics and programmatic focus targets that
do not add ordinary Tab stops. Word search results combine label, meaning, and
button behavior; selected definitions expose selection state.

Ordinary article/word/topic navigation uses `context.push`. The header's home
and settings shortcuts use `context.go` so they leave accumulated Help history
in one action. Preserve ordinary Back behavior and test returning to a home
search query.

Article and glossary Back to top controls appear at an offset of at least 320
logical pixels, in the bottom-left corner. They disappear below that threshold
and return to zero with a 300 ms animation or an immediate jump when animations
are disabled. If changing this behavior, review both screens and their tests.
Keep enough bottom padding for the floating control and consider the fixed
header when positioning contents or glossary targets.

## Localization

UI labels and accessibility announcements come from `AppLocalizations`.
Edit the English template in `frontend/lib/l10n/app_en.arb`, add corresponding
translations to the locale ARB files, and preserve placeholder names/types.
Test zero/one/many counts for article and word plural messages, plus the
combined announcement and parameterized See [term] in glossary label.

From `frontend/`, run:

```powershell
flutter gen-l10n
```

Review `missing_translations.txt`. Do not hand-edit generated
`app_localizations*.dart` files; follow the current repository ignore rules.
Existing missing UI translations fall back to English. Check long labels and
RTL layout when relevant.

Authored article/category text, custom headings, glossary definitions, keywords,
and aliases currently remain English regardless of the selected app locale.
Adding an ARB translation does not translate that catalog content. Preserve
IDs across any future translated catalogs, and use one shared locale resolver
for all Help screens. See [localization.md](localization.md) for the future
catalog translation design.

## Preview and refresh

### Normal Flutter development

Run from `frontend/` using the project's configured environment and supported
device. For example:

```powershell
flutter run -d windows
```

In the attached Flutter terminal, `r` requests hot reload and `R` requests hot
restart. Use **hot restart for catalog/configuration edits** to reinitialize
retained repositories and top-level data. Widget-only changes can often use
hot reload. Regenerate localization after ARB edits; restart or rebuild when
generated content remains stale. Fully stop/relaunch after changes to build
configuration, native dependencies, or Dart defines.

### Retired temporary Windows preview

The temporary dependency-bypass launcher has been removed. Build and run from
`frontend/` with the normal dependency set. SQLCipher, offline persistence,
text-to-speech, location, permissions, and secure storage remain in the
production frontend. Windows builds require their normal native build tools
and libraries; Help introduces no native dependency bypasses.

An old local `tmp/windows-online` copy may still exist for historical captures.
It is not maintained and may contain disabled integrations and stale Help
content. Use the production frontend for current development and verification.

Help reading/search needs no backend request. Account sign-in and the operations
described by articles may require a backend or platform integrations. On web,
the initial app load/reload can still need connectivity even though the loaded
Help catalog is local. Distribute content updates through the normal app
build/release workflow; repository documentation edits do not publish them.

## Validation and review

From `frontend/`, run appropriate checks after a content or presentation change:

```powershell
dart format lib/features/help test/features/help
dart analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
flutter test test/features/help --no-pub
```

Generate localization first if ARB files changed. SDKs must be available on PATH
or invoked through the developer's installed SDK path. `--no-pub` assumes the
project dependencies have already been resolved.

| Test file | Primary coverage |
| --- | --- |
| `help_repository_test.dart` | IDs, categories, related links, required roles/sections, headings, and immutable content. |
| `help_home_catalog_test.dart` | Keywords, audience filtering, featured selection/order, and search. |
| `help_glossary_catalog_test.dart` | Term/alias discovery, ranking, normalization, invalid references, immutable data, generated sections, and guide audiences. |
| `help_center_page_test.dart` | Home/search/topic behavior, keyboard traversal, result announcements, shared typography, layout, and fallback labels. |
| `help_article_page_test.dart` | Article rendering, navigation/recovery, scrolling, and presentation. |
| `help_article_contents_test.dart` | Generated menu order, repeated headings, collapse semantics, destination focus, keyboard activation, and reduced motion. |
| `help_flow_test.dart` | Real production routes and Help screens with refused HTTP, related/direct links, header shortcuts, selected terms, search, Back history, and enlarged layouts. |

Add a focused assertion for a meaningful new phrase, link, or behavior. When
catalog size or featured selection intentionally changes, update the relevant
expectations while retaining integrity/navigation coverage. Do not weaken
validation to make incomplete removals pass. Keep test fixture popular IDs and
glossary references explicit and resolvable.

Before requesting review, check the affected direct routes and incoming links,
topic/featured order, representative search phrases, generated contents and
definitions, glossary backlinks, Back history, header shortcuts, and Back to
top. Check shared light/dark styles, narrow widths, enlarged text, keyboard
focus, semantics, reduced motion, offline reading, and localization fallback
when the change affects presentation.

Record workflow verification in [content-verification.md](content-verification.md):
date, platform/build, entry point, source or observed result, and unresolved
questions. Distinguish source inspection, widget tests, and live workflows.
Automated semantics/layout checks do not replace physical screen-reader review
or representative-reader comprehension checks. Enlarged-text harnesses inject
scaling directly; the existing app-wide scaling clamp is a separate concern.

PR/commit notes should explain the reader-facing change, affected entries/IDs,
removals/replacements, reference cleanup, verification, and relevant limitations.
Keep optional screenshots/logs in ignored local QA locations rather than adding
them to the shipped catalog.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| A new guide is absent from home | Popular Help is explicit. Check its configured ID and Patient audience; also check the topic/search where it should appear. |
| A topic is absent from Browse Topics | It needs at least one Patient article. An empty topic can still resolve directly. |
| A new meaning appears globally but not in an article | Add its ID to that article's `glossaryTermIds` and restart the catalog preview. |
| A glossary guide link is missing or remains after a reference edit | Inspect both article references and the term's explicit guide IDs, then check the Patient audience. |
| A contents entry is absent | Check section headings and the minimum of two named sections. Use the shared heading resolver for generated sections. |
| Duplicate/missing ID validation fails | Inspect constants, literal IDs, categories, related links, featured IDs, and term references. Resolve the dependency rather than suppressing the error. |
| A glossary entry fails validation | Check its slug, unique normalized label, nonblank definition, aliases, and explicit guide targets. |
| A term-reference edit fails validation | Ensure the term exists and is not repeated across generated references and authored glossary sections. |
| Old content remains in a running app | Use hot restart from `frontend/`; stop and relaunch after build configuration or native dependency changes. |
| An alias appears to have disappeared | Normalization removes duplicate/display-equivalent aliases. Test discovery rather than expecting redundant source forms to remain in memory. |
| Search returns several meanings | Shared aliases and definition text can legitimately match. Exact labels/aliases rank first; check relevance before tightening phrases. |
| Content stays English after a locale change | ARB labels and authored catalog text are separate. The runtime catalog is currently English. |
| A deletion produces an old-link error | Deleted IDs use existing recovery screens. Verify reference cleanup and document the old-link behavior. |

## Specialized references

- [Glossary implementation and authoring](glossary.md)
- [Article contents menus](article-contents.md)
- [Localization and future translated catalogs](localization.md)
- [Content verification record](content-verification.md)
- [Production-flow verification and capture guidance](verification-step-9.md)
- [Feature overview](../../frontend/lib/features/help/README.md)
- [Frontend setup](../../frontend/README.md)
