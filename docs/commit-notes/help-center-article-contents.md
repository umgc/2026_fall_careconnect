# Commit notes: Help article contents menus

## Suggested commit title

Add accessible article contents menus generated from section headings

## Suggested commit body

Add an expanded On this page menu beneath Help article titles and summaries
when an article has at least two named sections. Generate its links from the
same heading resolver used by the article renderer, so heading changes and
section ordering automatically update the menu. Add useful headings to
previously unnamed paragraphs and step groups in the bundled guides.

Let readers collapse the menu without hiding article content. Selecting a
section scrolls its heading below the fixed header and transfers keyboard
focus to it. Give each section a separate anchor so repeated heading names
remain valid. Respect reduced-motion settings, expose the toggle's expanded
state on its accessible control, and preserve Back to top behavior.

Reject empty authored headings and add focused accessibility, navigation,
theme, and enlarged-text tests. Extend the disconnected production-route
flow to traverse every bundled article's menu. All 49 Help tests pass;
focused Dart analysis reports no issues. Document the authoring rules and
remaining physical screen-reader verification.

## Behavior and implementation

- The menu appears inside the article scroll view, beneath the title and
  summary. It starts expanded and appears only with two or more named sections.
- Entries follow section order. Unnamed sections remain readable but have no
  menu entry. Troubleshooting and related articles keep their existing
  localized default headings; authored headings override those defaults.
- `helpSectionHeading` supplies both menu labels and rendered headings.
  There is no separate contents list for authors to keep synchronized.
- `HelpArticleContent` becomes stateful to retain per-section `GlobalKey`
  anchors, focus nodes, and the menu expansion state. Targets are recreated
  when the article ID or section collection changes and disposed appropriately.
- Each entry uses its section position rather than heading text to identify
  its target. Duplicate heading names are supported.
- Activating a link calls `Scrollable.ensureVisible` with top alignment,
  then requests focus on the destination heading. The animation lasts
  300 milliseconds with an ease-out curve; disabled animations use zero duration.
- Destination headings have header semantics and programmatic focus nodes
  that do not introduce extra ordinary Tab stops. The contents toggle merges
  its label, button behavior, and expanded/collapsed state into one semantics node.
- The menu uses shared app typography and Material controls with a minimum
  height of 48 logical pixels. It participates in the existing article scroll
  view and Back to top behavior.
- `HelpRepository` rejects authored headings that are empty or whitespace-only.
  Null headings and repeated nonempty headings remain valid.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Modified | Adds the generated collapsible contents menu, persistent section anchors, heading focus transfer, reduced-motion scrolling, toggle semantics, and target lifecycle handling. |
| `frontend/lib/features/help/presentation/widgets/help_section_heading.dart` | Added | Centralizes authored and localized default heading resolution for the menu and article renderer. |
| `frontend/lib/features/help/data/bundled_help_content.dart` | Modified | Adds descriptive headings to unnamed introductory paragraphs and numbered step groups across the existing guides. Article IDs and instructional body text are preserved. |
| `frontend/lib/features/help/data/help_repository.dart` | Modified | Rejects empty or whitespace-only authored headings during catalog validation. |
| `frontend/lib/l10n/app_en.arb` | Modified | Adds `helpOnThisPage` and its translator description. |
| `frontend/missing_translations.txt` | Modified | Regenerates the missing-translation report with the new label in the 13 other locales; the existing English fallback applies. |
| `frontend/test/features/help/help_article_contents_test.dart` | Added | Adds seven cases for menu order, collapse/expand semantics, every section target including duplicate names, keyboard activation, heading focus/semantics, Back to top, disabled animations, single-section omission, and narrow light/dark layouts. |
| `frontend/test/features/help/help_article_page_test.dart` | Modified | Updates related-article heading assertions to distinguish the new menu entry from the article heading. |
| `frontend/test/features/help/help_center_page_test.dart` | Modified | Targets the actual Web section heading rather than its new contents entry in the enlarged-text flow. |
| `frontend/test/features/help/help_flow_test.dart` | Modified | Uses the app's shared light theme with Roboto in the production-route harness and traverses every bundled article's contents entries with refused HTTP and doubled text. |
| `frontend/test/features/help/help_repository_test.dart` | Modified | Adds a validation case rejecting blank headings while accepting repeated heading names. |
| `docs/help/article-contents.md` | Added | Documents menu behavior, heading authoring, shared heading resolution, validation rules, test commands, and verification boundaries. |
| `docs/commit-notes/help-center-article-contents.md` | Added | These commit notes, file inventory, and validation record. |

Flutter regenerated the ignored `frontend/lib/l10n/app_localizations*.dart`
files for the new label. Those generated outputs are not additional source
files to stage under the repository's current ignore rules.

## Validation completed

Verified October 4, 2026. Results were obtained during implementation;
writing these notes did not rerun the suite.

From `frontend/`, using the installed SDK:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat gen-l10n
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics format lib/features/help test/features/help
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub --reporter expanded
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

- All **49 Help tests passed**: ten repository tests, six article-screen tests,
  six home catalog tests, thirteen home-screen tests, seven flow tests, and
  seven new contents-menu tests.
- Contents-menu checks verify order, collapse/expand semantics, every target
  including repeated names, header semantics, destination focus, and placement
  below the AppBar.
- Tab/Enter activation and subsequent Back to top pass. A separate case checks
  immediate section jumping with animations disabled.
- Light and dark themes pass at **320 x 568** with doubled text and no widget
  exceptions. A one-section article omits the menu.
- The production-route flow traverses every bundled article's menu and related
  links with network requests refused and doubled text at narrow width.
- After switching the production-route harness to the shared app theme, all
  **seven flow cases passed again** with real Roboto fonts and optional captures.
- Focused Dart analysis reported **no issues**. Formatting and
  `git diff --check` passed.

The real-font flow/capture run used:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help/help_flow_test.dart --no-pub --dart-define=HELP_FONT_DIR=C:/Users/SQ/flutter/bin/cache/artifacts/material_fonts --dart-define=HELP_CAPTURE_DIR=C:/Users/SQ/Desktop/gitStuff/2026_fall_careconnect/tmp/windows-online/help-verification/contents --reporter expanded
```

Desktop and phone article menu captures were inspected for readable content,
wrapping, and placement. Captures and test logs remain local artifacts under
the ignored `tmp/windows-online/help-verification/` directory. The test harness
does not explicitly assign the AppBar title's font family, so its title can
render with the test fallback font; that title is not evidence of production
font rendering. No new font assets or dependencies were added.

## Verification limits and maintenance

Automated semantics and focus checks do not replace a physical screen-reader
review. Heading announcements, focus transitions, and touch/keyboard behavior
still need review in supported builds. No new live-app or physical-device check
was performed, and the full application test suite was not run.

The enlarged-text harness supplies scaling directly. The existing app-wide
text-scale clamp remains outside this change. Interface labels use app
localization; authored article headings continue to follow the English bundled
content convention.

For future articles, add concise headings to sections readers should be able
to jump to. The menu will update automatically. Maintain article IDs when
renaming headings or reordering sections. Authoring details are in
[article-contents.md](../help/article-contents.md).

This commit scope implements the article contents menu and its associated
validation/accessibility checks. Glossary implementation remains future work.
No commit or push was performed while writing these notes.
