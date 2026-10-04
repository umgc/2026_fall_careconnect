/// Stable paths shared by Help links and the app router.
abstract final class HelpRoutes {
  static const home = '/help';
  static const articlePattern = 'articles/:articleId';

  static String article(String id) =>
      '$home/articles/${Uri.encodeComponent(id)}';
}
