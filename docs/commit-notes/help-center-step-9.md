# Commit notes: Help Center step 9

## Suggested commit title

Verify Help Center navigation, offline reading, and responsive layouts

## Suggested commit body

Add four focused flow tests using the production route definitions and real
Settings/Help screens. Confirm Help is the first entry under General, before
Offline Persistence, and exercise Settings → Help → Topic → Article → Back at
desktop and phone-sized viewports.

Simulate disconnected connectivity and refuse HTTP requests. Verify keyword
search, query preservation after returning from an article, empty-result topic
browsing, unknown article/topic recovery, and every bundled article/category ID
and related link. Check all content and related navigation at narrow width with
double text size. Add optional local screenshot capture and SDK-font loading
for readable visual review without changing ordinary test requirements.

Record the 34 passing Help tests, clean focused static analysis, inspected
desktop/phone layouts, and live Windows preview route rendering/back-stack
checks. Update verification documentation to distinguish automated evidence
from remaining physical-device, browser, and screen-reader checks. Keep
production behavior, article content, dependencies, and preview bypasses unchanged.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/test/features/help/help_flow_test.dart` | Added | Adds four disconnected flow cases using production route definitions, the production telemetry router observer, real Settings/Help screens, test providers/preferences/platform channels, and a refused HTTP client. Covers Settings ordering and complete back navigation at desktop/phone sizes; keyword search and missing-content recovery; all eight articles, six categories, and every related link at narrow width/double text. Optional `HELP_CAPTURE_DIR` and `HELP_FONT_DIR` enable local PNG capture and SDK font loading. |
| `docs/help/verification-step-9.md` | Added | Records the verification plan, requirement-by-requirement results, commands, viewport sizes, Windows preview debug-service checks, artifact locations, and remaining device/browser/assistive-technology checks. Separates Help navigation from unverified server workflows. |
| `docs/help/content-verification.md` | Modified | Links the Step 9 report; updates the Opening Help and Reading Help verification rows with production-route tests, refused HTTP, all-content/related-link traversal, and Windows preview rendering evidence. Retains unresolved physical-device and server-workflow checks. |
| `frontend/lib/features/help/README.md` | Modified | Adds complete-flow verification instructions, focused test/analysis commands, and a link to the Step 9 results and capture instructions. Explains the limits of simulated connectivity and widget viewport checks. |
| `docs/commit-notes/help-center-step-9.md` | Added | These commit notes, exact file inventory, completed checks, remaining verification, and preview/restoration details. |

No app screen, router implementation, bundled article, localization source,
package manifest, backend file, native plugin, preview script, or ignore rule
was changed in Step 9. Existing mock/test dependencies were reused.

## Validation completed

Step 9 was verified October 3, 2026, on Windows with Flutter 3.41.9 and
Dart 3.11.5. These results were obtained during implementation; writing these
notes did not rerun the test suite.

From `frontend/`, using the installed SDK:

```powershell
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe format test/features/help/help_flow_test.dart
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

- All **34 Help tests passed**: nine repository tests, four article-screen
  tests, six home catalog tests, eleven home screen tests, and four new flow cases.
- Focused static analysis reported no issues. `git diff --check` passed.
- The new Settings flow passed at **1366 × 900** and **390 × 844**. Help is
  first under General, and back navigation returns through topic, home, and Settings.
- Every bundled category/article and related link passed at **320 × 568**
  with double text size and no widget exceptions.
- The HTTP client refused every attempted request, and connectivity reported
  `none`. Settings' notification request failed as expected; reading/browsing
  Help added no HTTP requests after initial Settings/provider setup. Telemetry
  was opted out in the test harness. Host networking was not changed.
- Existing keyboard, semantics, theme, enlarged-text, localization-fallback,
  ID-validation, link-validation, and local-search tests remained passing.
- All four new flow cases also passed with SDK fonts and optional captures
  enabled. Eight readable desktop/phone captures were inspected for Settings
  General, Help home, topic, and article. No Help overflow was observed. Long
  phone app-bar titles truncate; full article titles wrap in the scrollable body.
- The already-running Windows preview was inspected at its **648 × 998**
  surface in the app's dark theme. Debugger calls to existing router methods
  opened Settings, Help, Medications, and the dose guide, then returned through
  topic, home, and Settings. Engine screenshots confirmed the rendered screens.
  Help was left open; the debugger detached and the app remained running.

The full application test suite was not run. The detailed results and optional
capture command are in [the Step 9 report](../help/verification-step-9.md).

## Remaining verification and limits

Automated disconnected channels and refused HTTP establish local Help behavior
in the harness. They do not establish physically disconnected operation on a
real device. Widget phone sizes are layout checks, not mobile-device runs.
The Windows live check used debugger router invocation, not physical clicks or
keyboard navigation.

Outstanding checks are recorded explicitly:

- Physically disconnected Help reading/search/navigation on Windows preview
  and a supported mobile build.
- Physical desktop input, mobile touch/software keyboard, system back, and
  device text-size settings.
- Real screen-reader focus order, labels, result announcements, and article reading.
- Browser navigation, responsive rendering, and offline first-load/reload
  behavior, separately from reading an already-loaded catalog.

These tests do not establish successful dose persistence, appointment loading,
message delivery, password-reset email delivery, or web check-in submission.
The [content verification record](../help/content-verification.md) retains those
unverified instructions. The native check-in's mock submission explanation
remains unchanged.

## Temporary Windows preview and restoration

Step 9 added no OpenSSL requirement, native dependency, or new dependency bypass.
It did not alter `frontend/pubspec.yaml` or the preview launcher's restrictions
on offline saving/replay, text-to-speech, GPS, and native permission integrations.
Help reading remains separate from those integrations.

Local verification artifacts are under the already-ignored
`tmp/windows-online/help-verification/` directory:

- `desktop-*.png` and `phone-*.png`: test layout captures.
- `windows-live-*.png`: running preview engine captures.
- `live-probe.ps1`: temporary debug-service route/capture helper.

These files are local artifacts and must not be staged. The optional font path
uses `roboto-regular.ttf` and `materialicons-regular.otf` from the installed
Flutter SDK; no fonts or extra dependencies were added to the app. Ordinary
test runs require neither capture nor font arguments and write no screenshots.

Keep the Step 9 tests and documentation when retiring the preview. No dependency
restoration is required specifically for this step. The earlier bypass inventory
and restoration checklist remain in
[help-center-step-1.md](help-center-step-1.md).

No commit, push, dependency restoration, or preview cleanup was performed while
writing these notes.
