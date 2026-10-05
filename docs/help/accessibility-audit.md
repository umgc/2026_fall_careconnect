# Help Center accessibility review

Reviewed October 4, 2026, against [WCAG 2.1 AA](https://www.w3.org/TR/WCAG21/).
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
   nonlinear scaling, and reacts to route changes. Other routes retain their
   existing scaling policy.
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
   titles. Article sections, troubleshooting problems, glossary terms, and related
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
| 1.4.4, 1.4.10 | All routes preserve 200% text at 320 logical pixels and reflow vertically. Body titles wrap. Actual browser 400% zoom remains a manual check. |
| 1.4.5 | Help text is rendered as text, rather than embedded in images. |
| 1.4.12 | Stress-tested 1.5 line height, 0.12em letter spacing and 0.16em word spacing, including long article content and glossary links. Actual browser spacing/paragraph override behavior remains a manual check. |
| 1.4.13 | Help uses standard Material tooltips on icon controls. Live hover/focus tooltip persistence and Escape dismissal remain manual checks. |
| 2.1.1, 2.1.2, 2.1.4 | Existing Tab/Shift-Tab, Enter/Space, contents jumps, search and navigation tests pass; no custom character-only shortcuts or keyboard traps were introduced. |
| 2.2.1, 2.2.2, 2.3.1 | Help has no timed task, auto-playing content, or flashing content. User-triggered scroll animations respect reduced motion. |
| 2.4.1 | Level-one body headings provide a structural way to bypass the repeated header with assistive heading navigation. Confirm that navigation on each supported screen reader. |
| 2.4.2 | Every Help route exposes a descriptive `Title` and complete body heading, including missing content. |
| 2.4.3, 2.4.6, 2.4.7 | Reading-order traversal, explicit heading targets and visible focus borders. Search clearing and Back to top retain meaningful focus. |
| 2.4.4, 2.4.5 | Descriptive tile labels/hints; articles can be reached through topics, local search, popular guides and related links. |
| 2.5.1–2.5.4 | Standard tap/release controls, visible words included in accessible names, no motion-only or multipoint gestures. |
| 3.1.1, 3.1.2 | Current English content/fallback language and localized Back tooltip language are explicitly tagged. |
| 3.2.1–3.2.4 | Focus does not navigate. Search updates results without changing page; navigation requires activation. Shared header/control identification is consistent. |
| 3.3.1–3.3.4 | Help does not submit consequential forms. Empty search and unavailable content provide explanations and working recovery actions. |
| 4.1.1, 4.1.2, 4.1.3 | Widget/semantics checks cover names, button roles, selected/expanded/focused states and live counts. Browser-generated accessibility/DOM behavior remains a platform check. |

## Validation

- **70 Help tests pass**, including ten new accessibility cases and an optional
  visual-capture case. Static analysis of Help, its tests, and the new application
  scaling wrapper reports no issues. `git diff --check` passes.
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

From `frontend/`:

```powershell
flutter test --no-pub test/features/help
flutter analyze --no-pub lib/features/help lib/config/theme/app_text_scaling.dart test/features/help
```

For visual artifacts, set `HELP_CAPTURE_DIR` to a writable absolute output
directory and `HELP_FONT_DIR` to the Flutter SDK's
`bin/cache/artifacts/material_fonts`, then run `help_flow_test.dart` with
`--plain-name "all Help surfaces"`. Font loading includes regular, medium and bold
Roboto. Captures are developer artifacts, not app assets.

## Platform verification still required

Use supported live builds with NVDA/browser, VoiceOver and TalkBack to verify
actual spoken names, route announcements, heading navigation, selected and
expanded states, live search counts and focus after navigation. Verify 200%
device text settings, browser 400% zoom, browser text/paragraph spacing overrides,
tooltip dismissal/persistence, pointer/touch targets and focused/hovered contrast.
The automated evidence cannot substitute for those platform observations.
