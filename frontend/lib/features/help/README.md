# Help Center feature

Help lives under Settings > General > Help at `/help`.

```text
help/
  models/                 Immutable article and category data; no Flutter imports
  data/
    help_content_ids.dart Permanent IDs shared by content and screens
    bundled_help_content.dart Local article and category entries
    help_repository.dart  Validated catalog and lookups by ID
  presentation/
    pages/                Screens and navigation
    widgets/              Reusable article presentation
```

The initial catalog is compiled into the app as Dart constants. It requires no
backend request, credentials, database, new dependency, or asset download. Help
remains readable without a network connection. The activities described by
future articles may still require connectivity.

The current screen renders a short Opening Help article and the existing
placeholder for upcoming guides. Patient-focused featured articles, category
navigation, and search are later steps.

## Add content

1. Add a lowercase, hyphen-separated ID to `help_content_ids.dart`.
2. Add a `HelpCategory` to `bundledHelpCategories` if creating a new topic.
3. Add a `HelpArticle` to `bundledHelpArticles`, using the category's ID.
4. Run `flutter test test/features/help/help_repository_test.dart --no-pub`.

IDs are permanent and independent of display text. For example, keep
`opening-help` when changing the article title. Future article/category routes
should use these IDs, never titles or list positions. The repository rejects
duplicate IDs, invalid URL slugs, and missing category references. Missing ID
lookups return null so future screens can present a useful fallback.

`HelpArticleContent` renders article data without loading it or navigating.
`HelpCenterPage` accepts a catalog for previews and tests; its default is the
bundled catalog. Future screens should use the same repository API.

The starter article content is English. Screen labels use the existing app
localization system. Future translated catalogs should preserve the same IDs
across locales; translation must not affect article links.
