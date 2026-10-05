import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/data/help_search.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/models/help_glossary_term.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:flutter_test/flutter_test.dart';

HelpRepository _catalog(
        {Iterable<HelpGlossaryTerm> terms = const [],
        Iterable<HelpArticle> articles = const []}) =>
    HelpRepository(categories: const [
      HelpCategory(id: 'topic', title: 'Topic', description: '')
    ], articles: articles, glossaryTerms: terms);
HelpGlossaryTerm _term(
        {String id = 'word',
        String term = 'Word',
        String definition = 'A meaning.',
        Iterable<String> aliases = const [],
        Iterable<String> links = const []}) =>
    HelpGlossaryTerm(
        id: id,
        term: term,
        definition: definition,
        aliases: aliases,
        relatedArticleIds: links);
HelpArticle _article(
        {String id = 'guide',
        HelpRole role = HelpRole.patient,
        Iterable<String> terms = const [],
        Iterable<HelpSection>? sections}) =>
    HelpArticle(
        id: id,
        categoryId: 'topic',
        title: id,
        summary: 'A guide.',
        roles: [role],
        glossaryTermIds: terms,
        sections: sections ?? const [HelpParagraph(text: 'Read this.')]);

void main() {
  test('TC-HELP-037: all 75 approved labels and every alias are discoverable offline', () {
    final catalog = HelpRepository.bundled();
    expect(catalog.glossaryTerms, hasLength(75));
    for (final term in catalog.glossaryTerms) {
      expect(term.definition.trim(), isNotEmpty);
      expect(catalog.searchGlossary(term.term).first, same(term));
      final seen = {normalizeHelpSearch(term.term)};
      for (final alias in term.aliases) {
        expect(seen.add(normalizeHelpSearch(alias)), isTrue,
            reason: '${term.id}: $alias');
        expect(catalog.searchGlossary(alias), contains(term),
            reason: '${term.id}: $alias');
      }
    }
    final alphabetical = catalog
        .searchGlossary('')
        .map((term) => term.term.toLowerCase())
        .toList();
    final sorted = [...alphabetical]..sort();
    expect(alphabetical, sorted);
    expect(catalog.searchGlossary('What is EVV?').first.id, 'evv');
    expect(catalog.searchGlossary('WHY CAN’T I USE THE CAMERA?').first.id,
        'camera-access');
    expect(
        catalog.searchGlossary('read words aloud').first.id, 'text-to-speech');
    expect(catalog.searchGlossary('no internet').first.id, 'offline');
    expect(catalog.searchGlossary('zzzz-no-match'), isEmpty);
    expect(helpSearchWords('why is it not online without internet'),
        ['not', 'online', 'without', 'internet']);
  });

  test('TC-HELP-038: exact label outranks overlapping aliases and definition matches', () {
    final exact = _term(term: 'Dose');
    final alias = _term(id: 'alias', term: 'Alias', aliases: ['dose']);
    final description = _term(
        id: 'description', term: 'Description', definition: 'A dose amount.');
    final catalog = _catalog(terms: [description, alias, exact]);
    expect(catalog.searchGlossary('DOSE!'), [exact, alias, description]);
    expect(catalog.searchGlossary('amount'), [description]);
    expect(catalog.searchGlossary('what is'), isEmpty);
  });

  test('TC-HELP-039: aliases normalize punctuation, apostrophes, case and duplicates', () {
    final aliases = [
      'text to speech',
      'TTS',
      'tts',
      'read-aloud',
      'Read aloud'
    ];
    final term = _term(term: 'Text-to-speech', aliases: aliases);
    aliases.clear();
    expect(term.aliases, ['TTS', 'read-aloud']);
    expect(normalizeHelpSearch("Can't / can’t"), 'cant cant');
    expect(() => _term(aliases: [' -- ']), throwsArgumentError);
    expect(() => term.aliases.clear(), throwsUnsupportedError);
  });

  test('TC-HELP-040: bad IDs, duplicate IDs, empty labels/meanings and missing links fail',
      () {
    for (final terms in [
      [_term(id: 'Bad ID')],
      [_term(), _term()],
      [_term(), _term(id: 'another', term: 'WORD')],
      [_term(term: ' ')],
      [_term(definition: ' ')],
      [
        _term(links: ['missing'])
      ],
    ]) {
      expect(() => _catalog(terms: terms), throwsArgumentError);
    }
    expect(
        () => _catalog(articles: [
              _article(terms: ['missing'])
            ]),
        throwsArgumentError);
    expect(
        () => _catalog(terms: [
              _term()
            ], articles: [
              _article(sections: [HelpGlossaryTerms(termIds: [])]),
            ]),
        throwsArgumentError);
    expect(
        () => _catalog(terms: [
              _term()
            ], articles: [
              _article(terms: ['word', 'word'])
            ]),
        throwsArgumentError);
    expect(
        () => _catalog(articles: [
              _article(sections: [
                HelpGlossaryTerms(termIds: ['missing'])
              ])
            ]),
        throwsArgumentError);
  });

  test(
      'TC-HELP-041: one definition generates article sections and audience-filtered backlinks',
      () {
    final term = _term(aliases: ['plain words'], links: ['guide']);
    final patient = _article(terms: ['word']);
    final caregiver = _article(
        id: 'caregiver-guide', role: HelpRole.caregiver, terms: ['word']);
    final catalog = _catalog(terms: [term], articles: [patient, caregiver]);
    final sections = catalog.sectionsForArticle(patient);
    expect(sections.last, isA<HelpGlossaryTerms>());
    expect((sections.last as HelpGlossaryTerms).termIds, ['word']);
    expect(catalog.articlesForGlossaryTerm('word', role: HelpRole.patient),
        [patient]);
    expect(catalog.articlesForGlossaryTerm('word', role: HelpRole.caregiver),
        [caregiver]);
    expect(catalog.searchArticles('plain words', role: HelpRole.patient),
        [patient]);
    expect(catalog.sectionsForArticle(_article()), hasLength(1));
    expect(() => sections.clear(), throwsUnsupportedError);
    expect(() => catalog.glossaryTerms.clear(), throwsUnsupportedError);
    expect(() => patient.glossaryTermIds.clear(), throwsUnsupportedError);
    expect(() => term.relatedArticleIds.clear(), throwsUnsupportedError);
  });
}
