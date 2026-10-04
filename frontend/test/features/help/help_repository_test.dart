// Validate the offline catalog's link integrity without native plugins or HTTP.
import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:flutter_test/flutter_test.dart';

const _category = HelpCategory(
  id: HelpCategoryIds.gettingStarted,
  title: 'Getting Started',
  description: 'Starter guides',
);

HelpArticle _article({
  String id = HelpArticleIds.openingHelp,
  String title = 'Opening Help',
  String categoryId = HelpCategoryIds.gettingStarted,
  Iterable<HelpRole> roles = const [HelpRole.patient],
  Iterable<HelpSection> sections = const [
    HelpParagraph(text: 'Open Settings > General > Help.'),
  ],
}) =>
    HelpArticle(
      id: id,
      categoryId: categoryId,
      title: title,
      summary: 'Find Help',
      roles: roles,
      sections: sections,
    );

void main() {
  test(
      'authored section headings must be nonempty; repeated headings are valid',
      () {
    expect(
        () => HelpRepository(categories: const [
              _category
            ], articles: [
              _article(
                  sections: const [HelpParagraph(heading: '  ', text: 'Text')]),
            ]),
        throwsArgumentError);
    final catalog = HelpRepository(categories: const [
      _category
    ], articles: [
      _article(sections: const [
        HelpParagraph(heading: 'Details', text: 'First section'),
        HelpParagraph(heading: 'Details', text: 'Second section'),
      ]),
    ]);
    expect(catalog.articles.single.sections, hasLength(2));
  });

  test('bundled content is readable through local IDs', () {
    final catalog = HelpRepository.bundled();

    expect(catalog.findCategory(HelpCategoryIds.gettingStarted), isNotNull);
    final article = catalog.findArticle(HelpArticleIds.openingHelp)!;
    expect(article.sections.whereType<HelpSteps>().first.steps,
        contains('Scroll down to General.'));
    expect(article.roles, contains(HelpRole.patient));
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

  test('related links can point forward but must resolve to an existing ID',
      () {
    final first = _article(sections: [
      HelpRelatedArticles(articleIds: [HelpArticleIds.readingHelp]),
    ]);
    final second = _article(id: HelpArticleIds.readingHelp);

    expect(
      HelpRepository(categories: const [_category], articles: [first, second])
          .findArticle(HelpArticleIds.readingHelp),
      same(second),
    );
    expect(
      () => HelpRepository(categories: const [_category], articles: [first]),
      throwsArgumentError,
    );
  });

  test('articles declare an audience and at least one content section', () {
    expect(
      () => HelpRepository(
        categories: const [_category],
        articles: [_article(roles: [])],
      ),
      throwsArgumentError,
    );
    expect(
      () => HelpRepository(
        categories: const [_category],
        articles: [_article(sections: [])],
      ),
      throwsArgumentError,
    );
  });

  test('article and section collections cannot be changed by callers', () {
    // Arrange mutable inputs to ensure models take defensive copies.
    final roles = [HelpRole.patient];
    final steps = ['First action'];
    final links = [HelpArticleIds.readingHelp];
    final tips = [
      const HelpTroubleshootingTip(problem: 'Problem', solution: 'Fix')
    ];
    final stepSection = HelpSteps(steps: steps);
    final linkSection = HelpRelatedArticles(articleIds: links);
    final tipSection = HelpTroubleshooting(tips: tips);
    final sections = <HelpSection>[stepSection, linkSection, tipSection];
    final article = _article(roles: roles, sections: sections);

    // Act: mutate the inputs after constructing the article.
    roles.clear();
    steps.clear();
    links.clear();
    tips.clear();
    sections.clear();

    // Assert: published content and links retain their values.
    expect(article.roles, contains(HelpRole.patient));
    expect(article.sections, hasLength(3));
    expect(stepSection.steps, ['First action']);
    expect(linkSection.articleIds, [HelpArticleIds.readingHelp]);
    expect(tipSection.tips, hasLength(1));
    expect(() => article.roles.clear(), throwsUnsupportedError);
    expect(() => article.sections.clear(), throwsUnsupportedError);
    expect(() => stepSection.steps.clear(), throwsUnsupportedError);
    expect(() => linkSection.articleIds.clear(), throwsUnsupportedError);
    expect(() => tipSection.tips.clear(), throwsUnsupportedError);
  });
}
