# Commit notes: Help Center navigation and article scrolling

## Suggested commit title

Add Help header shortcuts and article Back to top navigation

## Suggested commit body

Add Help Center Home and Back to Settings buttons to the header of every Help
screen, including missing-topic and missing-article screens. Each shortcut
goes directly to its destination and clears accumulated Help navigation, so
readers can leave a chain of related articles with one click. Preserve the
existing Back button's step-by-step behavior.

Use a shared header that keeps the shortcuts visible while content scrolls and
wraps the buttons to fit narrow screens and enlarged text. Add a floating Back
to top button to articles after scrolling 320 logical pixels. Hide it again
below that threshold, and return to the beginning when activated. Respect
disabled animations and reserve extra space below article content.

Add localized labels and regression coverage for direct entry, deep article
chains, header placement, enlarged-text layouts, and scroll-button behavior.
All 41 Help tests pass, and focused Dart analysis reports no issues.

## Resulting behavior

| Control | Availability | Action |
| --- | --- | --- |
| Existing Back button | Same route-dependent availability as before | Returns to the previous screen in the navigation stack. |
| Help Center Home | Header on Help home, topics, articles, and missing-content screens | Uses `context.go(HelpRoutes.home)` to reach `/help` directly and discard the accumulated stack. |
| Back to Settings | Header on every Help screen | Uses `context.go('/settings')` to reach Settings directly and discard the accumulated stack. |
| Back to top | Article screen after scrolling at least 320 logical pixels | Returns the article scroll offset to zero; disappears when the offset falls below 320. |

The header retains the ordinary AppBar title and Back control, with the two
shortcuts in its bottom section. Button labels use shared `titleMedium`
typography and a minimum height of 48 logical pixels. Header sizing measures
the labels using the current text scale and direction, and reserves enough
space for one or two rows. Buttons remain outside the scrolling content.

The article screen now owns and disposes a `ScrollController`. It rebuilds
when scrolling crosses the visibility threshold. Back to top uses a labeled
floating button with an upward arrow at the bottom start corner (bottom-left
in the current left-to-right layout). It scrolls to zero over 300 milliseconds
with an ease-out curve, or jumps immediately when animations are disabled.
Article content has 96 logical pixels of bottom padding to leave room for the
floating control. Missing articles never show the floating button; short
articles that cannot reach the threshold do not show it either.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/presentation/widgets/help_app_bar.dart` | Added | Builds the shared Help AppBar and calculates the space needed for wrapping navigation buttons using label measurements, available width, text scale, and direction. |
| `frontend/lib/features/help/presentation/widgets/help_navigation_bar.dart` | Added | Provides the two labeled, icon-bearing shortcuts with shared typography, wrapping layout, and direct route navigation. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Uses the shared header with shortcuts on the Help home screen. |
| `frontend/lib/features/help/presentation/pages/help_topic_page.dart` | Modified | Uses the shared header on normal and missing-topic screens. |
| `frontend/lib/features/help/presentation/pages/help_article_page.dart` | Modified | Uses the shared header; becomes stateful to manage article scrolling and the conditional Back to top button; adds bottom padding and disposes the scroll controller. |
| `frontend/lib/l10n/app_en.arb` | Modified | Adds `helpCenterHome`, `helpBackToSettings`, and `helpBackToTop`, with translator descriptions. |
| `frontend/missing_translations.txt` | Modified | Regenerates the report to include the three new labels in the 13 other locales where translations are missing. These labels use the existing English fallback. |
| `frontend/test/features/help/help_article_page_test.dart` | Modified | Adds tests for scroll-button visibility, bottom-left placement, hiding near the top, returning to offset zero, and absence on a short article. |
| `frontend/test/features/help/help_center_page_test.dart` | Modified | Updates the keyboard traversal test to account for the two header shortcuts before search. |
| `frontend/test/features/help/help_flow_test.dart` | Modified | Adds three flow cases covering persistent header shortcuts on every Help screen and both destinations after a related-article chain. Verifies ordinary Back still returns to the previous article. Adjusts enlarged-text link activation to tap the visible first line of a long link. |
| `docs/commit-notes/help-center-navigation.md` | Added | These commit notes, behavior details, file inventory, and validation record. |

Flutter regenerated the ignored `frontend/lib/l10n/app_localizations*.dart`
files. Those generated files are not additional source files to stage under
the repository's current ignore rules.

## Validation completed

Verified October 4, 2026. These results were obtained during implementation;
writing these notes did not rerun the suite.

From `frontend/`, using the installed SDK:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat gen-l10n
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics format lib/features/help/presentation test/features/help
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub --reporter compact
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

- All **41 Help tests passed**: nine repository tests, six article-screen
  tests, six catalog tests, thirteen home-screen tests, and seven flow tests.
- The shortcut availability test covers Help home, a topic, an article, and
  both missing-content screens at **320 x 568** with doubled text. It checks
  that both controls are inside the AppBar, remain reachable after scrolling,
  and navigate directly to the requested destination.
- Two related-article-chain cases verify that ordinary Back returns to the
  preceding article and that either shortcut clears the accumulated stack.
- Article checks verify the floating button's visibility after scrolling,
  position, hiding near the top, and return to the beginning. The enlarged-text
  case runs at **320 x 568**; a separate short-article case confirms absence.
- Existing search, ordinary back navigation, keyboard, semantics, typography,
  light/dark theme, and enlarged-text checks remain passing.
- Focused Dart analysis reported **no issues**. Formatting required no further
  changes at the final check. `git diff --check` passed.

## Verification limits

Validation used source inspection and widget tests. No fresh screenshots, live
application review, physical-device checks, or real screen-reader checks were
performed. The full application suite was not run. The reduced-animation
branch is implemented but was not separately exercised by a new test.

The existing app-wide text-scale clamp remains outside this change; doubled
text is supplied directly by the test harness. New button labels currently
fall back to English in locales without translations. Settings flow tests use
mock providers/platform channels and refused HTTP requests, so they establish
navigation rather than live Settings service behavior.

No commit or push was performed while implementing these changes or writing
these notes.
