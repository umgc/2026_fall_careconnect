# Commit notes: Help Center developer maintenance documentation

## Suggested commit title

Document Help Center content maintenance and consolidate developer guidance

## Suggested commit body

Add a repository-only Help Center maintenance handbook covering articles,
topics, glossary terms, aliases, keywords, featured ordering, sections, links,
localization, and shared navigation controls. Include copyable authoring
examples, permanent-ID rules, dependency searches before deletion, replacement
and restoration procedures, preview refresh instructions, validation commands,
and troubleshooting.

Make the feature README a concise architecture overview and quick start linked
to the handbook. Add a handbook link to the frontend README and cross-links
from the glossary, article contents, and localization guides. Update the
localization guide for glossary content, word counts, combined announcements,
term placeholders, and future translated catalogs.

Verify 57 local Markdown links and referenced anchors. Extract the three
complete Dart examples and validate them against the real Help repository in
an isolated fixture. Check catalog construction, search, generated definitions,
guide backlinks, empty-category behavior, and featured selection. This change
updates documentation only; no in-app content or runtime behavior changes.

## Purpose and audience

Future developers need to maintain Help without rediscovering how its content,
configuration, screens, and generated relationships fit together. The handbook
identifies the source to edit for each task and explains the effect on listings,
search, references, direct routes, and previews.

The handbook lives at [docs/help/maintenance.md](../help/maintenance.md). It is
repository documentation, with no entry in the app's article or glossary
catalog and no app route or navigation item. Example content is illustrative
and remains in Markdown; it was not added to the shipped catalog.

## Handbook coverage

### Authoring and content ownership

- A quick task index links directly to the relevant maintenance procedure.
- A file map identifies bundled article/category data, permanent ID constants,
  featured configuration, glossary data, repository logic, query normalization,
  models, route builders, shared presentation, localization, and tests.
- Article instructions cover adding a complete entry, editing text, renaming
  while retaining its ID, moving between categories, audience metadata, and
  the effect of catalog order on topic/search listings.
- Section guidance covers paragraphs, automatically numbered steps,
  troubleshooting pairs, related-article IDs, headings, and generated glossary
  sections. It explains contents-menu generation and repeated heading support.
- Category instructions cover creation, title/description changes, ordering,
  moving articles, combining topics, and empty-category behavior.
- Popular Help instructions distinguish the explicit featured list from the
  article catalog and explain addition, removal, ordering, and audience checks.
- Glossary instructions cover unique labels/IDs, shared meanings, aliases,
  article references, optional explicit guide links, and generated backlinks.
- Search guidance explains article keywords, term aliases, definition search,
  ranking, normalization, question filler, meaningful negatives, and ordering.

### References, removal, and restoration

- Permanent IDs remain stable across ordinary wording or title changes.
  Previously published IDs should not be reused for unrelated content.
- Reference searches include both constants and literal IDs, because different
  consumers use different forms. Examples use `rg` from the repository root.
- Dependency tables identify featured IDs, related sections, glossary references,
  category references, direct links, and tests affected by a removal.
- Separate article, term, and category deletion procedures clean up incoming
  references before removing records, preserving repository validation.
- Replacement/splitting guidance explains surviving IDs, useful aliases,
  relevant replacement links, and existing old-link recovery behavior.
- Restoration uses focused Git history inspection to recover records and
  intended references while preserving unrelated newer catalog edits.

### Shared behavior, localization, and verification

- Shared presentation guidance identifies the renderer, heading resolver,
  entry tiles, header layout, shortcut actions, and scroll-control owners.
- Navigation documentation explains ordinary pushes, header shortcuts,
  retained Back history, selected-word focus, generated contents targets,
  reduced motion, and the current Back to top threshold.
- Localization distinguishes ARB interface labels from authored English
  catalog text. It documents placeholders, plural counts, generation, fallback,
  and preserving IDs across future translated content.
- Preview instructions distinguish normal Flutter hot reload/restart from the
  isolated Windows preview's copied frontend. Developers must stop/relaunch
  that preview to copy production-source changes again.
- Validation guidance maps test files to responsibilities and explains
  intentional count/order assertion changes, workflow verification records,
  accessibility/offline review, and appropriate PR/commit notes.
- Troubleshooting covers missing entries, unresolved references, stale previews,
  aliases, multiple search matches, localization, and deleted routes.

## Documentation consolidation

`frontend/lib/features/help/README.md` now provides a shorter current overview
with the full Help file map, combined article/word search, generated definitions
and backlinks, navigation behavior, content ownership, quick-start checks,
and links to the handbook and specialized references.

Detailed maintenance recipes now belong in the handbook. The article contents
and glossary guides retain their implementation-specific information and link
to the relevant handbook sections. The general frontend README provides a
discoverable link for developers approaching the feature from project setup.

The localization guide also reflects the implemented glossary:

- Glossary labels, definitions, and aliases are part of the authored English
  catalog rather than ARB interface strings.
- Both article and word count messages require correct plural handling.
- Combined announcements preserve `articles` and `words` placeholders; the
  glossary action preserves its `term` placeholder.
- Future translated catalogs must preserve glossary IDs, article references,
  explicit guide IDs, and article/category/glossary ID sets.
- Query filler handling is currently English and needs deliberate language-aware
  support alongside translated reader vocabulary.

## File inventory for this documentation change

| File | Status | Change |
| --- | --- | --- |
| `docs/help/maintenance.md` | Added | Main developer handbook with authoring examples, edit/remove/restore procedures, reference checks, search/navigation/localization guidance, preview refresh, validation, and troubleshooting. |
| `frontend/lib/features/help/README.md` | Modified | Consolidates the feature overview and quick start; updates the structure/search description and links to the handbook. |
| `frontend/README.md` | Modified | Adds the Help maintenance handbook to developer documentation links. |
| `docs/help/article-contents.md` | Modified | Links to the handbook's section-maintenance instructions. |
| `docs/help/glossary.md` | Modified | Links to glossary maintenance, reference cleanup, restoration, and preview procedures. |
| `docs/help/localization.md` | Modified | Links to the handbook and includes glossary-specific translation/content guidance. |
| `docs/commit-notes/help-center-maintenance-documentation.md` | Added | These commit notes and verification record. |

Use this inventory when staging the handbook and its related documentation
updates. Temporary example-verification files are local QA artifacts.

## Validation completed

Verified **October 4, 2026** during handbook implementation:

- **57 local Markdown links and referenced anchors passed** across the handbook,
  feature/frontend READMEs, and linked glossary/article/localization guides.
- The handbook's complete article, category, and glossary examples were
  extracted into an isolated Dart fixture and run against the real Help models
  and bundled repository.
- The fixture passed catalog construction and article lookup; keyword search;
  generated article definition references; glossary alias ranking; explicit
  guide backlinks; an empty category; and Patient featured selection.
- Example records existed only in the fixture. Production catalogs, models,
  routes, UI, and dependencies were unchanged.
- Markdown whitespace checks and `git diff --check` passed.

The example check ran from the repository root using the installed Dart SDK:

```powershell
dart --suppress-analytics run tmp/windows-online/help-verification/maintenance-examples.dart
```

The fixture is an ignored local artifact, not a committed test or application
entry point. The handbook lists the normal Help checks developers should run
when changing actual content or presentation.

The Help/application test suites and analyzer were not rerun for this
documentation-only update. No new live-app, backend-workflow, physical-device,
or screen-reader verification was performed. These notes report documentation
and example checks rather than a new application verification run.

Writing these commit notes did not create a Git commit or push changes.
