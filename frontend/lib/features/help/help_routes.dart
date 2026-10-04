/// Stable paths shared by Help links and the app router.
abstract final class HelpRoutes {
  static const home = '/help';
  static const articlePattern = 'articles/:articleId';
  static const topicPattern = 'topics/:categoryId';

  static String topic(String id) => '$home/topics/${Uri.encodeComponent(id)}';

  static String article(String id) =>
      '$home/articles/${Uri.encodeComponent(id)}';
}
