/// Shared English catalog search normalization. Keep negation meaningful.
String normalizeHelpSearch(String text) => text
    .toLowerCase()
    .replaceAll(RegExp("[’']"), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

List<String> helpSearchWords(String query) {
  const filler = {
    'a',
    'an',
    'the',
    'what',
    'does',
    'do',
    'is',
    'are',
    'how',
    'i',
    'my',
    'me',
    'can',
    'to',
    'of',
    'for',
    'in',
    'with',
    'this',
    'why',
    'who',
    'where',
    'please',
    'would',
    'will',
    'should',
    'when',
    'it',
    'you',
    'your',
  };
  return normalizeHelpSearch(query)
      .split(' ')
      .where((word) => word.isNotEmpty && !filler.contains(word))
      .toList();
}
