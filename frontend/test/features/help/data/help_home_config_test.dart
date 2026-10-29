import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:flutter_test/flutter_test.dart';

HelpRepository _catalog(
        {Iterable<String> popularIds = const ['second', 'first']}) =>
    HelpRepository(
      categories: const [
        HelpCategory(id: 'shared', title: 'Shared topic', description: ''),
        HelpCategory(
            id: 'caregiver', title: 'Caregiver topic', description: ''),
      ],
      popularArticleIds: popularIds,
      articles: [
        HelpArticle(
            id: 'first',
            categoryId: 'shared',
            title: 'Renamed title',
            summary: 'A description',
            roles: [
              HelpRole.patient
            ],
            sections: [
              HelpSteps(steps: ['Record a dose'])
            ]),
        HelpArticle(
            id: 'second',
            categoryId: 'shared',
            title: 'Second guide',
            summary: 'A description',
            roles: [
              HelpRole.patient
            ],
            sections: [
              HelpTroubleshooting(tips: [
                const HelpTroubleshootingTip(
                    problem: 'Missing reminder', solution: 'Reload Home')
              ])
            ]),
        HelpArticle(
            id: 'staff',
            categoryId: 'caregiver',
            title: 'Record a dose',
            summary: 'Missing reminder',
            roles: [HelpRole.caregiver],
            sections: const [HelpParagraph(text: 'For caregivers')]),
      ],
    );

void main() {
  test('TC-HELP-042: keyword synonyms match locally and are defensively copied', () {
    final keywords = ['rx', 'prescription refill'];
    final article = HelpArticle(
      id: 'medicine-guide',
      categoryId: 'shared',
      title: 'A guide',
      summary: 'A description',
      roles: [HelpRole.patient],
      sections: const [HelpParagraph(text: 'Instructions')],
      keywords: keywords,
    );
    keywords.clear();
    final catalog = HelpRepository(categories: const [
      HelpCategory(id: 'shared', title: 'Shared', description: ''),
    ], articles: [
      article
    ]);
    expect(catalog.searchArticles('  RX  ', role: HelpRole.patient), [article]);
    expect(
        catalog.searchArticles('refill prescription', role: HelpRole.patient),
        [article]);
    expect(catalog.searchArticles('rx', role: HelpRole.caregiver), isEmpty);
    expect(() => article.keywords.clear(), throwsUnsupportedError);
  });

  test('TC-HELP-043: bundled synonyms find the intended Patient guide', () {
    final catalog = HelpRepository.bundled();
    expect(
        catalog
            .searchArticles('medicine', role: HelpRole.patient)
            .map((a) => a.id),
        contains(HelpArticleIds.recordingDose));
    expect(
        catalog.searchArticles('chat', role: HelpRole.patient).map((a) => a.id),
        contains(HelpArticleIds.messagingCaregiver));
    expect(
        catalog
            .searchArticles('forgot password', role: HelpRole.patient)
            .map((a) => a.id),
        contains(HelpArticleIds.resettingPassword));
  });

  test('TC-HELP-044: bundled Patient popular guides have the requested fixed order', () {
    final articles =
        HelpRepository.bundled().popularArticlesForRole(HelpRole.patient);
    expect(articles.map((article) => article.title), [
      'Getting started with CareConnect',
      'Viewing medications and recording a dose',
      'Completing a daily check-in',
      'Viewing appointments',
      'Messaging your caregiver',
      'Resetting your password',
    ]);
    expect(
        articles.every((article) => article.roles.contains(HelpRole.patient)),
        isTrue);
    expect(HelpRepository.bundled().findArticle(HelpArticleIds.openingHelp),
        isNotNull);
  });

  test('TC-HELP-045: selection uses ID order independent of titles and catalog order', () {
    final ids = ['second', 'first'];
    final catalog = _catalog(popularIds: ids);
    ids.clear();
    expect(catalog.popularArticlesForRole(HelpRole.patient).map((a) => a.id),
        ['second', 'first']);
    expect(() => catalog.popularArticleIds.clear(), throwsUnsupportedError);
  });

  test('TC-HELP-046: missing and duplicate popular IDs fail during catalog validation', () {
    expect(() => _catalog(popularIds: ['missing']), throwsArgumentError);
    expect(() => _catalog(popularIds: ['first', 'first']), throwsArgumentError);
  });

  test('TC-HELP-047: search matches all words in content and topics and filters by role',
      () {
    final catalog = _catalog(popularIds: ['staff', 'second', 'first']);
    expect(
        catalog
            .searchArticles('  DOSE  record  ', role: HelpRole.patient)
            .map((a) => a.id),
        ['first']);
    expect(
        catalog
            .searchArticles('reload missing', role: HelpRole.patient)
            .map((a) => a.id),
        ['second']);
    expect(
        catalog
            .searchArticles('shared topic', role: HelpRole.patient)
            .map((a) => a.id),
        ['first', 'second']);
    expect(catalog.searchArticles('unknown', role: HelpRole.patient), isEmpty);
    expect(catalog.searchArticles('   ', role: HelpRole.patient), isEmpty);
    expect(catalog.popularArticlesForRole(HelpRole.patient).map((a) => a.id),
        ['second', 'first']);
    expect(catalog.categoriesForRole(HelpRole.patient).map((c) => c.id),
        ['shared']);
    expect(catalog.articlesForCategory('caregiver', role: HelpRole.patient),
        isEmpty);
  });
}
