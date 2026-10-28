# Commit notes: Patient-focused Help Center home

## Suggested commit title

Build Patient-focused Help home with bundled guides, search, and topics

## Suggested commit body

Replace the introductory Help listing and future-content placeholder with a
Patient-focused home showing Help Center, a search field, Popular Help, and
Browse Topics. Add six bundled guides in an explicit editorial order maintained
separately from article content and display titles. No usage-based ranking or
analytics collection is introduced.

Add local search across Patient article titles, summaries, topic titles, and
section text. Match all query words regardless of case or extra whitespace.
Show results in catalog order, support clearing the query, and retain the query
when returning from an article. Browse Topics opens separate category screens
that list Patient guides and link to the existing reusable article screen.

Keep stable article and category IDs, preserve the earlier Opening Help and
Reading Help articles, and validate missing or duplicate popular selections.
Reuse one article tile across popular entries, search results, and topics.
Add localized screen labels, developer documentation, and focused catalog and
widget tests. Reading Help requires no backend, database, new package, or
additional native dependency.

## Popular Help order and content

The order below is defined in `patientPopularHelpArticleIds` in
`frontend/lib/features/help/data/help_home_config.dart`. It does not depend on
catalog declaration order, title sorting, or measured usage.

| Position | Article title | Permanent article ID |
| --- | --- | --- |
| 1 | Getting started with CareConnect | `getting-started-with-careconnect` |
| 2 | Viewing medications and recording a dose | `viewing-medications-and-recording-a-dose` |
| 3 | Completing a daily check-in | `completing-a-daily-check-in` |
| 4 | Viewing appointments | `viewing-appointments` |
| 5 | Messaging your caregiver | `messaging-your-caregiver` |
| 6 | Resetting your password | `resetting-your-password` |

Browse Topics contains Getting Started, Medications, Daily Check-Ins,
Appointments, Messaging, and Account and Settings. The existing
`getting-started` category now has a broader description. Five new category
IDs are `medications`, `check-ins`, `appointments`, `messaging`, and `account`.

The first five new guides declare the Patient audience. Resetting your password
declares all existing roles. The earlier `opening-help` and `reading-help`
articles remain available through Getting Started and search; their IDs were
not changed or removed.

Guides were checked against the current app workflows. The medication guide
uses Home > Medication Reminders > Mark Taken for recording a dose. The
appointment guide uses Home > Upcoming EVV Appointments and its refresh action.
The check-in guide explicitly describes the current native app's mock
submission confirmation, which does not save or send mood/notes, and directs
users to Messages to share an update. This work did not implement or repair
check-in submission; update the guide when that workflow changes.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/data/help_content_ids.dart` | Modified | Added six permanent article IDs and five category IDs. Preserves all IDs from earlier steps. |
| `frontend/lib/features/help/data/help_home_config.dart` | Added | Defines the explicit six-article Patient Popular Help order as stable IDs, independently of content declaration order and titles. Documents that the selection is editorial rather than usage-based. |
| `frontend/lib/features/help/data/bundled_help_content.dart` | Modified | Added the six Patient-focused starter guides, with steps, troubleshooting tips, and related links. Added five topics and expanded the Getting Started description. Retains the two existing Help guides. All content remains bundled Dart data. |
| `frontend/lib/features/help/data/help_repository.dart` | Modified | Accepts and defensively copies `popularArticleIds`; rejects missing or duplicate selections. Bundled construction uses the Patient ordering configuration. Adds role-filtered popular articles and categories, optional role filtering for category articles, and local search across titles, summaries, topic titles, section headings, paragraphs, steps, and troubleshooting text. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Converts the home to a stateful screen with a disposable search controller. Displays the localized Help Center title, search field, Popular Help, and Browse Topics. Shows Patient search results or an empty-result message while searching; clear restores the home lists. Article entries push article paths; topic entries push category paths. Uses SafeArea, scrolling, a 720-wide content constraint, and semantic section headings. |
| `frontend/lib/features/help/presentation/pages/help_topic_page.dart` | Added | Separate topic screen resolved by category ID. Displays its description and Patient articles using the shared tile. Handles empty categories and unknown IDs, including a return-to-Help-Center action. Accepts an injected repository for tests/previews. |
| `frontend/lib/features/help/presentation/widgets/help_article_tile.dart` | Added | Shared card/list tile showing an article title, summary, and navigation chevron. Used by popular articles, search results, and topic screens; navigation is delegated through a callback. |
| `frontend/lib/features/help/help_routes.dart` | Modified | Adds the nested `topics/:categoryId` pattern and `topic(id)` path helper, producing `/help/topics/<encoded ID>`. Preserves existing home and article paths. |
| `frontend/lib/config/router/app_router.dart` | Modified | Imports `HelpTopicPage` and registers `topics/:categoryId` beneath `/help`, passing the category path parameter to the screen. Existing article routing remains in place. |
| `frontend/lib/l10n/app_en.arb` | Modified | Removes the obsolete `helpCenterPlaceholder`. Adds nine labels: `helpSearchArticles`, `helpClearSearch`, `helpPopularHelp`, `helpBrowseTopics`, `helpSearchResults`, `helpNoSearchResults`, `helpNoArticles`, `helpTopicNotFound`, and `helpTopicNotFoundDescription`. |
| `frontend/missing_translations.txt` | Modified | Regenerated the missing-translation report for the new labels and removal of the placeholder. |
| `frontend/lib/features/help/README.md` | Modified | Documents the Patient home, fixed popular ordering, local search behavior, topic routes, role filtering, reusable tiles, custom catalog configuration, extension process, and current native check-in limitation. |
| `frontend/test/features/help/help_home_catalog_test.dart` | Added | Four tests covering the exact six-guide title order and Patient audience, ordering independent of titles/catalog order and immutable selections, rejection of missing/duplicate selections, and local search with role/category filtering. |
| `frontend/test/features/help/help_center_page_test.dart` | Added | Five widget tests covering home labels/order, search-result navigation and query retention, no results and clearing search, topic-to-article/back navigation, unknown-topic recovery, and narrow-screen layouts with doubled text size. |
| `frontend/test/test_support/help_test_catalog.dart` | Modified | Explicitly selects the two existing fixture guides as popular entries so earlier home/article navigation tests continue to use the fixture catalog. |
| `docs/commit-notes/help-center-step-4.md` | Added | This commit description, content ordering, exact file inventory, validation record, and preview/restoration notes. |

Flutter also regenerated the ignored `frontend/lib/l10n/app_localizations*.dart`
files. These are generated outputs, not additional source files to stage under
the current ignore rules.

## Behavior and extension notes

- The home, search, and topic lists show articles relevant to `HelpRole.patient`,
  even when Help is opened by another account role. Audience metadata filters
  listings; it is not authorization. Direct article links remain readable.
- Search is entirely local. All query words must match somewhere in the
  searchable text; results retain catalog order. An empty or whitespace-only
  home query displays Popular Help and Browse Topics.
- Custom repositories default to an empty popular selection. Supply
  `popularArticleIds` explicitly when configuring a custom home catalog.
- To feature a new Patient guide, add its stable ID to the ordering configuration
  at the intended position and include `HelpRole.patient` in its article roles.
  Future usage-based selection can replace this configuration without changing
  article IDs, content models, or navigation paths.
- Article content remains English. Screen labels use the existing localization
  system and fall back to English where translations are missing.
- Help reading/searching requires no connection. Activities described by the
  guides, such as sending messages or requesting reset emails, may require one.

## Validation completed

The Step 4 implementation was verified before these notes were written.
Commands were run from `frontend/` using the installed SDK paths because
Flutter is not on this machine's PATH:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat gen-l10n
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe format lib/features/help test/features/help test/test_support/help_test_catalog.dart
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
& C:/Users/SQ/flutter/bin/flutter.bat test test/config/router/app_router_test.dart --plain-name 'appRouter configuration' --no-pub
```

- All 22 Help tests passed: nine existing repository tests, four existing article
  screen tests, four new home catalog tests, and five new home screen tests.
- All seven existing app-router configuration checks passed. This ran the
  configuration group, not the entire router test suite.
- Static analysis reported no issues in the Help feature, its tests, or the
  shared Help fixture.
- `git diff --check` passed from the repository root.
- The existing Windows preview accepted a successful hot restart with the new
  screens, content, localization outputs, and topic route. The app remained
  running after detaching the debugger.

Widget navigation/layout checks used a local catalog without backend services.
The narrow-layout test used a 320-by-568 viewport with doubled text size.

## Temporary Windows preview and restoration

Step 4 added no dependency bypasses and made no changes to
`frontend/pubspec.yaml`, the backend, `.gitignore`, or the preview scripts.
No additional OpenSSL, NuGet, ATL, or plugin workaround was introduced.

To refresh the running preview, these files were copied into the ignored
`tmp/windows-online/` working directory:

- `frontend/lib/features/help/` to `tmp/windows-online/lib/features/help/`.
- `frontend/lib/config/router/app_router.dart` to the matching preview path.
- `frontend/lib/l10n/app_en.arb` and generated `app_localizations*.dart` files
  to the matching preview localization paths.

These copies are local runtime artifacts and must not be staged. Keep the
Step 4 source changes when retiring the temporary preview; there is no Step 4
dependency restoration to perform. The earlier dependency-bypass inventory and
restoration checklist remain in
[help-center-step-1.md](help-center-step-1.md).

No commit, push, dependency restoration, or preview cleanup was performed
while writing these notes.
