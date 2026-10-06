import '../data/help_search.dart';

/// One shared, offline definition. Aliases are discovery phrases, not promises.
class HelpGlossaryTerm {
  HelpGlossaryTerm({
    required this.id,
    required this.term,
    required this.definition,
    Iterable<String> aliases = const [],
    Iterable<String> relatedArticleIds = const [],
  })  : aliases = _uniqueAliases(term, aliases),
        relatedArticleIds = List.unmodifiable(relatedArticleIds);

  final String id;
  final String term;
  final String definition;
  final List<String> aliases;
  final List<String> relatedArticleIds;

  static List<String> _uniqueAliases(String term, Iterable<String> aliases) {
    final seen = {normalizeHelpSearch(term)};
    final result = <String>[];
    for (final alias in aliases) {
      final normalized = normalizeHelpSearch(alias);
      if (normalized.isEmpty) {
        throw ArgumentError('Glossary aliases must not be blank');
      }
      if (seen.add(normalized)) result.add(alias.trim());
    }
    return List.unmodifiable(result);
  }
}
