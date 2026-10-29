# Help Center accessibility review

Reviewed October 4, 2026, against [WCAG 2.1 AA](https://www.w3.org/TR/WCAG21/).
Updated October 5, 2026, for the [PR #259 testing review](https://github.com/umgc/2026_fall_careconnect/pull/259#issuecomment-5996054850),
commit `9aa9932d` and the applied DEF-HELP-02 suggested patch.
Scope: Help home, search, all six topics and eight articles, the 75-word glossary,
article contents, related links, persistent navigation, and missing-content states.

This is a source, semantics, automated-layout, and rendered-layout review. It is
not a certification or evidence of actual NVDA, VoiceOver, or TalkBack speech.

## Issues fixed

1. Extended the readable glossary theme to all Help pages. Light-mode cyan text
   previously had 2.85:1 contrast on white. Help now uses darker cyan in light
   mode and lighter cyan in dark mode, with explicit control outlines.
2. Removed the application's 120% text-scaling cap for Help routes. The route-aware
   application wrapper preserves the original platform `TextScaler`, including
   nonlinear scaling. DEF-HELP-01 exposed a Back-specific regression: at 200%
   text, Settings retained Help's 32px per 16px instead of returning to its
   19.2px cap. `AppTextScaling` now listens to `router.routerDelegate` and reads
   the top-most route from `router.state`, covering push, pop and go. Route
   notifications during a Router build defer the rebuild to the next frame.
   TC-HELP-060/061/062 cover app-bar Back, Back through article/topic/home and
   system Back; TC-HELP-063 checks full Help scaling when the keyboard opens.
   Other routes retain their existing scaling policy.
3. Standardized body text and control labels at a 16px base, stronger heading
   weights, and 1.5 line height for body text. Floating search labels remain
   visibly 16px after Material's 75% transform. Always-floating labels avoid
   truncation with increased letter/word spacing.
4. Added explicit 48px button and icon-button targets and minimum 48px list tiles.
   Help opts out of compact platform density. Target size is a usability choice:
   WCAG 2.1's 44px target-size criterion is AAA, not AA. WCAG does not prescribe a
   universal minimum font size.
5. Added 3px keyboard-focus borders to tiles and controls. Enlarged navigation
   wraps; when the viewport is too short, the header shortcuts scroll vertically
   while preserving space for the body.
6. Added full, wrapping level-one headings and descriptive application/browser
   titles. DEF-HELP-02 exposed stale titles after Back and an underlying Help
   home title overwriting a directly linked article's title. `HelpPageTitle`
   replaces Material's `Title` within `HelpAccessibility`, reports only while
   its route is current, and reports again when Back makes it current.
   `AppTextScaling` restores the application's own title when leaving Help.
   TC-HELP-066 covers Back within Help, exit to Settings and direct-link titles.
   Article sections, troubleshooting problems, glossary terms, and related
   article groups have heading levels. The compact toolbar can truncate visually;
   the full title remains in the body and route semantics.
7. Added distinct navigation hints for articles, topics, glossary words, and the
   glossary entry. Each tile exposes its visible title and summary as one button
   label; chevrons do not create extra announcements. Search result counts remain
   live regions, and the contents toggle exposes expanded/collapsed state.
8. Moved glossary deep-link focus onto the named selected heading, rather than an
   unnamed card container. Clearing a search restores field focus; Back to top
   restores title focus. Existing contents jumps focus their own headings.
9. Tagged current English Help content and untranslated Help labels with English
   semantics and reading direction. The system Back control retains the app
   locale for its translated tooltip. Revisit the Help language scope when Help
   translations are added.

## Measured contrast

Ratios below use foreground/background relative luminance, without rounding for
test decisions. The regression tests use a conservative 4.5:1 threshold for all
text, including headings, and 3:1 for control/focus boundaries.

| Element | Light mode, white surface | Dark mode, `#131B2B` surface |
| --- | ---: | ---: |
| Main text | 17.85:1 (`#0F172A`) | 13.91:1 (`#E5E7EB`) |
| Links and accent controls | 6.49:1 (`#00677D`) | 9.86:1 (`#5AD4E8`) |
| Search/navigation outlines | 4.76:1 (`#64748B`) | 6.78:1 (`#9CA3AF`) |

Tests also inspect effective paragraph styles, input labels, action labels, and
the tinted glossary article panel against their painted ancestor backgrounds.
Input fills and focus/hover overlays still need confirmation on live platforms;
the chosen palette has margin above the required text threshold.

## WCAG coverage and evidence

| Criteria | Review result and evidence |
| --- | --- |
| 1.1.1 | Text controls have labels; decorative chevrons are excluded. Help has no informative images requiring alternative text. |
| 1.2.1–1.2.5, 1.4.2 | Not applicable: Help contains no recorded/live media or audio playback. |
| 1.3.1, 1.3.2, 1.3.3 | Heading hierarchy, ordered step text, topic/article/word relationships, and reading order are exposed programmatically. Instructions use words rather than only color or position. |
| 1.3.4 | Phone and landscape layouts tested without a Help orientation restriction. |
| 1.3.5 | Not applicable to the Help search fields, which do not collect personal information. |
| 1.4.1, 1.4.3, 1.4.11 | Text/outline contrast checked in both themes. Selection also has a border and semantic state; article groups also have words and outlines. |
| 1.4.4, 1.4.10 | Help routes preserve 200% text at 320 logical pixels and reflow vertically. Body titles wrap. Other screens retain their inherited 120% cap. Actual browser 400% zoom remains a manual check. |
| 1.4.5 | Help text is rendered as text, rather than embedded in images. |
| 1.4.12 | Stress-tested 1.5 line height, 0.12em letter spacing and 0.16em word spacing, including long article content and glossary links. Actual browser spacing/paragraph override behavior remains a manual check. |
| 1.4.13 | Help uses standard Material tooltips on icon controls. Live hover/focus tooltip persistence and Escape dismissal remain manual checks. |
| 2.1.1, 2.1.2, 2.1.4 | Existing Tab/Shift-Tab, Enter/Space, contents jumps, search and navigation tests pass; no custom character-only shortcuts or keyboard traps were introduced. |
| 2.2.1, 2.2.2, 2.3.1 | Help has no timed task, auto-playing content, or flashing content. User-triggered scroll animations respect reduced motion. |
| 2.4.1 | Level-one body headings provide a structural way to bypass the repeated header with assistive heading navigation. Confirm that navigation on each supported screen reader. |
| 2.4.2 | Every Help route exposes a descriptive `HelpPageTitle` and complete body heading, including missing content. Only the current route reports its window title; Back restores the visible Help page's title, and leaving Help restores the application title. TC-HELP-001 checks title labels; TC-HELP-066 checks platform-channel title reports across Back and direct links. Live browser evidence is attributed below; a local live rerun remains outstanding. |
| 2.4.3, 2.4.6, 2.4.7 | Reading-order traversal, explicit heading targets and visible focus borders. Search clearing and Back to top retain meaningful focus. |
| 2.4.4, 2.4.5 | Descriptive tile labels/hints; articles can be reached through topics, local search, popular guides and related links. |
| 2.5.1–2.5.4 | Standard tap/release controls, visible words included in accessible names, no motion-only or multipoint gestures. |
| 3.1.1, 3.1.2 | Current English content/fallback language and localized Back tooltip language are explicitly tagged. |
| 3.2.1–3.2.4 | Focus does not navigate. Search updates results without changing page; navigation requires activation. Shared header/control identification is consistent. |
| 3.3.1–3.3.4 | Help does not submit consequential forms. Empty search and unavailable content provide explanations and working recovery actions. |
| 4.1.1, 4.1.2, 4.1.3 | Widget/semantics checks cover names, button roles, selected/expanded/focused states and live counts. Browser-generated accessibility/DOM behavior remains a platform check. |

## Validation

Independent execution reported by **Kristopher Bickmore on October 5, 2026**,
using Flutter 3.44.9 / Dart 3.12.2, in the linked PR review. The scope was
`test/features/help/` plus `test/pages/settings_page_test.dart`:

| Reviewed code state | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: |
| Reviewer's DEF-HELP-01 fix and test changes, committed as `9aa9932d` | 165 | 0 | 1 |
| Those changes plus the DEF-HELP-02 suggested patch | 166 | 0 | 1 |

These are the reviewer's results, not a new local or PR-author rerun. The
PR-author rerun of `help_flow_test.dart` requested to close DEF-HELP-01 remains
unrecorded here; record its date, SDK version and results when available.

The earlier "70 Help tests passed" total included the optional capture case,
which returned early without assertions when `HELP_CAPTURE_DIR` was unset.
TC-HELP-035 now explicitly reports **skipped** in that configuration. The
reviewer separately executed it with capture/font paths and reported **24
renders with no exceptions**. Normal runs with one skipped case do not establish
that captures were generated or inspected.

- The reviewer reported live web reflow at 640 and 320 CSS pixels without
  horizontal scroll (TC-HELP-067), and correct Back/direct-link titles with the
  suggested patch (TC-HELP-068). Repeat the live title check on the applied
  local patch; these observations are distinct from widget-test evidence.
- All bundled topics/articles plus missing topic/article/word states are checked
  in light/dark themes at 390×844, 320×568 with 200% text, and 844×390 with 200%
  text. The selected glossary includes related article cards.
- Tests cover effective text contrast, labeled 48×48 tap targets, heading levels,
  descriptive route titles, preserved scaling, English fallback semantics, focus
  borders, live search results, selected word focus and focus restoration.
- Increased-spacing checks exercise the Help home, every article, and the
  selected glossary at 320px, without clipped body text.
- 24 readable captures cover home, topic, article and selected glossary in both
  themes and all three layouts. They are generated in the ignored
  `frontend/build/help-wcag-audit/` directory using SDK Roboto/Material Icons.

Run from `frontend/`, where `pubspec.yaml` is located. From the repository root,
first run `Set-Location .\frontend`:

```powershell
flutter test --no-pub test/features/help/help_flow_test.dart
flutter test --no-pub test/features/help test/pages/settings_page_test.dart
flutter analyze --no-pub lib/features/help lib/config/theme/app_text_scaling.dart test/features/help test/pages/settings_page_test.dart
```

For visual artifacts, supply `--dart-define=HELP_CAPTURE_DIR=<absolute-output-directory>`
and `--dart-define=HELP_FONT_DIR=<font-directory>`; the font directory is the Flutter SDK's
`bin/cache/artifacts/material_fonts`, then run `help_flow_test.dart` with
`--plain-name "all Help surfaces"`. Font loading includes regular, medium and bold
Roboto. Captures are developer artifacts, not app assets.

## Platform verification still required

**TalkBack (TC-HELP-069) and VoiceOver (TC-HELP-070) walkthroughs remain
outstanding and require a tester other than the PR author. No VPAT row should
cite Help until those checks are completed.** Semantics tests do not establish
actual spoken output or formal WCAG conformance.

Use supported live builds with NVDA/browser, VoiceOver and TalkBack to verify
actual spoken names, route announcements, heading navigation, selected and
expanded states, live search counts and focus after navigation. Verify 200%
device text settings, browser 400% zoom, browser text/paragraph spacing overrides,
tooltip dismissal/persistence, pointer/touch targets and focused/hovered contrast.
The automated evidence cannot substitute for those platform observations.
Platform text size on a physical device, the browser's own zoom control and
the full frontend suite were not executed in the independent review. Its live
web reflow used viewport sizing, not the browser zoom control.
