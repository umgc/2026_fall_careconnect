# Commit notes: Help Center WCAG accessibility review and fixes

## Suggested commit title

Improve Help Center contrast, text scaling, targets, and screen-reader semantics

## Suggested commit body

Apply a shared accessibility theme across Help home, search, topics, articles,
and the glossary. Replace low-contrast accent text, strengthen typography and
control outlines, use 48px targets, and add visible keyboard-focus borders.
Preserve the user's full platform text scaling on Help routes, including
nonlinear scaling. Keep navigation usable in narrow and short viewports and
prevent search-label truncation when text spacing increases.

Add descriptive page titles, wrapping level-one headings, and section heading
levels. Give article, topic, and glossary buttons distinct navigation hints,
retain live result counts and expanded states, and tag English Help content
with its language. Focus linked glossary headings with their selected state,
restore search focus after clearing, and return focus to the title after Back
to top. Preserve the app locale for the translated system Back label.

Add all-page contrast, target-size, reflow, spacing, scaling, and semantics
regressions. All 70 Help tests pass, focused static analysis reports no issues,
and 24 light/dark layouts were rendered and reviewed. Record the WCAG 2.1 AA
review and the remaining live browser and assistive-technology checks.

## Findings and resulting behavior

- Light-mode accent text previously measured 2.85:1 against white. Help now uses
  `#00677D`, which measures 6.49:1. Dark-mode accent text uses `#5AD4E8`, which
  measures 9.86:1 against the dark card surface.
- Main text measures 17.85:1 in light mode and 13.91:1 in dark mode. Search and
  navigation outlines measure 4.76:1 and 6.78:1 respectively. Regression tests
  use 4.5:1 for text and 3:1 for control/focus boundaries.
- Body text and control labels use a 16px base. Body text has stronger weight
  and 1.5 line height; term and section headings have stronger weights.
  Floating search labels remain visibly 16px after Material's scaling transform.
- Help routes preserve the original platform `TextScaler`. The application's
  previous 120% cap no longer constrains Help; route changes update the policy,
  and nonlinear scaling survives entry and return navigation.
- Buttons and icon buttons have 48px targets; navigation tiles have at least
  48px height. Compact platform density is disabled within Help. This target
  size is an additional usability measure: target size is AAA in WCAG 2.1,
  and WCAG does not specify a universal minimum font size.
- Focused controls and tiles show a 3px outline. Header shortcuts wrap with
  enlarged text and scroll vertically when needed in short viewports, leaving
  room for the page body.
- Full page titles wrap in the body as level-one headings. Route/application
  titles describe the current destination. Section, troubleshooting, glossary,
  and associated-article headings expose their hierarchy.
- Article/topic/word buttons announce their visible title and optional summary
  together, with a destination-specific hint. Decorative chevrons are excluded.
  Search counts remain live regions and the contents toggle exposes its state.
- Glossary deep links focus the named word heading with selected semantics.
  Clearing search returns focus to the field. Back to top returns focus to the
  page title; article contents links still focus their section headings.
- Current English Help content and fallback interface labels expose English
  language and reading direction. The system Back tooltip retains the app
  locale. The Help language scope must be revisited when translations are added.

## File inventory

Paths below are relative to the repository root.

| File or group | Change |
| --- | --- |
| `frontend/lib/features/help/presentation/widgets/help_accessibility.dart` | Adds shared contrast, typography, target-size, focus, language, direction, and page-title configuration. |
| `frontend/lib/features/help/presentation/widgets/help_glossary_theme.dart` | Removes the glossary-only theme in favor of the shared Help configuration. |
| `frontend/lib/features/help/presentation/widgets/help_link_tile.dart` | Adds shared named navigation tiles with hints and visible focus borders. |
| `frontend/lib/features/help/presentation/widgets/help_back_to_top.dart` | Adds a shared labeled scroll shortcut with readable typography and a focus ring. |
| `frontend/lib/config/theme/app_text_scaling.dart` | Adds route-aware preservation of platform text scaling in Help. |
| `frontend/lib/main.dart` | Applies the route-aware scaling wrapper at the application boundary. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Applies shared accessibility configuration, page heading/title, navigation semantics and search-focus restoration. |
| `frontend/lib/features/help/presentation/pages/help_topic_page.dart` | Applies shared configuration and complete page heading/title, including missing topics. |
| `frontend/lib/features/help/presentation/pages/help_article_page.dart` | Applies shared configuration, title focus, scroll shortcut and missing-article heading/title. |
| `frontend/lib/features/help/presentation/pages/help_glossary_page.dart` | Applies shared configuration, named word focus, title focus and search-focus restoration. |
| `frontend/lib/features/help/presentation/widgets/help_app_bar.dart` | Keeps enlarged/short-view navigation usable, uses shared title typography and preserves the Back tooltip language. |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Adds heading levels and title focus; uses shared related-article navigation tiles. |
| `frontend/lib/features/help/presentation/widgets/help_article_tile.dart` | Uses the shared navigation tile with an article hint and merged semantics. |
| `frontend/lib/features/help/presentation/widgets/help_topic_tile.dart` | Uses the shared navigation tile with a topic hint and merged semantics. |
| `frontend/lib/features/help/presentation/widgets/help_glossary_entry.dart` | Adds focused/selected term headings and heading hierarchy; uses shared word-result navigation semantics. |
| `frontend/lib/l10n/app_en.arb`, `frontend/missing_translations.txt` | Adds four destination hints and regenerates the translation report. |
| `frontend/test/features/help/help_accessibility_test.dart` | Adds ten accessibility cases covering every Help route, spacing, scaling, focus, language and announcements. |
| `frontend/test/features/help/help_flow_test.dart` | Exercises the production scaling wrapper, adds optional visual captures and targets the page scroll view explicitly. |
| `frontend/test/features/help/help_center_page_test.dart`, `help_article_page_test.dart`, `help_article_contents_test.dart` | Updates assertions for scoped typography, full body headings and explicit scroll-view keys. |
| `docs/help/accessibility-audit.md` | Records findings, measured contrast, criterion coverage, validation and platform verification limits. |
| `frontend/lib/features/help/README.md` | Links the accessibility review. |
| `docs/commit-notes/help-center-wcag-accessibility.md` | Records the suggested commit message and implementation evidence. |

## Validation completed

Verified October 4, 2026. These results were obtained during implementation;
writing the commit notes did not rerun the tests.

- **70 Help tests passed.** Ten new accessibility cases cover all six topics,
  eight articles, selected/unknown glossary words, and missing topic/article
  states in both themes.
- Viewports cover 390×844, 320×568 with 200% text, and 844×390 with 200% text.
  Checks include effective text contrast, labeled 48px targets, heading levels,
  route titles, keyboard focus, language, live results and preserved scaling.
- Increased letter/word/line spacing reflows without clipped body text at 320px.
  Nonlinear scaling and restoration of the existing policy outside Help pass.
- The optional capture case passed with real SDK fonts. **24 captures** cover
  home, topic, article and selected glossary in both themes and three layouts.
- Focused static analysis reported **no issues**. `git diff --check` passed.

Commands from `frontend/`:

```powershell
flutter test --no-pub test/features/help --reporter expanded
flutter analyze --no-pub lib/features/help lib/config/theme/app_text_scaling.dart test/features/help
```

For captures, run `test/features/help/help_flow_test.dart` with
`--plain-name "all Help surfaces"`, setting `HELP_CAPTURE_DIR` to a writable
absolute output directory and `HELP_FONT_DIR` to the SDK's
`bin/cache/artifacts/material_fonts`. The harness loads Roboto regular, medium,
bold, and Material Icons.

Logs and PNGs under `frontend/build/help-wcag-audit/` and the other
`frontend/build/help-audit-*` paths are ignored verification artifacts.

## Verification limits

The review covers source, widget semantics, automated layouts and rendered
captures. It does not establish formal WCAG conformance or actual screen-reader
speech. Live NVDA, VoiceOver and TalkBack checks remain necessary, along with
browser 400% zoom, text/paragraph spacing overrides, tooltip dismissal and
persistence, and focused/hovered contrast on supported platforms. The full
application test suite was not run.

See the [accessibility audit](../help/accessibility-audit.md) for criterion
coverage and the remaining platform checklist. No Git commit or push was
performed while writing these notes.
