# Commit notes: Help Center feature structure

## Suggested commit title

Add an offline Help catalog with stable IDs and reusable article presentation

## Suggested commit body

Organize Help under `frontend/lib/features/help/`, separating article/category
models, bundled content, catalog access, reusable widgets, and screens.

Introduce permanent article and category IDs independent of display titles.
Validate duplicate IDs, URL slug format, and category references when building
the catalog. Expose immutable collections and lookups for future Help screens.

Bundle a Getting Started category and an Opening Help guide as Dart constants.
Update the existing Help Center screen to render the guide through a reusable
article widget, with a scrollable layout and a maximum content width of 720.
Allow catalog injection for previews and tests while defaulting to bundled
content. Reading this content requires no backend connection, database,
additional native plugin, or new package dependency.

Document the feature structure, content extension process, stable-ID rules,
and current localization scope. Add six catalog tests covering lookup integrity,
title changes, invalid references, and immutability.

## Exact file inventory

| File | Status | Change |
| --- | --- | --- |
| `frontend/lib/features/help/models/help_article.dart` | Added | Immutable article model with `id`, `categoryId`, `title`, `summary`, and `body`. Contains no Flutter or backend imports. |
| `frontend/lib/features/help/models/help_category.dart` | Added | Immutable category model with `id`, `title`, and `description`. Contains no Flutter or backend imports. |
| `frontend/lib/features/help/data/help_content_ids.dart` | Added | Defines permanent identifiers: category `getting-started` and article `opening-help`. Display titles and translations can change without changing these values. |
| `frontend/lib/features/help/data/bundled_help_content.dart` | Added | Bundles the Getting Started category and Opening Help article directly in the app. The guide describes Settings > General > Help and returning with the back button. |
| `frontend/lib/features/help/data/help_repository.dart` | Added | Local catalog with `bundled()`, `findCategory`, `findArticle`, and `articlesForCategory`. Rejects duplicate IDs, invalid lowercase URL slugs, and articles referencing missing categories. Copies input collections into unmodifiable lists; missing ID lookups return null. |
| `frontend/lib/features/help/presentation/widgets/help_article_content.dart` | Added | Reusable themed widget that renders an article's title, summary, and body. Content loading and navigation remain outside the widget. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | Modified | Accepts an optional repository, defaults to the bundled catalog, looks up the introduction by stable ID, and renders it above the existing placeholder. Uses SafeArea, scrolling, and a 720-wide content constraint. Retains the localized AppBar and existing back navigation. |
| `frontend/lib/features/help/README.md` | Added | Developer instructions for the directory structure, adding content, preserving IDs, validating the catalog, and future localization. |
| `frontend/test/features/help/help_repository_test.dart` | Added | Six deterministic catalog tests without HTTP, database, or native plugin dependencies. |
| `docs/commit-notes/help-center-step-2.md` | Added | This commit description, file inventory, and verification record. |

## Validation completed

From `frontend/`:

```powershell
flutter test test/features/help/help_repository_test.dart --no-pub
dart analyze lib/features/help test/features/help/help_repository_test.dart
```

- All six catalog tests passed.
- Static analysis reported no issues in the Help feature or its tests.
- `git diff --check` passed.
- Copied the updated Help feature into the existing local Windows preview and
  hot-reloaded it successfully. The desktop app remained running after the
  debugger detached.

The tests verify bundled content lookup, missing-ID handling, title changes
without broken ID lookups, duplicate article/category rejection, missing
category rejection, slug validation, and catalog immutability.

## Current scope and next steps

The current content is a short starter guide in English. Existing screen labels
continue to use app localization. Translated catalogs should retain the same
IDs across locales.

The screen still includes the existing placeholder for upcoming guides.
Patient-focused featured content, category/article navigation routes, search,
and a richer article-section model are future steps. Only the existing `/help`
entry route is used at this stage.

## Relationship to the temporary Windows preview

Step 2 added no new dependency bypasses and made no changes to `pubspec.yaml`,
the Settings entry, the router, localization resources, backend source,
`.gitignore`, or the preview scripts.

The updated `frontend/lib/features/help/` directory was copied to
`tmp/windows-online/lib/features/help/` solely to update the running preview.
That generated copy remains local and should not be staged.

The restoration instructions for the original temporary Windows work remain
in [help-center-step-1.md](help-center-step-1.md). Keep the Step 2 source files
when retiring that preview; no Step 2 dependency restoration is needed.

No commit, push, dependency restoration, or preview cleanup was performed
while writing these notes.
