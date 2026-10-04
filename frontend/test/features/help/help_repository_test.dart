// Validate the offline catalog's link integrity without native plugins or HTTP.
import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:flutter_test/flutter_test.dart';

const _category = HelpCategory(
  id: HelpCategoryIds.gettingStarted,
  title: 'Getting Started',
  description: 'Starter guides',
);

HelpArticle _article({
  String title = 'Opening Help',
  String categoryId = HelpCategoryIds.gettingStarted,
}) =>
    HelpArticle(
      id: HelpArticleIds.openingHelp,
      categoryId: categoryId,
      title: title,
      summary: 'Find Help',
      body: 'Open Settings > General > Help.',
    );

void main() {
  test('bundled content is readable through local IDs', () {
    final catalog = HelpRepository.bundled();

    expect(catalog.findCategory(HelpCategoryIds.gettingStarted), isNotNull);
    final article = catalog.findArticle(HelpArticleIds.openingHelp)!;
    expect(article.body, contains('Scroll down to General'));
    expect(catalog.articlesForCategory(article.categoryId), contains(article));
    expect(catalog.findArticle('unknown'), isNull);
    expect(catalog.findCategory('unknown'), isNull);
  });

  test('changing display titles preserves article and category lookups', () {
    // Arrange a revised title while preserving the published identifiers.
    final article = _article(title: 'Where to Find Help');
    final catalog = HelpRepository(
      categories: const [
        HelpCategory(
          id: HelpCategoryIds.gettingStarted,
          title: 'First Steps',
          description: 'Starter guides',
        ),
      ],
      articles: [article],
    );

    expect(catalog.findArticle(HelpArticleIds.openingHelp), same(article));
    expect(
      catalog.findCategory(HelpCategoryIds.gettingStarted)!.title,
      'First Steps',
    );
  });

  test('duplicate article and category IDs cannot shadow existing links', () {
    expect(
      () => HelpRepository(
        categories: const [_category],
        articles: [_article(), _article(title: 'Duplicate')],
      ),
      throwsArgumentError,
    );
    expect(
      () => HelpRepository(
          categories: const [_category, _category], articles: []),
      throwsArgumentError,
    );
  });

  test('articles must reference an existing category', () {
    expect(
      () => HelpRepository(
        categories: const [_category],
        articles: [_article(categoryId: 'missing-topic')],
      ),
      throwsArgumentError,
    );
  });

  test('IDs are valid URL slugs', () {
    expect(
      () => HelpRepository(
        categories: const [
          HelpCategory(id: 'Display Title', title: 'Topic', description: ''),
        ],
        articles: [],
      ),
      throwsArgumentError,
    );
  });

  test('callers cannot mutate the catalog after construction', () {
    final input = [_article()];
    final catalog =
        HelpRepository(categories: const [_category], articles: input);
    input.clear();

    expect(catalog.articles, hasLength(1));
    expect(() => catalog.articles.clear(), throwsUnsupportedError);
    expect(() => catalog.categories.clear(), throwsUnsupportedError);
    expect(
      () => catalog.articlesForCategory(_category.id).clear(),
      throwsUnsupportedError,
    );
  });
}
