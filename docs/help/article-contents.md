# Article contents menus

The [developer maintenance handbook](maintenance.md#sections-and-article-contents)
covers section edits and their effects on generated navigation.

Help articles with at least two named sections show an expanded **On this page**
menu beneath the title and summary. The toggle collapses only the menu links;
the article remains visible. Selecting a link scrolls its heading beneath the
fixed Help header and gives that heading keyboard focus. Reduced-motion
settings disable the scroll animation. Back to top continues to use the same
article scroll view.

## Authoring and maintenance

- Add a concise `heading` to paragraphs and step groups readers may want to
  reach directly. Unnamed sections remain readable but do not get menu entries.
- Troubleshooting, related-article, and generated glossary sections receive localized
  default headings. An authored heading overrides that default.
- Do not maintain a separate contents list. `helpSectionHeading` supplies both
  the menu label and the visible section heading.
- Heading names may repeat: each section has its own scroll anchor and focus
  node. Changing a heading does not change the article's permanent route ID.
- Empty or whitespace-only authored headings are rejected by `HelpRepository`.
- Menu labels use app localization; authored content follows the existing
  English bundled-catalog convention.

## Verification

The focused widget tests cover menu order and collapse/expand semantics,
individual targets including repeated names, Tab/Enter activation, destination
heading semantics and focus, reduced-motion jumps, Back to top, omission for a
single named section, and light/dark layouts at 320 x 568 with doubled text.
The production-route flow also traverses every bundled article's menu while
HTTP is refused and text is enlarged.

From `frontend/`:

```powershell
& C:/Users/SQ/flutter/bin/flutter.bat test test/features/help --no-pub
& C:/Users/SQ/flutter/bin/cache/dart-sdk/bin/dart.exe --suppress-analytics analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
```

Widget semantics checks do not replace a physical screen-reader review. Check
heading announcements, focus transitions, and touch/keyboard use in supported
builds. Enlarged-text tests set scaling directly in the harness; the existing
app-wide scaling clamp remains outside this feature.
