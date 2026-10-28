// Unit tests for lib/features/help/help_routes.dart.
import 'package:care_connect_app/features/help/help_routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Help lives under /help with nested article, topic and glossary paths',
      () {
    expect(HelpRoutes.home, '/help');
    expect(HelpRoutes.glossary, '/help/glossary');
    expect(HelpRoutes.articlePattern, 'articles/:articleId');
    expect(HelpRoutes.topicPattern, 'topics/:categoryId');
  });

  test('article and topic links encode their IDs', () {
    expect(HelpRoutes.article('resetting-your-password'),
        '/help/articles/resetting-your-password');
    expect(HelpRoutes.topic('a b/c'), '/help/topics/a%20b%2Fc');
  });

  test('a glossary link carries the term as a query parameter', () {
    expect(
        HelpRoutes.glossaryTerm('caregiver'), '/help/glossary?term=caregiver');
    expect(Uri.parse(HelpRoutes.glossaryTerm('a&b')).queryParameters['term'],
        'a&b');
  });
}
