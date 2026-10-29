# Commit notes: Help glossary, article meanings, and combined search

## Suggested commit title

Add a plain-language Help glossary with article definitions and combined search

## Suggested commit body

Add the 75 approved glossary terms with short definitions and 551 authored
search aliases covering everyday phrases, questions, abbreviations, and
alternative names. Bundle the catalog in the app so readers can browse and
search meanings offline. Add a Glossary entry to Help Center Home, alphabetical
browsing, local search, empty-state recovery, and selected-word direct links.

Connect the existing eight Help articles to the shared catalog through permanent
term IDs. Generate Words in this article sections and their contents-menu links
from those references, and generate glossary guide backlinks automatically.
Extend Help home search to show Articles and Words and meanings separately,
with a combined live result announcement. Normalize punctuation and common
question filler while retaining meaningful negatives. Prioritize exact glossary
labels over aliases and definition matches.

Reuse app typography, Help header shortcuts, and existing Back navigation.
Add glossary Back to top behavior, selected-entry semantics, programmatic
destination focus, and reduced-motion scrolling. Validate catalog integrity
and immutable content. Expand disconnected production-route and catalog tests;
all 59 Help tests pass and focused Dart analysis reports no issues. Document
authoring rules, localization fallback, and remaining real-device accessibility
verification.

## Scope and purpose

This implements the remaining approved Help expansion work:

- **#2: Glossary.** A complete starting vocabulary with simple meanings,
  everyday search aliases, alphabetical browsing, and offline access.
- **#3: Article and search integration.** Shared meanings inside articles,
  generated contents links and related-guide links, combined Help search,
  and direct navigation to a particular definition.
- **#4: Validation, accessibility checks, and maintenance documentation.**
  Catalog validation, alias coverage, audience filtering, navigation and
  keyboard tests, theme/enlarged-text checks, and instructions for future edits.

The earlier article contents menu remains the source of section navigation.
This change extends that menu to include generated glossary sections. Existing
Help header shortcuts and ordinary Back behavior are reused on the new screen.

The reader can now search `What is EVV?`, see both the appointment guide and
the EVV meaning, and open the definition directly. Searching `points and rewards`
finds Gamification even when no article matches. Readers do not need to know a
feature's exact label or open a separate page for each meaning.

## Glossary content and reader accessibility

The bundled catalog contains these 75 approved terms. The groupings below
describe content coverage; the glossary screen displays an alphabetical list.

| Content area | Count | Terms |
| --- | ---: | --- |
| People and accounts | 8 | Patient, Caregiver, Administrator, User role, Account, Profile, Sign in, Sign out |
| Access and privacy | 7 | Password, Password reset link, Account access, Permissions, Privacy, Session, Linked account |
| Check-ins and health information | 8 | Daily Check-In, Virtual Check-In, Questionnaire, Assigned questionnaire, Mood, Symptom, Allergy, Care notes |
| Medication | 7 | Medication, Medication Tracker, Dose, Dosage, Schedule, Medication reminder, Mark Taken |
| Appointments and care visits | 7 | Appointment, Scheduled visit, EVV, Calendar Assistant, Patient List, Patient Report, Shift |
| Messages and calls | 7 | Conversation, Contacts, Message, Attachment, Audio call, Video call, Retry |
| Connections and saved information | 7 | Online, Offline, Offline Persistence, Synchronization, Pending update, Refresh, Cache |
| Devices and device access | 8 | Wearable, Smart device, Pairing, Location access, GPS, Camera access, Microphone access, Text-to-speech |
| App tools and progress | 8 | AI Assistant, Notetaker Assistant, Daily Brief, File Management, Invoice Assistant, Social Feed, Gamification, Achievement |
| Appearance and navigation | 8 | Light mode, Dark mode, Text size, Screen reader, Keyboard navigation, Browse Topics, Related articles, Back to top |

Definitions use short sentences, familiar words, and concrete examples where
helpful. For example, Questionnaire starts with "A list of questions for you to
answer," and Offline starts with "Your device is not connected to the internet."
Abbreviations such as EVV and GPS are expanded within their meanings.

Aliases include questions and everyday descriptions such as `what is EVV`,
`read words aloud`, `no internet`, and `points and rewards`. The Dart source
contains **551 authored aliases** across the 75 entries. Runtime normalization
removes aliases that duplicate another alias or the display term; 551 describes
the authored map before that removal.

Closely related concepts retain separate definitions. Dose and dosage, daily
and virtual check-ins, offline persistence and cache, synchronization and
refresh, and text-to-speech and screen readers are distinct entries. General
device examples explain categories without promising support for every device
or file type. Medical examples explain vocabulary rather than treatment.

The [approved alias map](../help/glossary-aliases.md) records the original content
review. The implemented Dart catalog is the source to edit for future changes.

## Screen behavior and navigation

- Help Center Home shows a labeled Glossary card when the search is empty.
  Opening it navigates to `/help/glossary`.
- The glossary displays every meaning directly, ordered alphabetically when
  browsing. Definitions do not require hovering or opening individual pages.
- Find a word filters locally. A clear-search control restores browsing.
  The visible result count is a live semantics region.
- An empty search result offers a simpler-search suggestion and Show all words.
  An unknown direct-link ID shows a recovery message while preserving the
  complete glossary for browsing and searching.
- A specific-word link uses `/help/glossary?term=<permanent-id>`. For example,
  `/help/glossary?term=evv` opens the full list at EVV. The entry receives a
  visible outline, selected semantics, and programmatic focus.
- Entry keys and focus nodes persist across rebuilds. Direct-link selection
  runs after layout so the target is available. A changed requested term or
  injected repository clears the search before resolving the new selection.
- Definition entries are built eagerly so any of the 75 variable-height cards
  can be reached by a direct link. There are no fixed-height assumptions.
- Existing Help Center Home and Back to Settings shortcuts stay in the header.
  They retain their existing behavior of leaving accumulated Help history in
  one action. Ordinary Back still returns to the previous screen.
- Opening a word from Help search and returning with Back preserves the home
  query. Article-to-glossary and glossary-to-guide navigation use normal pushes.
- Glossary Back to top appears in the bottom-left corner at a scroll offset of
  **320 logical pixels or more**, and disappears below that threshold. It
  returns to offset zero with a 300 ms ease-out animation, or an immediate jump
  when animations are disabled.

The glossary uses the shared Help AppBar, a maximum content width of 720 logical
pixels, the app's text styles and colors, and bottom padding for the floating
control. No new font assets, packages, network service, or backend endpoint are
introduced.

## Article integration and low-maintenance authoring

`HelpArticle` now has an optional, immutable `glossaryTermIds` collection.
The eight existing guides declare relevant IDs covering account access,
medication, check-ins, appointments, messaging, and reading Help.

`HelpRepository.sectionsForArticle` appends a `HelpGlossaryTerms` section when
an article references terms. Articles with no glossary references keep their
original sections. Each generated entry reads its current label and meaning
from the repository through the shared `HelpGlossaryEntry` widget.

`helpSectionHeading` supplies the localized Words in this article heading for
both rendering and the contents menu. `HelpArticleContent` builds its anchors
and focus targets from the resolved section list, so generated definitions
participate in the existing menu without a second list of navigation metadata.
The article page also retains a bundled repository instance across rebuilds.

Each article definition can open its selected glossary entry through a visible
See [term] in glossary button. On the glossary screen,
`articlesForGlossaryTerm` collects guide backlinks from article references plus
optional explicit `relatedArticleIds` on the term. An article appears only once,
and results are filtered by audience. The current Help screens use the existing
Patient-focused audience. Terms without a relevant guide display their meaning
without inventing an unrelated link.

To extend an article, add permanent IDs in the desired reading order:

```dart
glossaryTermIds: ['appointment', 'scheduled-visit', 'evv'],
```

Edit the definition once in `bundled_glossary_content.dart`. The glossary,
article meanings, search results, and generated guide connections then use the
same content. Keep IDs when renaming terms or translating display text.

## Search behavior

The home search label changes from Search Help articles to **Search Help**.
Matching articles and words appear under separate headings. Word results show
both their label and meaning before the reader opens them. A live announcement
includes article and word counts, for example:

```text
No Help articles found. 1 glossary word found.
```

The empty state appears only when both groups have no results and now says
"No matching articles or words. Try another search." Clearing the search restores
the glossary entry, Popular Help, and topic browsing.

`help_search.dart` centralizes normalization for both search paths:

- Lowercase text, trim boundaries, and collapse whitespace and punctuation.
- Normalize straight and curly apostrophes so `can't` and `can’t` match.
- Treat hyphenated and spaced forms consistently.
- Ignore common English question filler for word matching.
- Retain negatives such as `no`, `not`, `without`, and normalized `cant`.

Glossary results rank exact display labels first, exact aliases second,
all-word matches in labels/aliases third, and definition matches fourth.
Results within each rank sort alphabetically. A blank glossary query returns
the full alphabetical catalog. Cross-term alias overlap is allowed.

Article search also includes the labels and aliases of referenced glossary
terms. It keeps audience filtering and catalog ordering, and does not add whole
glossary definitions to the article search text. Typo tolerance and every
possible misspelling are not implemented by this change.

## Validation and localization

`HelpGlossaryTerm` stores a permanent ID, label, definition, aliases, and optional
related-article IDs. It takes defensive immutable copies, trims aliases, rejects
blank normalized aliases, and removes duplicates within an entry.

`HelpRepository` validates the combined catalog during construction. New checks
reject malformed or duplicate term IDs, duplicate normalized display labels,
blank labels or definitions, missing term references, empty authored glossary
sections, repeated term references within an article, and missing explicit guide
targets. Existing article/category/featured/related-link validation remains.

New labels and pluralized counts use the existing ARB localization system.
Twelve new UI messages are added, and two existing search messages are updated.
The missing-translation report adds the twelve messages in each of the 13 other
locales. The existing English fallback applies while translations are pending.
Authored glossary definitions and aliases remain English, like bundled articles.

Flutter regenerated ignored `app_localizations*.dart` outputs. They are not
additional source files to stage under the repository's current ignore rules.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/data/bundled_glossary_content.dart` | Added | Bundles all 75 meanings, permanent IDs, and 551 authored aliases for offline use. |
| `frontend/lib/features/help/data/help_search.dart` | Added | Shares punctuation, case, apostrophe, and question-word normalization. |
| `frontend/lib/features/help/models/help_glossary_term.dart` | Added | Defines immutable glossary entries and normalized alias deduplication. |
| `frontend/lib/features/help/presentation/pages/help_glossary_page.dart` | Added | Provides alphabetical browsing, search, result status, recovery, selected-term scrolling/focus, guide links, and Back to top. |
| `frontend/lib/features/help/presentation/widgets/help_glossary_entry.dart` | Added | Shares definition presentation and accessible word-search result tiles. |
| `frontend/lib/features/help/data/help_repository.dart` | Modified | Indexes and validates terms, ranks glossary search, generates article sections and audience-filtered backlinks, and enriches article search. |
| `frontend/lib/features/help/data/bundled_help_content.dart` | Modified | Adds glossary references to the existing eight guides. |
| `frontend/lib/features/help/models/help_article.dart` | Modified | Adds optional immutable `glossaryTermIds`. |
| `frontend/lib/features/help/models/help_section.dart` | Modified | Adds the `HelpGlossaryTerms` section type. |
| `frontend/lib/features/help/help_routes.dart` | Modified | Adds glossary route constants and encoded selected-term links. |
| `frontend/lib/config/router/app_router.dart` | Modified | Registers the production glossary route and resolves its `term` query parameter. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Adds glossary entry, combined search groups, combined live counts, word navigation, and revised empty-state behavior. |
| `frontend/lib/features/help/presentation/pages/help_article_page.dart` | Modified | Opens selected-word routes and retains its bundled repository across rebuilds. |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Modified | Renders shared meanings and builds contents targets from resolved sections. |
| `frontend/lib/features/help/presentation/widgets/help_section_heading.dart` | Modified | Supplies the localized generated glossary heading. |
| `frontend/lib/l10n/app_en.arb` | Modified | Adds glossary/search labels and counts, and updates the home search label and empty state. |
| `frontend/missing_translations.txt` | Modified | Records the new messages awaiting translation in the 13 other locales. |
| `frontend/test/features/help/help_glossary_catalog_test.dart` | Added | Adds five catalog/search/integrity/immutability/audience tests, including every retained alias. |
| `frontend/test/features/help/help_center_page_test.dart` | Modified | Updates combined announcements and labels, and uses a specific article query for the keyboard navigation case. |
| `frontend/test/features/help/help_flow_test.dart` | Modified | Adds five production-flow cases and extends header coverage; supports dark theme and disabled animations in the harness. |
| `frontend/lib/features/help/README.md` | Modified | Links glossary maintenance guidance and documents additional immutable collections. |
| `docs/help/article-contents.md` | Modified | Includes generated glossary sections in the shared default-heading guidance. |
| `docs/help/glossary-aliases.md` | Added | Records the approved vocabulary/alias review, plain-language guidance, and concept distinctions. |
| `docs/help/glossary.md` | Added | Documents behavior, content ownership, reference authoring, validation, localization, and verification boundaries. |
| `docs/commit-notes/help-center-glossary.md` | Added | These detailed commit notes and validation record. |

## Validation completed

Verified **October 4, 2026** during implementation. Writing these notes did not
rerun the application tests.

- All **59 Help tests passed**, including five new glossary catalog cases and
  five new production-route flow cases. The previous 49 Help tests also pass.
- Every bundled term is discoverable by its exact label, and every retained
  alias finds its owning term. Ranking, punctuation, question filler, negation,
  alphabetical browsing, and empty matches are checked.
- Catalog checks cover malformed/duplicate IDs, duplicate labels, blank content,
  missing links, repeated references, immutable collections, generated sections,
  and audience-filtered guide links.
- Production-flow tests use the real route definitions and Help screens while
  connectivity reports disconnected and HTTP requests are refused. Help
  browsing/search/navigation adds no network requests; Settings requests in
  the broader flow are refused and counted separately.
- Glossary entry, word-only and combined results, unknown-word recovery,
  selected links, article meanings, related guides, and Back query/history
  behavior pass. Existing header shortcut coverage now includes glossary and
  selected/unknown glossary routes.
- Keyboard Tab/Enter activation, destination focus, heading/button semantics,
  and combined live counts pass.
- Light and dark layouts pass at **320 x 568 with doubled text** and disabled
  animations, without widget exceptions. The glossary reuses shared body
  typography; the tested text contrast meets the 4.5:1 check.
- Back to top appears after scrolling and returns the glossary to offset zero.
  The generated article definitions also participate in contents-menu traversal.
- Focused Dart analysis reported **no issues**. Formatting and the implementation
  `git diff --check` completed successfully.
- Selected EVV and light/dark enlarged-text glossary captures were inspected.

Commands used from `frontend/`:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat gen-l10n
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics format lib/features/help test/features/help
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub --reporter expanded --dart-define=HELP_FONT_DIR=C:/Users/SQ/flutter/bin/cache/artifacts/material_fonts --dart-define=HELP_CAPTURE_DIR=C:/Users/SQ/Desktop/gitStuff/2026_fall_careconnect/tmp/windows-online/help-verification/glossary
```

The test log is a local artifact at
`tmp/windows-online/help-verification/glossary-tests.log`. Captures are under
`tmp/windows-online/help-verification/glossary/`. These ignored artifacts are
not source files to include in the commit.

## Verification limits and future maintenance

Automated semantics and viewport tests do not replace physical screen-reader
testing or reader comprehension review. Real announcements, touch and keyboard
focus, and supported-device behavior still need that review. No new live-app
or physical-device verification was performed, and the full application test
suite was not run.

Enlarged-text tests inject scaling into the harness. The existing app-wide
text-scaling clamp remains outside this feature. At a very narrow width with
doubled text, long labels wrap and the content remains scrollable.

The real-font harness loads Roboto Regular and Material Icons. AppBar titles
can appear as blocks when the test environment lacks the platform fallback
font; that artifact does not establish a production font problem.

English definitions and aliases do not provide translated content for all
supported locales. Future translated catalogs must keep the same permanent
IDs. The eager glossary layout is suitable for the current 75-entry catalog;
substantial growth should prompt a performance review of browsing and direct
link targeting.

Future content work should edit the shared Dart catalog, add relevant glossary
IDs to articles, and rerun the focused Help suite. The existing guides remain responsible
for current step-by-step workflows, while the glossary explains stable concepts.
See [glossary.md](../help/glossary.md) for the maintenance guide.

No Git commit or push was performed while writing these notes.
