import '../models/help_article.dart';
import '../models/help_category.dart';
import '../models/help_role.dart';
import '../models/help_section.dart';
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
  })  : categories = List.unmodifiable(categories),
        articles = List.unmodifiable(articles),
        popularArticleIds = List.unmodifiable(popularArticleIds) {
    for (final category in this.categories) {
      _validateId(category.id);
      if (_categoriesById.containsKey(category.id)) {
        throw ArgumentError('Duplicate Help category ID: ${category.id}');
      }
      _categoriesById[category.id] = category;
    }

    for (final article in this.articles) {
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
      );

  final List<HelpCategory> categories;
  final List<HelpArticle> articles;
  final List<String> popularArticleIds;
  final Map<String, HelpCategory> _categoriesById = {};
  final Map<String, HelpArticle> _articlesById = {};

  HelpCategory? findCategory(String id) => _categoriesById[id];

  HelpArticle? findArticle(String id) => _articlesById[id];

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
  /// Searches titles, summaries, topics, and section text without any services.
  List<HelpArticle> searchArticles(String query, {required HelpRole role}) {
    final words = query.trim().toLowerCase().split(RegExp(r'\s+'));
    if (words.first.isEmpty) return const [];
    return List.unmodifiable(articles.where((article) {
      if (!article.roles.contains(role)) return false;
      final text = [
        article.title,
        article.summary,
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
          },
        ],
      ].join(' ').toLowerCase();
      return words.every(text.contains);
    }));
  }

  static void _validateId(String id) {
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
      throw ArgumentError('Help IDs must be lowercase URL slugs: $id');
    }
  }
}
