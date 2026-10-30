# Help Center Step 9 verification

Verified October 3, 2026, with Flutter 3.41.9 / Dart 3.11.5 on Windows.

## Plan and outcome

1. Exercise the real Settings and Help screens through production route
   definitions. Confirm Help is the first General entry and test the complete
   Settings → Help → Topic → Article → Back sequence.
2. Refuse HTTP and simulate disconnected connectivity. Verify local search,
   empty results, missing-content recovery, every bundled ID, and related links.
3. Check desktop, phone-sized, and enlarged-text layouts; inspect the running
   Windows preview separately from widget tests.
4. Run the focused suite and static analysis, then record device-check limits.

The automated checks pass. The live Windows preview renders and returns through
the tested routes correctly. Physical disconnection, real mobile input, browser
offline reloads, and real screen-reader checks remain unverified.

## Results

| Requirement | Evidence | Result / boundary |
| --- | --- | --- |
| Help first under General | New flow tests build Settings, scroll to General, and assert Help followed by Offline Persistence. Readable desktop/phone captures inspected. | Passed at 1366 × 900 and 390 × 844. |
| Settings → Help → Topic → Article → Back | Tests tap the actual Settings row and Help entries, then use back navigation through all three screens to Settings. Production route definitions and telemetry router observer are used. | Passed in both layouts. Providers, preferences, and platform channels are test substitutes. |
| Search and empty results | Keyword `medicine` opens the dose guide; returning preserves the query. A nonexistent query shows the empty message and Browse Topics restores visible topics. Existing catalog/home tests cover title, description, keywords, content, normalization, and role filtering. | Passed locally with HTTP refused. |
| Missing content | Production article/topic routes receive unknown IDs; each fallback returns to Help Center. | Passed. |
| IDs and links | Existing repository tests reject malformed/duplicate IDs and invalid references. The new flow test opens all eight articles and all six categories, then taps every related link and returns to its source article. | Passed at 320 × 568 with double text size; no widget exceptions. |
| Disconnected access | Connectivity reports `none`; the injected HTTP client throws for every request. Settings' notification request fails as expected. The Help flow adds no HTTP requests after initial Settings/provider setup. | Passed in the test harness. Host connectivity was not changed. Telemetry is opted out in this harness. |
| Desktop/mobile-sized layout | Eight readable captures cover Settings General, Help home, topic, and article at desktop and phone sizes, using SDK Roboto/Material Icons fonts. Existing tests also cover dark/light themes and enlarged text. | Inspected; no Help overflow. Long phone app-bar titles truncate, while full article titles wrap in the scrollable body. These are widget viewports, not physical mobile devices. |
| Running Windows preview | The already-running preview was attached to its Flutter debug service. Existing router methods opened Settings, Help, Medications, and the dose article, then popped back through topic, home, and Settings. Engine screenshots inspected at the current 648 × 998 surface in the app's dark theme. | Passed for route rendering/back stack. This used debugger router invocation, not physical mouse/keyboard interaction. Help was left open and the debugger detached. |
| Accessibility/localization regression | Existing tests cover Tab/Shift-Tab, Enter/Space, focus transfer, semantic button labels, result announcements, light/dark themes, large text, and English fallback for untranslated labels. | Passed. Actual screen-reader output is not established by semantics tests. |

## Changes and validation

- Added `frontend/test/features/help/help_flow_test.dart`: four flow tests using
  real route definitions and screens, refused HTTP, disconnected platform
  channels, desktop/phone sizes, and all-content/related-link traversal.
- Added optional local screenshot capture and SDK-font loading to that test
  harness. Ordinary test runs write no images and require no font path.
- Updated the feature README and content-verification record to link these
  results and retain outstanding live-platform checks.
- No production behavior, article content, dependencies, preview bypasses,
  native integrations, or package manifests changed in Step 9.

From `frontend/`:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

All **34 Help tests passed**: 30 existing tests and four new flow cases.
Focused static analysis reported no issues. `git diff --check` passed.
The whole application test suite was not run; these checks target the Help work.

To reproduce readable layout artifacts, from `frontend/`:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help/help_flow_test.dart --no-pub --dart-define=HELP_CAPTURE_DIR=C:/Users/SQ/Desktop/gitStuff/2026_fall_careconnect/tmp/windows-online/help-verification --dart-define=HELP_FONT_DIR=C:/Users/SQ/flutter/bin/cache/artifacts/material_fonts
```

Adjust both absolute paths for another machine. The font directory must contain
`roboto-regular.ttf` and `materialicons-regular.otf`; these are SDK artifacts,
not new app dependencies. All four cases also passed with font loading/captures
enabled. Local images and the temporary live-debug probe are ignored artifacts
under `tmp/windows-online/help-verification/`, not files to stage or publish.
Windows live captures use `windows-live-*.png`; test captures use
`desktop-*.png` and `phone-*.png`.

## Remaining device checks

These checks require an actual device/browser or assistive-technology session;
they must not be marked passed based on widget substitutes:

1. On Windows preview and a supported mobile build, open Help, disconnect the
   device, and repeat topic/article/search/back navigation. Check readable Help
   separately from offline saving/replay, which the Windows preview disables.
2. Repeat Settings navigation and search with physical desktop keyboard/mouse
   and mobile touch/software keyboard, including dismissing the keyboard and
   system back navigation. Use device large-text settings as well.
3. Run a screen reader on each supported platform; verify focus order, entry
   labels, result announcements, and article reading order.
4. In a browser, distinguish an already-loaded Help catalog from first load or
   reload while disconnected. Check browser history/back and responsive layout.

The [content verification record](content-verification.md) separately tracks
unverified dose saving, appointment loading, message delivery, reset emails,
and check-in entry points. Step 9 Help navigation tests do not validate those
server workflows or change the native check-in's mock submission.
