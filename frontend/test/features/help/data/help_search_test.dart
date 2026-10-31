// Unit tests for lib/features/help/data/help_search.dart.
import 'package:care_connect_app/features/help/data/help_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeHelpSearch', () {
    test('lowercases, drops apostrophes and collapses punctuation to spaces',
        () {
      expect(normalizeHelpSearch("  Can't  Log-In?! "), 'cant log in');
      expect(
          normalizeHelpSearch('Caregiver’s   Medicare'), 'caregivers medicare');
    });

    test('keeps letters and digits from any script', () {
      expect(normalizeHelpSearch('Dose #2 — médicament'), 'dose 2 médicament');
    });

    test('returns an empty string for punctuation only', () {
      expect(normalizeHelpSearch(' ?!… '), isEmpty);
    });
  });

  group('helpSearchWords', () {
    test('drops filler words and keeps the meaningful ones in order', () {
      expect(helpSearchWords('How do I reset my password?'),
          ['reset', 'password']);
    });

    test('a query made only of filler words has no search words', () {
      expect(helpSearchWords('What is this?'), isEmpty);
    });

    test('normalizes before splitting', () {
      expect(helpSearchWords("Where's the check-in"), ['wheres', 'check']);
    });
  });
}
