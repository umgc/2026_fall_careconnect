import '../models/help_article.dart';
import '../models/help_category.dart';
import 'bundled_help_content.dart';

/// Immutable local catalog shared by Help screens.
///
/// Validate references here so new content cannot silently shadow an existing
/// ID or leave an article pointing to a category that does not exist.
class HelpRepository {
  HelpRepository({
    required Iterable<HelpCategory> categories,
    required Iterable<HelpArticle> articles,
  })  : categories = List.unmodifiable(categories),
        articles = List.unmodifiable(articles) {
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
      _articlesById[article.id] = article;
    }
  }

  factory HelpRepository.bundled() => HelpRepository(
        categories: bundledHelpCategories,
        articles: bundledHelpArticles,
      );

  final List<HelpCategory> categories;
  final List<HelpArticle> articles;
  final Map<String, HelpCategory> _categoriesById = {};
  final Map<String, HelpArticle> _articlesById = {};

  HelpCategory? findCategory(String id) => _categoriesById[id];

  HelpArticle? findArticle(String id) => _articlesById[id];

  List<HelpArticle> articlesForCategory(String categoryId) => List.unmodifiable(
        articles.where((article) => article.categoryId == categoryId),
      );

  static void _validateId(String id) {
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) {
      throw ArgumentError('Help IDs must be lowercase URL slugs: $id');
    }
  }
}
