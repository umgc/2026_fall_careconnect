# Commit notes: Help Center steps 6-8

## Suggested commit title

Document Help platform differences and improve search, accessibility, and extension guidance

## Suggested commit body

Document Windows preview, mobile, and web differences in the existing Help
articles. Explain that offline Help reading is separate from offline saving and
replay, which the Windows preview disables alongside text-to-speech, GPS, and
native permission integrations. Preserve the native Daily Check-In mock
submission warning and distinguish it from the web questionnaire route.
Record sources, platforms inspected, and unverified instructions for all eight
bundled articles without claiming a complete live workflow audit.

Add optional immutable search keywords and synonyms to the bundled guides.
Provide a Browse Topics action for empty search results that clears the query,
scrolls to topics, and moves keyboard focus to the first topic. Announce result
counts through a localized live region and expose article, topic, and related
links as accessible buttons with combined text labels.

Expand developer instructions for adding articles, categories, featured
entries, keywords, and related links through content/configuration. Document
current English fallback and a concrete future design for translated article
catalog selection. Add focused keyword, keyboard, semantics, theme, large-text,
and localization-fallback tests. Keep content bundled and dependencies unchanged.

## Agreed scope

- **Step 6 was narrowed by the user:** explain platform differences and record
  each article's source material, platforms checked, and remaining unverified
  instructions. This work did not perform a new live audit of every instruction.
- **Step 7:** finish keyword search, empty-results topic browsing, accessibility
  checks, and explicit localization fallback.
- **Step 8:** finish expansion and translation documentation. Content-driven
  articles, categories, featured ordering, role metadata, and reusable routes
  already existed.
- **Step 9 remains separate:** complete Settings-to-Help flow verification,
  physically disconnected access, and actual device/assistive-technology checks.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/models/help_article.dart` | Modified | Adds optional `keywords`, defaulting to an empty iterable. Copies keywords into an unmodifiable list so existing constructors remain compatible and callers cannot mutate published synonyms. |
| `frontend/lib/features/help/data/help_repository.dart` | Modified | Includes keyword strings in the existing local search text. Retains all-word matching, case/whitespace normalization, Patient audience filtering, and catalog-order results. |
| `frontend/lib/features/help/data/bundled_help_content.dart` | Modified | Adds search synonyms to all eight articles. Adds a Reading Help related link to Getting started with CareConnect. Adds Windows preview connectivity guidance to the dose guide; qualifies the check-in mock explanation as native and documents the different web questionnaire entry; expands Reading Help articles with Windows preview, mobile, and web paragraphs. Preserves all article/category IDs and the six featured articles' order. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Adds reading-order focus traversal, a disposable first-topic focus node, and an empty-results Browse Topics button. Its action clears search, restores the home lists, focuses the first topic, and brings the topic heading into view. Adds a localized semantic live region for search-result counts. Uses the new shared topic tile. |
| `frontend/lib/features/help/presentation/widgets/help_topic_tile.dart` | Added | Reusable category card/list tile accepting a category, navigation callback, and optional focus node. Merges title/description semantics and exposes a button role. |
| `frontend/lib/features/help/presentation/widgets/help_article_tile.dart` | Modified | Merges article title/summary semantics and explicitly exposes the navigation entry as a button. Retains standard Material keyboard activation and theme styling. |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Modified | Merges related-link semantics and exposes each related article entry as a button. Continues resolving link titles through article IDs. |
| `frontend/lib/l10n/app_en.arb` | Modified | Adds the ICU plural message `helpSearchResultsCount` and placeholder metadata for integer `count`. Supplies zero, one, and multiple-result announcements. Reuses the existing localized Browse Topics label for the new action. |
| `frontend/missing_translations.txt` | Modified | Regenerated the report to include the new search-count label in the 13 non-English locales where its translation is missing. |
| `frontend/lib/features/help/README.md` | Modified | Documents keyword search, empty-result browsing/focus behavior, semantic announcements, offline web-loading boundaries, and platform guidance. Expands examples for articles, categories, related links, featured configuration, validation rules, and tests. Links to the verification record and localization guide. |
| `docs/help/content-verification.md` | Added | Records sources and implementation references for each of the eight articles, distinguishes code inspection from device/live-backend verification, documents the preview/mobile/web differences, and lists unresolved instructions and future verification requirements. |
| `docs/help/localization.md` | Added | Documents current ARB labels and English content/fallback, translating labels and plural messages, and a future locale resolver/registry design for translated article/category catalogs. Covers locale selection, fallback, stable IDs, validation, and proposed tests. |
| `frontend/test/features/help/help_home_catalog_test.dart` | Modified | Adds two tests for keyword-only search, multiword/case/whitespace behavior, audience filtering, defensive copying/immutability, and the bundled medicine/chat/forgot-password synonyms. Catalog suite now has six tests. |
| `frontend/test/features/help/help_center_page_test.dart` | Modified | Adds six widget cases: keyboard empty-result browsing with focused/visible topics; Tab/Shift-Tab and Enter activation; semantic button labels and live result counts; dark and light themes with doubled text at narrow width; and Spanish-locale English fallback. Extends the pump helper with theme brightness and locale options. Disposes the semantics handle in `finally`. Home screen suite now has eleven tests. |
| `docs/commit-notes/help-center-step-6-8.md` | Added | This combined commit description, exact file inventory, validation record, remaining work, and preview/restoration notes. |

Flutter regenerated the ignored `frontend/lib/l10n/app_localizations*.dart`
files for the new message. These generated outputs are not additional source
files to stage under the current ignore rules. The new documentation is under
`docs/help/`; `frontend/.gitignore` ignores new Markdown files under frontend.

## Platform and content boundaries

The Windows preview restrictions apply to that temporary development build,
not every desktop/mobile/web build. Missing native permission integration does
not mean every operating-system permission or other plugin is disabled.
Help reading, topic browsing, and searching use bundled content independently
of those integrations. Web first-load/reload behavior remains unverified and
can require a connection even though the loaded catalog needs no backend fetch.

The native mood-and-notes check-in still displays a mock confirmation and does
not send those responses. The web `/virtual-checkin` conditional entry can open
the server-backed questionnaire form; Patient bottom navigation currently
imports the native-style screen directly, so entry points matter. These
distinctions were checked in source, not through live browser/mobile submission.
This change did not implement or repair check-in submission.

The verification record uses SUPPORT.md and the older User Guide as context
alongside current source. It explicitly lists remaining live instructions;
automated Help rendering does not establish that dose persistence, message
delivery, password-reset email delivery, or appointment loading succeeds.

## Localization and expansion boundaries

Article/category content remains English. Existing UI localization and generated
English fallback remain active; no new translated catalogs were shipped.
`HelpRepository.bundled()` still selects English for every app locale.

The proposed `HelpRepository.forLocale(...)` resolver in the localization guide
is future extension design, not an implemented API. The guide explains the
one-time locale wiring and subsequent configuration-based translation workflow,
including exact/language/English fallback and preserving IDs and related links.

New English articles and categories can already be added through content entries
and permanent IDs without adding router cases or article-screen branches.
Featured order remains in the existing `patientPopularHelpArticleIds` configuration.

## Validation completed

The implementation was verified before these notes were written. From
`frontend/`, using the installed SDK paths:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat gen-l10n
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe format lib/features/help test/features/help
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

- All **30 Help tests passed**: nine existing repository tests, four existing
  article-screen tests, six home catalog tests, and eleven home screen tests.
- Static analysis reported no issues in Help, its tests, or the shared fixture.
- Keyboard cases cover Tab, Shift-Tab, Enter, and Space, plus focus transfer from
  empty results to a topic. Semantics cases verify article/topic button roles,
  combined labels, and zero/one-result live announcements.
- Both light and dark themes were tested at a 320-by-568 viewport with doubled
  text size. The Spanish-locale test verifies current English Help fallback.
- `git diff --check` passed from the repository root.
- The running Windows preview accepted a successful hot restart and remained
  running after the debugger detached.

No new full-router suite, live browser/mobile workflow audit, physical network
disconnection test, or real screen-reader session was performed in these steps.
Those checks remain in Step 9 and the content verification record.

## Temporary Windows preview and restoration

Steps 6-8 introduced no package/native dependency, OpenSSL requirement, or new
dependency bypass. They did not change `frontend/pubspec.yaml`, the backend,
Settings placement, the router, `.gitignore`, or the preview scripts.

The updated `frontend/lib/features/help/` directory, English ARB, and generated
localization Dart files were copied into their matching paths beneath the
ignored `tmp/windows-online/` directory to refresh the running preview. These
copies are local runtime artifacts and must not be staged.

Keep the Steps 6-8 source/documentation changes when retiring the preview.
No dependency restoration is required specifically for these steps. The
earlier temporary bypass inventory and restoration checklist remain in
[help-center-step-1.md](help-center-step-1.md).

No commit, push, dependency restoration, or preview cleanup was performed while
writing these notes.
