// Unit tests for lib/features/help/data/bundled_help_content.dart: the bundled
// topics and guides are internally consistent.
import 'package:care_connect_app/features/help/data/bundled_help_content.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('topic and guide IDs are unique', () {
    final topicIds = bundledHelpCategories.map((c) => c.id).toList();
    final guideIds = bundledHelpArticles.map((a) => a.id).toList();
    expect(topicIds.toSet(), hasLength(topicIds.length));
    expect(guideIds.toSet(), hasLength(guideIds.length));
  });

  test(
      'every guide belongs to a bundled topic and has a title, summary and role',
      () {
    final topicIds = bundledHelpCategories.map((c) => c.id).toSet();
    for (final article in bundledHelpArticles) {
      expect(topicIds, contains(article.categoryId), reason: article.id);
      expect(article.title.trim(), isNotEmpty, reason: article.id);
      expect(article.summary.trim(), isNotEmpty, reason: article.id);
      expect(article.roles, isNotEmpty, reason: article.id);
      expect(article.sections, isNotEmpty, reason: article.id);
    }
  });

  test('related-article links point at bundled guides', () {
    final guideIds = bundledHelpArticles.map((a) => a.id).toSet();
    for (final article in bundledHelpArticles) {
      for (final section in article.sections.whereType<HelpRelatedArticles>()) {
        for (final id in section.articleIds) {
          expect(guideIds, contains(id), reason: '${article.id} -> $id');
        }
      }
    }
  });

  test('the guide list cannot be changed at run time', () {
    expect(() => bundledHelpArticles.removeLast(), throwsUnsupportedError);
  });
}
