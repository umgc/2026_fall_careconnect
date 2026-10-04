# Plan: Help Center developer maintenance documentation

## Purpose and delivery

Create a developer-only maintenance handbook at `docs/help/maintenance.md`.
Keep it in the repository documentation. It will have no Help article entry,
glossary entry, app route, or user-facing navigation link.

Make the handbook the main place for add, edit, retire, restore, and delete
instructions. Link it from `frontend/lib/features/help/README.md` and the root
developer documentation index where appropriate. Keep the feature README as a
short architecture overview and quick start. Link to specialized glossary,
article-contents, and localization guides instead of copying their details.

This file is a documentation plan. The handbook and the proposed lifecycle
support below have not been implemented by writing this plan.

## Current implementation: facts the handbook must preserve

- Categories and articles are bundled Dart data in
  `frontend/lib/features/help/data/bundled_help_content.dart`.
- Article/category ID constants live in `data/help_content_ids.dart`.
  IDs are permanent URL slugs; renaming display text should keep them.
- Popular Help ordering lives separately in `data/help_home_config.dart`.
  Removing an ID there only removes that featured placement.
- Glossary labels, meanings, aliases, and optional explicit guide links live in
  `data/bundled_glossary_content.dart`. Glossary IDs currently live on entries,
  rather than in a separate glossary ID constants file.
- Article `glossaryTermIds` generate definitions and glossary backlinks. Section
  headings generate article contents links. Both should remain automatic.
- Articles, glossary definitions, and search are local to the built app. Content
  edits require a refreshed/rebuilt app and an app release to reach deployed
  users. There is no current Help CMS or remote publishing workflow.
- Home, topic listings, article search, and glossary guide backlinks currently
  use the Patient audience. Article roles are presentation metadata, not access
  control. Direct article routes do not enforce role restrictions.
- Glossary search/browsing currently includes every catalog term. Articles,
  categories, and terms have no publication-status field or runtime hide/delist
  configuration.
- Removing an article or term from the compiled catalog makes its existing
  direct link unavailable. References must be cleaned up first or repository
  validation fails. A category cannot be deleted while articles reference it.
- Glossary content counts and Popular Help order are asserted by tests. Intended
  catalog changes may require explicit updates to those expectations.

## Planned handbook structure

| Section | What a developer should be able to do |
| --- | --- |
| Quick task index | Find the recipe for a small change without reading the whole handbook. |
| File and ownership map | Identify the content/configuration file to edit and the shared renderer that owns behavior. |
| Catalog and reference map | Understand categories, articles, sections, featured IDs, glossary references, guide links, aliases, and stable routes. |
| Articles | Add, revise, rename, move to another topic, reorder sections, change audience, retire, restore, or delete a guide. |
| Topics/categories | Add, revise, reorder, move articles between topics, merge, retire, restore, or delete a topic. |
| Glossary | Add/edit meanings and aliases, attach/detach article references, merge terms, retire/restore/delete terms, and preserve old links. |
| Home placement and search | Change featured order, unfeature content, maintain keywords/aliases, and understand result ranking and listing order. |
| Article presentation and navigation | Maintain generated contents links, related articles, header shortcuts, focus targets, and Back to top. |
| Lifecycle and compatibility | Choose unfeature, delist, hide, delete, or replacement; understand each action's effect on discovery and direct links. |
| Localization and writing | Maintain ARB messages, English fallback, plain-language definitions, and future translated catalogs. |
| Validation and troubleshooting | Diagnose catalog failures, missing content, stale previews, unexpected search matches, and broken navigation. |
| Review, preview, and release | Run appropriate checks, review accessibility/offline behavior, refresh the app, and prepare commit notes. |

Use one consistent recipe format: goal, files to edit, ordered steps, short
example, affected references, expected result, required checks, and restoration
or rollback instructions. Mark every proposed API as future work until it ships.

## Recipes and examples to include

### Articles and sections

- Add an ID constant and a complete article with an existing/new category,
  nonempty roles and sections, summary, and relevant keywords.
- Add or revise paragraph, numbered-step, troubleshooting, and related-article
  sections. Supply useful headings; do not author a second contents menu.
- Add glossary IDs in reading order; do not copy shared definitions into prose.
- Rename a title while preserving its ID and existing bookmarks.
- Move an article to another category and check both topic lists and search.
- Feature, reorder, or unfeature a guide using Popular Help configuration.
- Change an audience and explain the current Patient-focused screen behavior.
- Split or merge guides while preserving or explicitly replacing old links.
- Remove an obsolete related link without deleting its target article.

Provide a complete copyable article example with a paragraph, steps,
troubleshooting, related links, and glossary references. Explain which outputs
are generated and which lists authors intentionally maintain.

### Glossary terms and aliases

- Add an entry with a unique ID/normalized label and a short definition.
- Add everyday questions, alternative names, and abbreviations; explain exact
  label priority, normalized duplicates, overlapping aliases, and negation.
- Edit one meaning and show how articles and search automatically use it.
- Add/remove a term reference on an article and explain generated backlinks.
- Add an explicit guide link only when automatic backlinks are insufficient.
- Rename a display label without changing its ID.
- Merge duplicate concepts using a surviving ID and a compatibility decision
  for the retired ID. Do not merge genuinely different concepts for convenience.
- Remove an alias, remove a term from one article, delist a term, hide a term,
  and delete a term as separate operations.

### Other Help elements

- Add/edit/reorder topics; explain that list ordering comes from the catalog.
- Change localized labels, placeholder-bearing messages, and result counts.
- Maintain the shared header and floating controls in their common components.
- Explain the current Back to top threshold and reduced-motion behavior.
- Show how to preview content locally and when hot reload, hot restart,
  localization generation, or a rebuild is needed. Verify commands against the
  project's actual launch workflow before publishing the handbook.
- Explain why editing repository Markdown does not update an in-app article.

## Lifecycle terminology and proposed policy

Document **current support** separately from the intended lifecycle design.
The existing models do not yet provide delist/hide switches. Do not suggest
changing roles, emptying required content, or commenting out referenced records
as a substitute for a supported lifecycle operation.

| Operation | Intended meaning | Discovery | Known/explicit links | Current support |
| --- | --- | --- | --- | --- |
| Unfeature | Remove an article's Popular Help placement. | Other discovery remains. | Continue working. | Remove its ID from `patientPopularHelpArticleIds`. |
| Delist | Keep content usable through a known link or intentional reference, but remove automatic promotion/discovery. | Omit applicable home/topic/search/glossary-directory results and automatic backlinks. | Remain readable; explicit related links and article term references can remain. | Requires lifecycle implementation. |
| Hide | Retain an entry for restoration while making it unavailable through the app's public Help surfaces. | Omit all applicable discovery. | Show recovery or an approved replacement; suppress hidden definitions and links. | Requires lifecycle implementation. |
| Delete | Remove the content record permanently from the active catalog after reference and compatibility review. | Entry no longer exists. | Missing-content recovery unless a redirect or retirement record is deliberately retained. | Catalog removal works after cleaning dependencies; redirects/retirement records require additional support. |

The delist definition above is deliberately compatible with explicit article
references. It is a discovery decision, not confidentiality. Hidden content can
also remain in a compiled app bundle; neither status should be described as
protection for sensitive material.

### Lifecycle implementation prerequisite

If hide/delist recipes should be executable, implement the following in a
separate, explicitly scoped app change before documenting those recipes as
available:

- Add a shared publication state such as published/delisted/hidden, defaulting
  to published for compatibility. Apply it to articles, categories, and terms.
- Centralize effective visibility in the repository. Category state should
  constrain its articles: a hidden topic hides its articles, and a delisted
  topic delists its articles. Restoring a topic should preserve each article's
  own state instead of automatically publishing every child.
- Keep validation/indexing separate from public visibility: retained hidden
  records remain structurally valid, while screens use visibility-aware
  resolution. Hidden references may remain for restoration but must not render
  a hidden definition or reader-facing link.
- Apply state consistently to featured entries, topics, article and glossary
  search, glossary browsing, generated backlinks, explicit links, generated
  definition sections, contents targets, and direct-route resolution.
- Keep featured configuration intact when temporarily hiding content, with
  visibility taking precedence at display time. This supports restoration
  without losing editorial position.
- For hidden definitions, generate no empty Words in this article section or
  orphaned contents entry. For unavailable routes, use clear existing recovery
  behavior or an explicitly approved replacement.
- Consider redirects or retirement records when replacing a published ID.
  Reject redirect cycles, invalid destinations, and visibility bypasses.

This is a proposed design, not an instruction to change the app during this
documentation-planning task. Until such support ships, the handbook should
describe only current operations as executable and label the rest clearly.

## Safe removal and replacement procedures

Every deletion recipe should begin with an impact search and end with validation.
Include copyable `rg` examples scoped to the relevant content ID and files.

| Target | Dependencies to inspect |
| --- | --- |
| Article | ID constants, featured configuration, other articles' related sections, glossary explicit guide IDs, external/bookmarked routes, tests, and developer instructions. |
| Glossary term | Article `glossaryTermIds`, authored `HelpGlossaryTerms` sections if present, selected-term routes, aliases worth moving to a replacement, tests, and documentation. |
| Category | Every article's `categoryId`, category constants, topic bookmarks, configured order, tests, and documentation. Move or retire its articles before removal. |
| Section or heading | Generated menu order/targets, internal navigation tests, related links or glossary references within the removed section. |
| Alias or keyword | Expected search matches and readers' existing everyday phrasing. Consider preserving useful variants on a replacement. |

Reserve previously published IDs instead of reusing them for another meaning.
Explain when a replacement should keep an existing ID and when it needs a new
ID with an explicit old-link decision. Record retirement/replacement decisions
in the PR and an appropriate maintainer record. Git history can recover deleted
text, but it does not keep old application links working.

## Validation and review guidance

Document these commands from `frontend/`, using portable SDK names in the
handbook rather than a particular developer's Windows SDK location:

```powershell
flutter gen-l10n
dart format lib/features/help test/features/help
dart analyze lib/features/help test/features/help test/test_support/help_test_catalog.dart
flutter test test/features/help --no-pub
```

Explain when localization generation applies, how to interpret catalog
validation errors, and how intentional term-count/featured-order changes affect
tests. Do not weaken validation just to make a deletion pass.

The review checklist should cover relevant links and direct routes, search
phrases, generated definitions/contents/backlinks, Back history, header shortcuts,
Back to top, light/dark layouts, enlarged text, keyboard focus, semantics,
offline reading, and localization fallback. Distinguish automated evidence from
real-device and screen-reader review. Avoid copying a permanently fixed passing
test count into the ongoing authoring instructions.

If lifecycle support ships, add a visibility matrix test covering every state
and surface, parent-category effects, explicit versus generated links, restoration,
and redirects. Include fixtures containing a mixture of published, delisted,
and hidden records.

## Documentation consolidation and acceptance criteria

1. Draft the handbook around the current implementation and a clearly marked
   lifecycle support gap.
2. Review it against repository methods, all four Help screen types, fixtures,
   routing, and localization generation.
3. Update the feature README's outdated article-only search description and
   file map. Link to the handbook and specialized guides with working paths.
4. Keep glossary/article/localization documents focused on their specialty.
   Preserve historical commit notes as records of their own changes.
5. Verify snippets through appropriate existing tests or temporary fixtures,
   without adding demonstration entries to the shipped app catalog.
6. Check Markdown links, file references, terminology, and publication-state
   claims. Confirm no developer instructions were added to the app catalog,
   packaged user content, or app navigation.

The finished documentation should let a developer unfamiliar with the feature
complete ordinary content maintenance without tracing Flutter screen code.
They should also be able to predict what happens to search, generated sections,
incoming links, and restoration before removing or retiring an entry.
