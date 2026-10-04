# Help Center feature

Help is available from Settings > General > Help at `/help`. Topics and articles
use permanent IDs in their routes; selected glossary words use a `term` query
parameter. The catalog is bundled Dart data and requires no network request to
read or search after the app is loaded.

For add, edit, remove, restore, preview, and verification instructions, use the
[developer maintenance handbook](../../../../docs/help/maintenance.md).
That handbook and the linked repository documentation are outside in-app Help.

## Structure

```text
help/
  models/                       Articles, categories, glossary terms, roles, sections
  data/
    help_content_ids.dart        Permanent article/category IDs
    help_home_config.dart        Patient Popular Help selection/order
    bundled_help_content.dart    Category/article content and references
    bundled_glossary_content.dart Shared meanings and search aliases
    help_repository.dart         Validated local catalog and generated relationships
    help_search.dart             Shared search normalization
  help_routes.dart               Stable route patterns/builders
  presentation/
    pages/                       Home, topic, article, glossary screens
    widgets/                     Shared content, entry tiles, and header controls
```

## Behavior and content ownership

Home is Patient-focused, with Search Help, a Glossary entry, Popular Help, and
Browse Topics. Featured selection/order is explicit configuration. Topic and
article listings are generated from catalog data and audience metadata.
Roles describe audiences rather than authorizing direct article access.

Home search shows article and word results separately, with both counts in its
live announcement. Article search includes relevant glossary labels/aliases;
glossary search also includes meanings and ranks exact labels/aliases first.
The shared normalizer handles punctuation and question filler while retaining
meaningful negatives.

Article headings generate On this page links. Article `glossaryTermIds` generate
Words in this article from shared meanings, and also generate glossary guide
backlinks. Do not copy definitions or maintain duplicate contents/backlink lists.
Related-link labels use current target titles. Keep permanent IDs when renaming
or translating content.

The shared Help header provides Home and Settings shortcuts. Ordinary Back
retains navigation history, while those shortcuts leave the accumulated Help
stack. Long article/glossary screens provide Back to top and respect disabled
animations. Shared app typography, localized controls, focus targets, and
semantics are part of the reusable presentation.

Content is currently English; interface labels use the app localization system
and its English fallback for untranslated messages. Activities described in
guides may require connectivity or device integrations. On web, loading the app
itself can need a connection. See the verification record before changing
platform-specific workflow claims.

## Quick start for content edits

1. Find the entry in the relevant bundled content file; preserve its ID.
2. Change text or references, or add a complete entry with resolvable targets.
3. Adjust explicit featured selection if appropriate.
4. Update focused tests for intentional catalog/order changes and verify the
   workflow described by the content.
5. Hot restart the normal app, or stop/relaunch the isolated Windows preview.

From `frontend/`:

```powershell
dart format lib/features/help test/features/help
dart analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
flutter test test/features/help --no-pub
```

Run `flutter gen-l10n` after ARB changes. The repository validates catalog IDs,
references, required content, headings, and glossary labels. Models make
defensive immutable copies. All screens accept an injected repository for
tests/previews and otherwise use the bundled catalog.

## Further developer documentation

- [Maintenance handbook](../../../../docs/help/maintenance.md)
- [Glossary](../../../../docs/help/glossary.md)
- [Article contents](../../../../docs/help/article-contents.md)
- [Localization](../../../../docs/help/localization.md)
- [Content verification](../../../../docs/help/content-verification.md)
- [Production-flow verification](../../../../docs/help/verification-step-9.md)

The test suite includes production routes with refused HTTP, catalog integrity,
keyboard/semantics checks, and narrow/enlarged layouts. Its evidence is distinct
from physical-device, actual screen-reader, or successful backend-workflow checks.
