# Help glossary: implementation and maintenance

For step-by-step catalog changes, reference cleanup, restoration, and preview
instructions, use the [developer maintenance handbook](maintenance.md#glossary).

The glossary contains the 75 approved terms with short, plain-language meanings.
The approved alias map includes 551 everyday phrases, questions, abbreviations,
and alternative names. Redundant aliases are removed after normalization.

## Reader experience

- Help Center Home has a Glossary entry. All definitions are visible in one
  alphabetical list, without opening 75 separate detail pages.
- Find a word searches labels, aliases, and definitions. Exact labels rank
  before exact aliases, followed by partial name/alias and definition matches.
- Help home searches both articles and words. Results use separate Articles
  and Words and meanings headings. The live announcement includes both counts.
  A word-only result does not display the empty-articles message.
- Article references produce a Words in this article section with the shared
  meanings. That section also appears in the article contents menu.
- See [term] in glossary opens `/help/glossary?term=<permanent-id>`, scrolls to
  that definition, marks it selected, and moves focus to it. Other words remain
  available. An unknown ID shows a recovery message and the full glossary.
- Related guides are drawn from existing article references, so adding a word
  to an article automatically creates its glossary backlink. Links respect the
  article audience. Terms without a relevant guide show their meaning alone.
- Existing Back behavior and Help header shortcuts also work on the glossary.
  Its Back to top button appears at 320 pixels of scrolling and disappears
  nearer the top. Reduced-motion settings use immediate jumps.
- Reading and searching this content require no network, login request, new
  dependency, font download, or database. The shared app theme supplies text
  styles and colors.

## Single source of truth

Edit `frontend/lib/features/help/data/bundled_glossary_content.dart` for labels,
definitions, and aliases. The Markdown alias map records the approved review;
the app does not parse it at runtime. Keep permanent IDs when changing wording
or translating content.

Use `glossaryTermIds` in `HelpArticle` to list relevant words in the order readers
should see them:

```dart
glossaryTermIds: ['appointment', 'scheduled-visit', 'evv'],
```

`HelpRepository.sectionsForArticle` generates the definitions section. Do not
copy meanings into article text or maintain a second contents-menu list.
`articlesForGlossaryTerm` generates backlinks. An optional `relatedArticleIds`
on a term can link an existing guide that does not reference the term directly.

Repository construction rejects malformed or duplicate IDs, duplicate display
labels after normalization, blank meanings, missing article/term targets, and
empty or repeated glossary references. Models make defensive immutable copies.
Aliases are trimmed and deduplicated per term; overlap between different terms
is permitted. Apostrophes, hyphens, case, repeated spaces, and punctuation are
normalized. Common question filler is ignored while meaningful negatives such
as `no`, `not`, `without`, and `can't` remain searchable.

The interface uses the existing ARB localization system. The glossary catalog
is currently English, as are the bundled articles. New UI labels fall back to
English in locales awaiting translation. Preserve term IDs across future
translated catalogs; routes must never depend on translated labels.

## Content review

Prefer short first sentences, concrete examples, and one idea per sentence.
Avoid assuming readers know abbreviations or medical language. Task phrases
help discovery; they do not promise that a feature works on every device.
Keep dose distinct from dosage, daily check-ins from virtual check-ins, and
offline saving from cache and synchronization. Definitions describe concepts;
existing guides carry current step-by-step instructions.

Feature labels and guide connections were checked against the bundled Help
catalog and the app's router, menus, medication/check-in screens, EVV tools,
and `features/stml/presentation/pages/stml_brief_page.dart`. General device,
permission, and communication definitions avoid specific compatibility claims.
The allergy definition was checked against the
[NHS explanation of allergies](https://www.nhs.uk/conditions/allergies/) and
[food allergy and immune response](https://www.nhs.uk/conditions/food-allergy/).
The medicine examples explain vocabulary rather than prescribing treatment.

## Verification

From `frontend/`:

```powershell
flutter gen-l10n
dart analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
flutter test test/features/help --no-pub
```

`help_glossary_catalog_test.dart` checks all 75 terms and every retained alias,
exact-match ranking, question punctuation, negation, immutable data, invalid
references, generated sections, and audience filtering.

On October 4, 2026, all **59 Help tests passed** and the focused Dart analyzer
reported **no issues**. Light/dark glossary captures and the selected EVV entry
were inspected for clipping, readable text, and consistent header placement.

`help_flow_test.dart` uses the production routes with refused HTTP. It exercises
home entry, article definitions, selected/unknown direct links, related guides,
Back history, header shortcuts, search recovery, live counts, button semantics,
Tab/Enter activation, selected-word focus, and Back to top. Light and dark
layouts are checked at 320 x 568 with doubled text and reduced motion. The
existing article contents and complete Help tests remain part of this suite.

Optional screenshot capture uses `HELP_FONT_DIR` and `HELP_CAPTURE_DIR` Dart
defines, as in the existing Help flow harness. Captures are local QA artifacts
under `tmp/windows-online/help-verification/glossary/`; do not commit them.
The harness loads Roboto Regular and Material Icons. App-bar titles can appear
as blocks where the harness lacks the platform fallback font; those captures
do not establish a production font failure.

Widget semantics and viewport tests do not replace a physical screen-reader
review or testing on supported devices. Review real announcements, touch and
keyboard focus, and comprehension with representative readers before claiming
full accessibility coverage. The existing app-wide text-scaling clamp remains
outside this Help feature; the tests inject enlarged scaling directly.
