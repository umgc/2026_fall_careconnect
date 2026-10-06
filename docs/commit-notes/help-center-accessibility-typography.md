# Commit notes: Help Center typography accessibility

## Suggested commit title

Improve Help Center readability with shared app typography

## Suggested commit body

Use the app's shared text styles throughout Help home, topics, and articles.
Help already inherited the Roboto font and application theme, but article and
topic cards relied on default ListTile typography, and headings used Material
defaults instead of the app's bold heading styles.

Apply shared 16px body text and primary text colors to card summaries, search
input, empty states, and missing-content descriptions. Use shared bold heading
styles for home headings, article titles, and article sections, and consistent
16px medium-weight titles for navigation entries and troubleshooting problems.

Run home and article widget checks with AppTheme and the same Roboto text-theme
configuration as the app. Add light/dark typography and contrast checks, and
verify article headings and paragraph styles. All 36 Help tests pass, including
keyboard navigation, semantics, and narrow layouts with doubled text. Focused
Dart analysis reports no issues.

## Findings and resulting behavior

- `frontend/lib/main.dart` applies Roboto to both `AppTheme.lightTheme` and
  `AppTheme.darkTheme`. Help screens inherit those resources; they do not load a
  separate font or theme.
- Article and topic card titles now explicitly use `textTheme.titleMedium`;
  summaries and descriptions use `textTheme.bodyLarge` (16px with the app's
  primary text color and line spacing).
- Help home headings and article section headings use
  `textTheme.displaySmall` (20px bold). Article body titles use
  `textTheme.displayMedium` (24px bold).
- Search input, empty-result messages, and missing-topic/article descriptions
  use the shared body style. Troubleshooting problem titles and related article
  links use `textTheme.titleMedium` (16px, medium weight).
- Styles are resolved through `Theme.of(context)`, so light and dark modes use
  their respective shared colors and typography.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Applies shared body text to search and empty states, and shared bold styling to Popular Help, search-result, and Browse Topics headings. |
| `frontend/lib/features/help/presentation/pages/help_topic_page.dart` | Modified | Applies shared body text to missing-topic descriptions and empty article lists. |
| `frontend/lib/features/help/presentation/pages/help_article_page.dart` | Modified | Applies shared body text to missing-article descriptions. |
| `frontend/lib/features/help/presentation/widgets/help_article_tile.dart` | Modified | Explicitly applies shared medium titles and 16px primary-colored summaries. |
| `frontend/lib/features/help/presentation/widgets/help_topic_tile.dart` | Modified | Explicitly applies shared medium titles and 16px primary-colored descriptions. |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Modified | Uses shared bold article/section headings, medium troubleshooting titles, and explicit shared related-link titles. Existing article body text continues using the shared body style. |
| `frontend/test/features/help/help_center_page_test.dart` | Modified | Uses AppTheme with Roboto in both modes; adds two typography/contrast cases checking card titles, descriptions, home heading, and search input. Existing enlarged-text checks now exercise the app theme. |
| `frontend/test/features/help/help_article_page_test.dart` | Modified | Uses the shared light theme with Roboto and extends the rendering test to verify article title, paragraph, and section-heading styles. |
| `docs/commit-notes/help-center-accessibility-typography.md` | Added | Records the commit description, findings, file inventory, validation, and verification limits. |

## Validation completed

Verified October 4, 2026. Results below were obtained during implementation;
writing these notes did not rerun the tests.

From `frontend/`, using the installed SDK:

```powershell
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe format lib/features/help/presentation test/features/help/help_center_page_test.dart test/features/help/help_article_page_test.dart
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

- All **36 Help tests passed**: nine repository tests, four article-screen
  tests, six home catalog tests, thirteen home-screen tests, and four flow tests.
- New light/dark checks confirm that card descriptions use the shared Roboto
  16px body style and have at least **4.5:1** calculated contrast against the
  theme surface. Home headings use the shared bold style.
- Article rendering checks confirm shared Roboto bold title, body paragraph,
  and section-heading styles.
- Existing keyboard, semantic labels/announcements, search, navigation,
  localization fallback, and narrow-screen/doubled-text checks pass.
- Focused Dart analysis reported **no issues**. `git diff --check` passed for
  the implementation changes.

The formatter completed its edits but initially returned a telemetry file
access error under the workspace sandbox. Analysis also encountered an SDK
process-launch restriction. Tests and analysis then completed successfully
using the installed SDK with sandbox escalation.

## Verification limits

This change was verified through source inspection and automated widget tests.
No fresh screenshots, live application review, physical-device checks, or real
screen-reader checks were performed. Contrast assertions cover the card
description text and theme surface; they are not an audit of every app color.
The full application test suite was not run.

The app-wide text-scale clamp in `main.dart` was observed and remains outside
this typography change. Doubled-text checks set scaling directly in the widget
harness; they do not establish that the production app honors a 200% system
text-size setting.

No font assets, dependencies, shared theme definitions, article content, or
localization resources were changed. No commit or push was performed.
