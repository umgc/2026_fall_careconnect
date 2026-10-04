/// Bundled article content. Titles can change without changing saved IDs.
class HelpArticle {
  const HelpArticle({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.summary,
    required this.body,
  });

  final String id;
  final String categoryId;
  final String title;
  final String summary;
  final String body;
}
