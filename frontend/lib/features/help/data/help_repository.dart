import '../models/help_article.dart';
import '../models/help_category.dart';
import '../models/help_role.dart';
import '../models/help_section.dart';
import '../models/help_glossary_term.dart';
import 'bundled_glossary_content.dart';
import 'help_search.dart';
import 'bundled_help_content.dart';
import 'help_home_config.dart';

/// Immutable local catalog shared by Help screens.
///
/// Validate references here so new content cannot silently shadow an existing
/// ID or leave an article pointing to a category that does not exist.
class HelpRepository {
  HelpRepository({
    required Iterable<HelpCategory> categories,
    required Iterable<HelpArticle> articles,
    Iterable<String> popularArticleIds = const [],
    Iterable<HelpGlossaryTerm> glossaryTerms = const [],
  })  : categories = List.unmodifiable(categories),
        articles = List.unmodifiable(articles),
        popularArticleIds = List.unmodifiable(popularArticleIds),
        glossaryTerms = List.unmodifiable(glossaryTerms) {
    final termLabels = <String>{};
    for (final term in this.glossaryTerms) {
      _validateId(term.id);
      if (_termsById.containsKey(term.id) ||
          normalizeHelpSearch(term.term).isEmpty ||
          !termLabels.add(normalizeHelpSearch(term.term)) ||
          term.definition.trim().isEmpty) {
        throw ArgumentError('Duplicate or empty glossary term: ${term.id}');
      }
      _termsById[term.id] = term;
    }
    for (final category in this.categories) {
      _validateId(category.id);
      if (_categoriesById.containsKey(category.id)) {
        throw ArgumentError('Duplicate Help category ID: ${category.id}');
      }
      _categoriesById[category.id] = category;
    }

    for (final article in this.articles) {
      final termIds = [
        ...article.glossaryTermIds,
        for (final section in article.sections.whereType<HelpGlossaryTerms>())
          ...section.termIds
      ];
      if (termIds.toSet().length != termIds.length ||
          article.sections
              .whereType<HelpGlossaryTerms>()
              .any((section) => section.termIds.isEmpty)) {
        throw ArgumentError(
            'Empty or duplicate glossary references in ${article.id}');
      }
      for (final id in termIds) {
        if (!_termsById.containsKey(id)) {
          throw ArgumentError(
              'Help article ${article.id} links to missing term $id');
        }
      }
      _validateId(article.id);
      if (_articlesById.containsKey(article.id)) {
        throw ArgumentError('Duplicate Help article ID: ${article.id}');
      }
      if (!_categoriesById.containsKey(article.categoryId)) {
        throw ArgumentError(
          'Help article ${article.id} has unknown category ${article.categoryId}',
        );
      }
      if (article.roles.isEmpty || article.sections.isEmpty) {
        throw ArgumentError(
            'Help article ${article.id} needs roles and sections');
      }
      if (article.sections.any((section) =>
          section.heading != null && section.heading!.trim().isEmpty)) {
        throw ArgumentError('Help article ${article.id} has an empty heading');
      }
      _articlesById[article.id] = article;
    }

    // Resolve related links after indexing all articles, including forward links.
    final seenPopularIds = <String>{};
    for (final id in this.popularArticleIds) {
      if (!_articlesById.containsKey(id) || !seenPopularIds.add(id)) {
        throw ArgumentError(
            'Missing or duplicate popular Help article ID: $id');
      }
    }
    for (final term in this.glossaryTerms) {
      for (final id in term.relatedArticleIds) {
        if (!_articlesById.containsKey(id)) {
          throw ArgumentError(
              'Glossary term ${term.id} links to missing article $id');
        }
      }
    }

    for (final article in this.articles) {
      for (final section in article.sections.whereType<HelpRelatedArticles>()) {
        for (final relatedId in section.articleIds) {
          if (!_articlesById.containsKey(relatedId)) {
            throw ArgumentError(
              'Help article ${article.id} links to missing article $relatedId',
            );
          }
        }
      }
    }
  }

  factory HelpRepository.bundled() => HelpRepository(
        categories: bundledHelpCategories,
        articles: bundledHelpArticles,
        popularArticleIds: patientPopularHelpArticleIds,
        glossaryTerms: bundledHelpGlossary,
      );

  final List<HelpCategory> categories;
  final List<HelpArticle> articles;
  final List<String> popularArticleIds;
  final List<HelpGlossaryTerm> glossaryTerms;
  final Map<String, HelpGlossaryTerm> _termsById = {};
  final Map<String, HelpCategory> _categoriesById = {};
  final Map<String, HelpArticle> _articlesById = {};

  HelpCategory? findCategory(String id) => _categoriesById[id];

  HelpArticle? findArticle(String id) => _articlesById[id];

  HelpGlossaryTerm? findGlossaryTerm(String id) => _termsById[id];

  /// Generate definitions from IDs, without copying them into article content.
  List<HelpSection> sectionsForArticle(HelpArticle article) =>
      List.unmodifiable([
        ...article.sections,
        if (article.glossaryTermIds.isNotEmpty)
          HelpGlossaryTerms(termIds: article.glossaryTermIds),
      ]);

  List<HelpArticle> articlesForGlossaryTerm(String id,
      {required HelpRole role}) {
    final explicitIds =
        findGlossaryTerm(id)?.relatedArticleIds ?? const <String>[];
    return List.unmodifiable(articles.where((article) =>
        article.roles.contains(role) &&
        (explicitIds.contains(article.id) ||
            article.glossaryTermIds.contains(id) ||
            article.sections
                .whereType<HelpGlossaryTerms>()
                .any((section) => section.termIds.contains(id)))));
  }

  /// Exact labels and aliases rank first; remaining matches sort alphabetically.
  List<HelpGlossaryTerm> searchGlossary(String query) {
    final normalized = normalizeHelpSearch(query);
    final words = helpSearchWords(query);
    final matches = <(HelpGlossaryTerm, int)>[];
    for (final term in glossaryTerms) {
      final label = normalizeHelpSearch(term.term);
      final aliases = term.aliases.map(normalizeHelpSearch).toList();
      final nameText = [label, ...aliases].join(' ');
      final allText = '$nameText ${normalizeHelpSearch(term.definition)}';
      final rank = normalized.isEmpty
          ? 4
          : label == normalized
              ? 0
              : aliases.contains(normalized)
                  ? 1
                  : words.isNotEmpty && words.every(nameText.contains)
                      ? 2
                      : words.isNotEmpty && words.every(allText.contains)
                          ? 3
                          : null;
      if (rank != null) matches.add((term, rank));
    }
    matches.sort((a, b) {
      final rank = a.$2.compareTo(b.$2);
      return rank != 0
          ? rank
          : a.$1.term.toLowerCase().compareTo(b.$1.term.toLowerCase());
    });
    return List.unmodifiable(matches.map((match) => match.$1));
  }

  List<HelpArticle> articlesForCategory(String categoryId, {HelpRole? role}) =>
      List.unmodifiable(
        articles.where((article) =>
            article.categoryId == categoryId &&
            (role == null || article.roles.contains(role))),
      );

  List<HelpArticle> popularArticlesForRole(HelpRole role) => List.unmodifiable(
        popularArticleIds
            .map((id) => _articlesById[id]!)
            .where((article) => article.roles.contains(role)),
      );

  List<HelpCategory> categoriesForRole(HelpRole role) => List.unmodifiable(
        categories.where((category) =>
            articlesForCategory(category.id, role: role).isNotEmpty),
      );

  /// Local, case-insensitive matching of all query words, in catalog order.
  /// Searches titles, summaries, keywords, topics, and section text locally.
  List<HelpArticle> searchArticles(String query, {required HelpRole role}) {
    final words = helpSearchWords(query);
    if (words.isEmpty) return const [];
    return List.unmodifiable(articles.where((article) {
      if (!article.roles.contains(role)) return false;
      final text = [
        article.title,
        article.summary,
        ...article.keywords,
        for (final id in article.glossaryTermIds) ...[
          findGlossaryTerm(id)!.term,
          ...findGlossaryTerm(id)!.aliases,
        ],
        findCategory(article.categoryId)!.title,
        for (final section in article.sections) ...[
          section.heading ?? '',
          switch (section) {
            HelpParagraph() => section.text,
            HelpSteps() => section.steps.join(' '),
            HelpTroubleshooting() => section.tips
                .map((tip) => '${tip.problem} ${tip.solution}')
                .join(' '),
            HelpRelatedArticles() => '',
            HelpGlossaryTerms() => section.termIds
                .map((id) =>
                    '${findGlossaryTerm(id)!.term} ${findGlossaryTerm(id)!.aliases.join(' ')}')
                .join(' '),
          },
        ],
      ].join(' ');
      final normalized = normalizeHelpSearch(text);
      return words.every(normalized.contains);
    }));
  }

  static void _validateId(String id) {
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
      throw ArgumentError('Help IDs must be lowercase URL slugs: $id');
    }
  }
}
