# Commit notes: Reusable Help article model and screen

## Suggested commit title

Add structured Help articles, audience roles, and an ID-based article screen

## Suggested commit body

Extend Help articles with relevant roles and typed content sections while
preserving stable article/category IDs, titles, and short descriptions.
Support paragraphs, numbered steps, troubleshooting problem/solution tips,
and related-article links. Keep content in the bundled catalog and render it
through a shared widget independent of article-specific screen layout.

Add one reusable article screen at `/help/articles/:articleId`. Selecting an
article from Help Center opens the guide by ID. Related links resolve current
titles from the catalog and open the same screen for another ID. Unknown IDs
display a localized explanation and a working return-to-Help-Center action.
Nest article routes under `/help` to support back navigation and direct links.

Migrate Opening Help to structured sections and add Reading Help articles as
a second bundled guide. Validate related links after indexing the catalog so
forward references work. Require audience roles and content sections, and
defensively copy collections to prevent later mutation.

Document the updated schema and extension process. Add focused tests for the
model, link integrity, section rendering, navigation, missing articles, and
long content with large text on a narrow screen.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/models/help_article.dart` | Modified | Replaced the single `body` string with `roles` and `sections`. Retains `id`, `categoryId`, `title`, and `summary` as the short description. The constructor copies roles into an unmodifiable set and sections into an unmodifiable list; construction is no longer const. |
| `frontend/lib/features/help/models/help_role.dart` | Added | Defines Patient, Caregiver, Family Member, and Admin audience metadata through `HelpRole`. This metadata supports future role-aware listings; it does not enforce authorization. |
| `frontend/lib/features/help/models/help_section.dart` | Added | Defines sealed `HelpSection` types: `HelpParagraph`, `HelpSteps`, `HelpTroubleshooting`, and `HelpRelatedArticles`, plus `HelpTroubleshootingTip`. Sections support optional headings. Steps, tips, and related IDs are defensively copied into unmodifiable lists. |
| `frontend/lib/features/help/data/help_content_ids.dart` | Modified | Added permanent article ID `reading-help`; existing `opening-help` and `getting-started` IDs remain unchanged. |
| `frontend/lib/features/help/data/bundled_help_content.dart` | Modified | Migrated Opening Help from a body string to typed sections. Added Reading Help articles, with paragraphs, steps, troubleshooting tips, and reciprocal related links. Both guides declare all four audience roles. Article entries are now an unmodifiable list of locally constructed models. |
| `frontend/lib/features/help/data/help_repository.dart` | Modified | Rejects articles without roles or sections. Validates related IDs against the complete article index after all articles have been registered, allowing forward references while rejecting broken links. Retains existing ID/category validation and lookup behavior. |
| `frontend/lib/features/help/help_routes.dart` | Added | Defines `/help`, the nested `articles/:articleId` route pattern, and an article path helper that encodes IDs. |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Modified | Renders typed sections instead of a body string. Numbers steps, renders problem/solution cards, marks section headings for screen readers, and displays related links using current catalog titles. Delegates related-link selection to its caller. |
| `frontend/lib/features/help/presentation/pages/help_article_page.dart` | Added | Reusable article screen that resolves any article by ID. Displays its category and content, follows related links, and handles unknown IDs with a localized fallback and return button. Uses SafeArea, scrolling, and a 720-wide content constraint. Supports repository injection for tests/previews. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Replaced inline introductory article content with selectable article cards showing titles and short descriptions. Each card pushes an ID-based article path. Retains the existing future-content placeholder. |
| `frontend/lib/config/router/app_router.dart` | Modified | Imports the article screen and shared route paths. Registers `articles/:articleId` as a child of `/help`, passing the path parameter to `HelpArticlePage`. |
| `frontend/lib/l10n/app_en.arb` | Modified | Added `helpTroubleshooting`, `helpRelatedArticles`, `helpArticleNotFoundTitle`, `helpArticleNotFoundDescription`, and `helpBackToCenter`. Changed the placeholder to “More help articles and guides are coming soon.” |
| `frontend/missing_translations.txt` | Modified | Regenerated the missing-translation report for the new article-screen labels. |
| `frontend/lib/features/help/README.md` | Modified | Documents section types, roles, immutable collections, related-link validation, article routing, and an example of adding structured content. Updates the current feature scope and test command. |
| `frontend/test/features/help/help_repository_test.dart` | Modified | Migrated existing tests to structured articles and expanded the suite from six to nine tests. Adds forward-link/broken-link checks, required roles/sections, and defensive-copy checks for nested collections. |
| `frontend/test/features/help/help_article_page_test.dart` | Added | Four widget tests covering all section types, home-to-article and related-link navigation with back behavior, an unknown-ID fallback, and long content at double text scale on a 320-by-568 viewport. |
| `frontend/test/test_support/help_test_catalog.dart` | Added | Shared local catalog fixture with two guides, all supported section types, audience metadata, and configurable paragraph text for layout tests. |
| `docs/commit-notes/help-center-step-3.md` | Added | This commit description, change inventory, and validation record. |

Flutter also regenerated the ignored `frontend/lib/l10n/app_localizations*.dart`
files for the new labels. These are generated outputs, not new source files to
stage under the current ignore rules.

## Content model and compatibility notes

- New articles require `roles` and `sections`; existing `body:` constructor
  arguments must be migrated to typed sections.
- `summary` remains the short-description field; `categoryId` references the
  existing category model.
- Related sections store article IDs rather than display titles or URLs.
  Renaming a title therefore does not break the link.
- Generic Troubleshooting and Related articles headings use app localization
  unless a section supplies a custom heading.
- Starter article text and custom headings remain English. New generic labels
  fall back to English where translations are missing.
- Article content stays bundled with the app. No HTTP request, backend
  credentials, database, package addition, or native dependency is needed to
  read it. Some activities described by future guides may require connectivity.

## Validation completed

From `frontend/`:

```powershell
flutter test test/features/help --no-pub
dart analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
flutter test test/config/router/app_router_test.dart --no-pub --plain-name 'appRouter configuration'
```

- All 13 Help tests passed: nine catalog tests and four article-screen tests.
- All seven existing app-router configuration checks passed.
- Static analysis reported no issues in the Help feature, its tests, or the
  shared Help fixture.
- `git diff --check` passed.
- The running Windows preview loaded the updated content model and new route
  through a successful hot restart. The app remained running after detaching
  the debugger.

The router command above ran the configuration group, not the entire router
test suite. The widget tests independently exercised article paths, related
navigation, direct article entry, and missing-ID handling with a local catalog.

## Temporary Windows preview and restoration

Step 3 added no dependency bypasses and did not change `frontend/pubspec.yaml`,
the backend, `.gitignore`, or the temporary preview scripts.

To update the running preview, these source files were copied into the ignored
`tmp/windows-online/` working directory:

- `frontend/lib/features/help/` to `tmp/windows-online/lib/features/help/`.
- `frontend/lib/config/router/app_router.dart` to the matching preview path.
- `frontend/lib/l10n/app_en.arb` and generated `app_localizations*.dart` files
  to the matching preview localization paths.

These copies are local runtime artifacts and must not be staged. Keep the
Step 3 source changes when retiring the preview. The earlier dependency-bypass
inventory and restoration checklist remain in
[help-center-step-1.md](help-center-step-1.md).

No commit, push, dependency restoration, or preview cleanup was performed
while writing these notes.
