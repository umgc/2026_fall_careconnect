import 'help_role.dart';
import 'help_section.dart';

/// Bundled article content. Titles can change without changing saved IDs.
class HelpArticle {
  HelpArticle({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.summary,
    required Iterable<HelpRole> roles,
    required Iterable<HelpSection> sections,
  })  : roles = Set.unmodifiable(roles),
        sections = List.unmodifiable(sections);

  final String id;
  final String categoryId;
  final String title;
  final String summary;
  final Set<HelpRole> roles;
  final List<HelpSection> sections;
}
