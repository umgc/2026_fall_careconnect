// Unit tests for lib/features/help/data/help_content_ids.dart: every stable
// ID is unique and resolves in the bundled catalog.
import 'package:care_connect_app/features/help/data/help_content_ids.dart';
import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _categoryIds = [
  HelpCategoryIds.gettingStarted,
  HelpCategoryIds.medications,
  HelpCategoryIds.checkIns,
  HelpCategoryIds.appointments,
  HelpCategoryIds.messaging,
  HelpCategoryIds.account,
];

const _articleIds = [
  HelpArticleIds.openingHelp,
  HelpArticleIds.readingHelp,
  HelpArticleIds.gettingStarted,
  HelpArticleIds.recordingDose,
  HelpArticleIds.dailyCheckIn,
  HelpArticleIds.viewingAppointments,
  HelpArticleIds.messagingCaregiver,
  HelpArticleIds.resettingPassword,
];

void main() {
  final repository = HelpRepository.bundled();

  test('category and article IDs are unique', () {
    expect(_categoryIds.toSet(), hasLength(_categoryIds.length));
    expect(_articleIds.toSet(), hasLength(_articleIds.length));
  });

  test('every category ID resolves to a bundled topic', () {
    for (final id in _categoryIds) {
      expect(repository.findCategory(id), isNotNull, reason: id);
    }
  });

  test('every article ID resolves to a bundled guide', () {
    for (final id in _articleIds) {
      expect(repository.findArticle(id), isNotNull, reason: id);
    }
  });
}
