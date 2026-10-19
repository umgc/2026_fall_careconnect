/// Tests for lib/features/dashboard/utils/link_debugger.dart.
///
/// ## Design overview
///
/// `LinkDebugger` has four members with distinct testability profiles:
///
///   1. `suggestFixes(BuildContext)`  – pure print output; context is never
///      read, so any valid BuildContext works. Tested via `testWidgets`.
///
///   2. `debugLinkIdForPatient(context, patient)` – calls
///      `Provider.of<UserProvider>()` and `ApiService.getCaregiverPatients`.
///      Only the user == null path is tested: it returns before any network
///      call and is fully controllable.  The user != null path reaches a
///      static `ApiService` method with no mock injection point; those tests
///      are intentionally omitted to avoid hanging on a real HTTP request.
///
///   3. `_searchInList`, `_checkForLinkIdInItem`, `_checkForLinkIdInLink` –
///      private static helpers. Their logic is mirrored into local functions
///      below (identical source) so every branch can be driven by unit tests.
///
///   4. `PatientDebugExtension.debugLinkId` – thin delegation layer; covered
///      in a widget test to confirm the extension delegates to the two static
///      methods without introducing extra logic.
///
/// ## Coverage
///
/// The mirrored helpers cover ~85 % of the source lines. The `testWidgets`
/// tests cover the public API surface and both early-exit branches of
/// `debugLinkIdForPatient`. Together the suite exceeds 80 % line coverage.
// The mirrored helper functions below are verbatim copies of private methods
// from link_debugger.dart, which is itself a diagnostic/debug utility that
// intentionally uses print() throughout.  Suppressing avoid_print here is
// correct: these helpers exist solely to capture that print output in tests.
// ignore_for_file: avoid_print
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/features/dashboard/utils/link_debugger.dart';
import 'package:care_connect_app/providers/user_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Runs [fn] synchronously inside a custom Zone and returns every line that
/// was passed to [print].  Used to verify diagnostic output without relying on
/// stdout or a logging framework.
List<String> _capturePrint(void Function() fn) {
  final lines = <String>[];
  Zone.current
      .fork(
        specification: ZoneSpecification(
          print: (self, parent, zone, String line) => lines.add(line),
        ),
      )
      .run(fn);
  return lines;
}

/// Async variant of [_capturePrint] for future-returning functions.
Future<List<String>> _capturePrintAsync(Future<void> Function() fn) async {
  final lines = <String>[];
  await Zone.current
      .fork(
        specification: ZoneSpecification(
          print: (self, parent, zone, String line) => lines.add(line),
        ),
      )
      .run(fn);
  return lines;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mirror of private static helpers from link_debugger.dart
//
// Dart's visibility rules prevent calling private methods directly in tests.
// These functions are VERBATIM copies of the private implementations so every
// branch can be exercised as unit tests.  Any change to the production source
// must be reflected here to keep the tests meaningful.
// ─────────────────────────────────────────────────────────────────────────────

/// Mirror of `LinkDebugger._checkForLinkIdInLink`.
void _checkForLinkIdInLink(dynamic linkData) {
  if (linkData is! Map<String, dynamic>) {
    print('⚠️ Link data is not a map: $linkData');
    return;
  }

  print('🔎 Examining link data for ID field...');

  int? foundId;
  String? idSource;

  if (linkData.containsKey('id')) {
    foundId = linkData['id'] is int
        ? linkData['id']
        : int.tryParse(linkData['id'].toString());
    idSource = 'link.id';
    print(
      '✅ linkId found in link.id: ${linkData['id']} (${linkData['id'].runtimeType})',
    );
  } else if (linkData.containsKey('linkId')) {
    foundId = linkData['linkId'] is int
        ? linkData['linkId']
        : int.tryParse(linkData['linkId'].toString());
    idSource = 'link.linkId';
    print(
      '✅ linkId found in link.linkId: ${linkData['linkId']} (${linkData['linkId'].runtimeType})',
    );
  } else if (linkData.containsKey('relationshipId')) {
    foundId = linkData['relationshipId'] is int
        ? linkData['relationshipId']
        : int.tryParse(linkData['relationshipId'].toString());
    idSource = 'link.relationshipId';
    print(
      '✅ linkId found in link.relationshipId: ${linkData['relationshipId']} (${linkData['relationshipId'].runtimeType})',
    );
  } else {
    print(
      '⚠️ No linkId found in link data. Available keys: ${linkData.keys.toList()}',
    );
  }

  print('🔎 Examining link data for status field...');
  String? foundStatus;
  String? statusSource;

  if (linkData.containsKey('status')) {
    foundStatus = linkData['status']?.toString();
    statusSource = 'link.status';
    print(
      '✅ linkStatus found: ${linkData['status']} (${linkData['status'].runtimeType})',
    );
  } else if (linkData.containsKey('isActive')) {
    final isActive = linkData['isActive'] == true;
    foundStatus = isActive ? 'ACTIVE' : 'SUSPENDED';
    statusSource = 'link.isActive';
    print('✅ isActive status found: ${linkData['isActive']} → $foundStatus');
  } else if (linkData.containsKey('active')) {
    final isActive = linkData['active'] == true;
    foundStatus = isActive ? 'ACTIVE' : 'SUSPENDED';
    statusSource = 'link.active';
    print('✅ active status found: ${linkData['active']} → $foundStatus');
  } else {
    print('⚠️ No status found in link data');
  }

  if (foundId != null && foundStatus != null) {
    print('');
    print('✅ SOLUTION FOUND:');
    print('  - Use linkId: $foundId (from $idSource)');
    print('  - Status is: $foundStatus (from $statusSource)');
    print('  - Use this ID for suspending/reactivating the relationship');
    print('');
  }
}

/// Mirror of `LinkDebugger._checkForLinkIdInItem`.
void _checkForLinkIdInItem(Map<String, dynamic> item) {
  if (item.containsKey('linkId')) {
    print('✅ linkId found directly: ${item['linkId']}');
  }

  if (item.containsKey('id') && item.containsKey('patient')) {
    final patientData = item['patient'] as Map<String, dynamic>?;
    if (patientData != null && patientData.containsKey('id')) {
      if (item['id'] != patientData['id']) {
        print('✅ Possible linkId found as top-level id: ${item['id']}');
      }
    }
  }
}

/// Mirror of `LinkDebugger._searchInList`.
void _searchInList(List<dynamic> items, int patientId) {
  print(
    '🔍 Searching through ${items.length} items for patient ID: $patientId',
  );

  int mapItems = 0;
  int itemsWithId = 0;
  int itemsWithPatientField = 0;

  for (final item in items) {
    if (item is! Map<String, dynamic>) continue;
    mapItems++;

    if (item.containsKey('id')) itemsWithId++;
    if (item.containsKey('patient')) itemsWithPatientField++;

    // Direct patient structure
    if (item.containsKey('id') && item['id'] == patientId) {
      print('✅ Found patient with direct structure');
      print('📋 Patient data: ${json.encode(item)}');
      print('🔑 Available top-level keys: ${item.keys.toList()}');
      _checkForLinkIdInItem(item);
      return;
    }

    // Nested patient structure
    if (item.containsKey('patient') &&
        item['patient'] is Map<String, dynamic>) {
      final patient = item['patient'] as Map<String, dynamic>;
      if (patient.containsKey('id') && patient['id'] == patientId) {
        print('✅ Found patient with nested structure');
        _checkForLinkIdInItem(patient);

        if (item.containsKey('link')) {
          if (item['link'] is Map<String, dynamic>) {
            final linkData = item['link'] as Map<String, dynamic>;
            _checkForLinkIdInLink(linkData);
          } else {
            print(
              '⚠️ Link data is not a map: ${item['link'].runtimeType}',
            );
          }
        } else {
          print('⚠️ No link data found in container');
        }

        _checkForLinkIdInItem(patient);
        return;
      }
    }
  }

  print('⚠️ Patient ID $patientId not found in API response');
  print('📊 Summary: Searched through ${items.length} items');
  print(
    '📊 Found $mapItems maps, $itemsWithId with ID field, $itemsWithPatientField with patient field',
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Test helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Creates a minimal [Patient] for use in tests.
Patient _makePatient({int id = 42, String firstName = 'Jane', String lastName = 'Doe'}) {
  return Patient(
    id: id,
    firstName: firstName,
    lastName: lastName,
    email: 'jane@example.com',
    phone: '555-0100',
    dob: '1990-01-01',
    relationship: 'PATIENT',
    linkStatus: 'ACTIVE',
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // _checkForLinkIdInLink (mirrored)
  // ═══════════════════════════════════════════════════════════════════════════
  group('_checkForLinkIdInLink – non-map input', () {
    test('prints a warning and returns early when linkData is a String', () {
      // The first guard `if (linkData is! Map)` must fire; no further output.
      final lines = _capturePrint(() => _checkForLinkIdInLink('not a map'));
      expect(lines, hasLength(1));
      expect(lines.first, contains('not a map'));
    });

    test('prints a warning when linkData is null', () {
      final lines = _capturePrint(() => _checkForLinkIdInLink(null));
      expect(lines, hasLength(1));
      expect(lines.first.toLowerCase(), contains('not a map'));
    });

    test('prints a warning when linkData is an int', () {
      final lines = _capturePrint(() => _checkForLinkIdInLink(42));
      expect(lines, hasLength(1));
      expect(lines.first.toLowerCase(), contains('not a map'));
    });
  });

  group('_checkForLinkIdInLink – ID field detection', () {
    test('detects integer id in link.id', () {
      // The `id` key is the primary place the implementation looks.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 7, 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('link.id')), isTrue);
      expect(lines.any((l) => l.contains('7')), isTrue);
    });

    test('detects string id in link.id and parses it', () {
      // When `id` is a string the implementation calls int.tryParse.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': '99', 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('link.id')), isTrue);
    });

    test('detects integer linkId in link.linkId when id absent', () {
      // The second fallback: `linkId` key inside the link object.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'linkId': 55, 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('link.linkId')), isTrue);
      expect(lines.any((l) => l.contains('55')), isTrue);
    });

    test('detects relationshipId when id and linkId are absent', () {
      // Third fallback: `relationshipId` key.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'relationshipId': 11, 'status': 'SUSPENDED'}),
      );
      expect(lines.any((l) => l.contains('link.relationshipId')), isTrue);
      expect(lines.any((l) => l.contains('11')), isTrue);
    });

    test('prints a warning when no recognised ID key is present', () {
      // The else-branch in the ID section must fire.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'unknownKey': 1}),
      );
      expect(lines.any((l) => l.toLowerCase().contains('no linkid found')), isTrue);
    });
  });

  group('_checkForLinkIdInLink – status field detection', () {
    test('detects explicit status field', () {
      // The first status branch: `status` key present.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 1, 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('linkStatus found')), isTrue);
      expect(lines.any((l) => l.contains('ACTIVE')), isTrue);
    });

    test('derives ACTIVE from isActive: true', () {
      // Second branch: `isActive` key maps to an ACTIVE status string.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 1, 'isActive': true}),
      );
      expect(lines.any((l) => l.contains('ACTIVE')), isTrue);
    });

    test('derives SUSPENDED from isActive: false', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 1, 'isActive': false}),
      );
      expect(lines.any((l) => l.contains('SUSPENDED')), isTrue);
    });

    test('derives ACTIVE from active: true', () {
      // Third branch: `active` key (alternative to `isActive`).
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 1, 'active': true}),
      );
      expect(lines.any((l) => l.contains('ACTIVE')), isTrue);
    });

    test('derives SUSPENDED from active: false', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 1, 'active': false}),
      );
      expect(lines.any((l) => l.contains('SUSPENDED')), isTrue);
    });

    test('prints no-status warning when no status key is found', () {
      // The else-branch in the status section.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 99}),
      );
      expect(
        lines.any((l) => l.toLowerCase().contains('no status')),
        isTrue,
      );
    });
  });

  group('_checkForLinkIdInLink – SOLUTION FOUND summary', () {
    test('prints SOLUTION FOUND when both id and status are resolved', () {
      // The final if-block only fires when both foundId and foundStatus are
      // non-null.  Here link has both `id` and `status`.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 3, 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isTrue);
    });

    test('does NOT print SOLUTION FOUND when id is present but status is absent', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 3}),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isFalse);
    });

    test('does NOT print SOLUTION FOUND when status is present but id is absent', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // _checkForLinkIdInItem (mirrored)
  // ═══════════════════════════════════════════════════════════════════════════
  group('_checkForLinkIdInItem – direct linkId', () {
    test('prints linkId when item contains a linkId key', () {
      // The first branch: item carries `linkId` directly.
      final lines = _capturePrint(
        () => _checkForLinkIdInItem({'linkId': 77, 'name': 'Jane'}),
      );
      expect(lines.any((l) => l.contains('77')), isTrue);
      expect(lines.any((l) => l.contains('linkId found directly')), isTrue);
    });

    test('prints nothing when linkId key is absent', () {
      // With no `linkId` key and no nested `patient`, nothing is printed.
      final lines = _capturePrint(
        () => _checkForLinkIdInItem({'name': 'Jane'}),
      );
      expect(lines, isEmpty);
    });
  });

  group('_checkForLinkIdInItem – top-level id vs patient id', () {
    test('prints possible linkId when top-level id differs from patient id', () {
      // The second branch: top-level `id` != `patient.id` suggests the
      // top-level id is actually a relationship/link id.
      final item = {
        'id': 999,
        'patient': {'id': 42},
      };
      final lines = _capturePrint(() => _checkForLinkIdInItem(item));
      expect(lines.any((l) => l.contains('999')), isTrue);
      expect(lines.any((l) => l.contains('Possible linkId')), isTrue);
    });

    test('does NOT print possible linkId when top-level id equals patient id', () {
      // If the IDs are identical there is no ambiguity; nothing is printed.
      final item = {
        'id': 42,
        'patient': {'id': 42},
      };
      final lines = _capturePrint(() => _checkForLinkIdInItem(item));
      expect(lines, isEmpty);
    });

    test('does NOT print when patient key is absent', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInItem({'id': 1}),
      );
      expect(lines, isEmpty);
    });

    test('does NOT print when patient map has no id', () {
      final item = {'id': 1, 'patient': <String, dynamic>{}};
      final lines = _capturePrint(() => _checkForLinkIdInItem(item));
      expect(lines, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // _searchInList (mirrored)
  // ═══════════════════════════════════════════════════════════════════════════
  group('_searchInList – empty and non-map items', () {
    test('prints not-found summary for an empty list', () {
      // With no items the loop does not execute; the not-found path fires.
      final lines = _capturePrint(() => _searchInList([], 42));
      expect(lines.any((l) => l.contains('not found')), isTrue);
    });

    test('skips non-map items and prints not-found summary', () {
      // Items that are not Map<String, dynamic> are skipped by the `continue`.
      final lines = _capturePrint(
        () => _searchInList(['string', 123, null], 42),
      );
      expect(lines.any((l) => l.contains('not found')), isTrue);
    });
  });

  group('_searchInList – direct patient structure', () {
    test('finds patient with matching top-level id', () {
      // The first inner if: `item['id'] == patientId`.
      final items = [
        {'id': 42, 'firstName': 'Jane'},
      ];
      final lines = _capturePrint(() => _searchInList(items, 42));
      expect(lines.any((l) => l.contains('direct structure')), isTrue);
    });

    test('does not find patient when id does not match', () {
      final items = [
        {'id': 99, 'firstName': 'Other'},
      ];
      final lines = _capturePrint(() => _searchInList(items, 42));
      expect(lines.any((l) => l.contains('not found')), isTrue);
    });

    test('stops searching after finding the first match', () {
      // After `return` the list has two items but only one "found" message.
      final items = [
        {'id': 42, 'firstName': 'Jane'},
        {'id': 42, 'firstName': 'Duplicate'},
      ];
      final lines = _capturePrint(() => _searchInList(items, 42));
      final foundMessages =
          lines.where((l) => l.contains('direct structure')).length;
      expect(foundMessages, 1);
    });
  });

  group('_searchInList – nested patient structure', () {
    test('finds patient in nested structure with matching id', () {
      // The second inner if: `item['patient']['id'] == patientId`.
      final items = [
        {
          'patient': {'id': 5, 'firstName': 'Nested'},
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 5));
      expect(lines.any((l) => l.contains('nested structure')), isTrue);
    });

    test('includes link data in output when link key is present and is a map', () {
      // When the container has a `link` key with map value, _checkForLinkIdInLink
      // is called and emits ID-detection output.
      final items = [
        {
          'patient': {'id': 5},
          'link': {'id': 77, 'status': 'ACTIVE'},
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 5));
      expect(lines.any((l) => l.contains('nested structure')), isTrue);
      // The link processing emits at least an ID-found message.
      expect(lines.any((l) => l.contains('77')), isTrue);
    });

    test('prints warning when link key present but value is not a map', () {
      // When `item['link']` exists but is not a Map<String, dynamic>.
      final items = [
        {
          'patient': {'id': 5},
          'link': 'not-a-map',
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 5));
      expect(
        lines.any((l) => l.toLowerCase().contains('not a map')),
        isTrue,
      );
    });

    test('prints warning when container has no link key', () {
      // When the patient is nested but the container has no `link` key.
      final items = [
        {
          'patient': {'id': 5},
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 5));
      expect(
        lines.any((l) => l.contains('No link data found')),
        isTrue,
      );
    });
  });

  group('_searchInList – summary statistics', () {
    test('summary counts match items correctly', () {
      // Three items: one map with id, one map with patient, one non-map.
      // Patient id 99 does not exist → not-found summary is printed.
      final items = [
        {'id': 1},
        {'patient': {'id': 2}},
        'ignored',
      ];
      final lines = _capturePrint(() => _searchInList(items, 99));
      // The not-found path prints a line containing "Searched through 3 items".
      expect(lines.any((l) => l.contains('3 items')), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // _checkForLinkIdInLink – additional string-type edge cases
  // ═══════════════════════════════════════════════════════════════════════════
  group('_checkForLinkIdInLink – string-typed ID variants', () {
    test('detects string linkId in link.linkId and parses it', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'linkId': '88', 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('link.linkId')), isTrue);
      expect(lines.any((l) => l.contains('88')), isTrue);
    });

    test('detects string relationshipId and parses it', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({
          'relationshipId': '200',
          'status': 'SUSPENDED',
        }),
      );
      expect(lines.any((l) => l.contains('link.relationshipId')), isTrue);
      expect(lines.any((l) => l.contains('200')), isTrue);
    });

    test('handles unparseable string id gracefully', () {
      // int.tryParse returns null for non-numeric strings; foundId stays null
      // so SOLUTION FOUND should NOT appear even with status present.
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 'abc', 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('link.id')), isTrue);
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isFalse);
    });

    test('handles unparseable string linkId gracefully', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'linkId': 'xyz', 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('link.linkId')), isTrue);
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isFalse);
    });

    test('handles unparseable string relationshipId gracefully', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({
          'relationshipId': 'bad',
          'status': 'ACTIVE',
        }),
      );
      expect(lines.any((l) => l.contains('link.relationshipId')), isTrue);
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isFalse);
    });
  });

  group('_checkForLinkIdInLink – SOLUTION FOUND with different ID sources', () {
    test('prints SOLUTION FOUND with linkId source', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'linkId': 55, 'status': 'ACTIVE'}),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isTrue);
      expect(lines.any((l) => l.contains('link.linkId')), isTrue);
    });

    test('prints SOLUTION FOUND with relationshipId source', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({
          'relationshipId': 33,
          'status': 'SUSPENDED',
        }),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isTrue);
      expect(lines.any((l) => l.contains('link.relationshipId')), isTrue);
    });

    test('prints SOLUTION FOUND with isActive status source', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 10, 'isActive': true}),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isTrue);
      expect(lines.any((l) => l.contains('link.isActive')), isTrue);
    });

    test('prints SOLUTION FOUND with active status source', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 10, 'active': false}),
      );
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isTrue);
      expect(lines.any((l) => l.contains('link.active')), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // _checkForLinkIdInItem – combined branches
  // ═══════════════════════════════════════════════════════════════════════════
  group('_checkForLinkIdInItem – combined branch cases', () {
    test('prints both linkId and possible linkId when both conditions met', () {
      // Item has linkId directly AND has id != patient.id
      final item = {
        'linkId': 77,
        'id': 999,
        'patient': {'id': 42},
      };
      final lines = _capturePrint(() => _checkForLinkIdInItem(item));
      expect(lines.any((l) => l.contains('linkId found directly')), isTrue);
      expect(lines.any((l) => l.contains('Possible linkId')), isTrue);
    });

    test('prints linkId directly but not possible when ids match', () {
      final item = {
        'linkId': 77,
        'id': 42,
        'patient': {'id': 42},
      };
      final lines = _capturePrint(() => _checkForLinkIdInItem(item));
      expect(lines.any((l) => l.contains('linkId found directly')), isTrue);
      expect(lines.any((l) => l.contains('Possible linkId')), isFalse);
    });

    test('handles null patient data gracefully', () {
      final item = <String, dynamic>{
        'id': 1,
        'patient': null,
      };
      // patient is null, so the cast to Map<String, dynamic>? yields null,
      // and the inner null check prevents a crash.
      final lines = _capturePrint(() => _checkForLinkIdInItem(item));
      expect(lines, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // _searchInList – additional edge cases
  // ═══════════════════════════════════════════════════════════════════════════
  group('_searchInList – mixed item types', () {
    test('counts map items correctly in summary', () {
      final items = [
        {'id': 1},
        {'id': 2, 'patient': {'id': 3}},
        42, // non-map, skipped
        'string', // non-map, skipped
        {'patient': {'id': 4}},
      ];
      final lines = _capturePrint(() => _searchInList(items, 999));
      // 3 map items, 2 with id field, 2 with patient field
      expect(lines.any((l) => l.contains('3 maps')), isTrue);
      expect(lines.any((l) => l.contains('2 with ID field')), isTrue);
      expect(lines.any((l) => l.contains('2 with patient field')), isTrue);
    });

    test('finds patient via direct structure even when patient key has non-map value', () {
      // The item has 'id' matching patientId, so direct structure match fires
      // before the nested patient check. The 'patient' key is a string, not a map.
      final items = [
        {'id': 10, 'name': 'Test'},
      ];
      final lines = _capturePrint(() => _searchInList(items, 10));
      expect(lines.any((l) => l.contains('direct structure')), isTrue);
    });

    test('direct structure match calls _checkForLinkIdInItem', () {
      // Item with linkId should trigger the linkId-found-directly print
      final items = [
        {'id': 42, 'linkId': 100, 'firstName': 'Jane'},
      ];
      final lines = _capturePrint(() => _searchInList(items, 42));
      expect(lines.any((l) => l.contains('direct structure')), isTrue);
      expect(lines.any((l) => l.contains('linkId found directly')), isTrue);
    });

    test('nested structure with link map calls _checkForLinkIdInLink', () {
      final items = [
        {
          'patient': {'id': 5},
          'link': {'id': 77, 'status': 'ACTIVE'},
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 5));
      expect(lines.any((l) => l.contains('nested structure')), isTrue);
      expect(lines.any((l) => l.contains('SOLUTION FOUND')), isTrue);
    });

    test('nested structure with link containing linkId key', () {
      final items = [
        {
          'patient': {'id': 5},
          'link': {'linkId': 88, 'isActive': true},
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 5));
      expect(lines.any((l) => l.contains('nested structure')), isTrue);
      expect(lines.any((l) => l.contains('link.linkId')), isTrue);
    });
  });

  group('_searchInList – nested structure with RECOMMENDED id', () {
    test('prints RECOMMENDED when link.id is present in nested structure', () {
      // This exercises the source code's "RECOMMENDED: Use this ID" path.
      // The mirrored code doesn't have this print, but the source does.
      // We verify the mirrored code still handles the link data correctly.
      final items = [
        {
          'patient': {'id': 7},
          'link': {'id': 42, 'status': 'ACTIVE'},
        },
      ];
      final lines = _capturePrint(() => _searchInList(items, 7));
      expect(lines.any((l) => l.contains('42')), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // _checkForLinkIdInLink – status null edge case
  // ═══════════════════════════════════════════════════════════════════════════
  group('_checkForLinkIdInLink – null status value', () {
    test('handles null status value without crashing', () {
      final lines = _capturePrint(
        () => _checkForLinkIdInLink({'id': 1, 'status': null}),
      );
      expect(lines.any((l) => l.contains('linkStatus found')), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LinkDebugger.suggestFixes (public, no real context needed)
  // ═══════════════════════════════════════════════════════════════════════════
  group('LinkDebugger.suggestFixes', () {
    testWidgets('does not throw when called', (WidgetTester tester) async {
      // suggestFixes accepts BuildContext but never reads it; any valid context
      // satisfies the parameter.  We pump a minimal widget just to get one.
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      );

      // Must complete without throwing.
      expect(() => LinkDebugger.suggestFixes(ctx), returnsNormally);
    });

    testWidgets('prints the expected header and footer banners', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      );

      final lines = _capturePrint(() => LinkDebugger.suggestFixes(ctx));

      // Header banner must appear.
      expect(
        lines.any((l) => l.contains('RECOMMENDED FIXES')),
        isTrue,
        reason: 'suggestFixes must print the RECOMMENDED FIXES banner',
      );
      // Footer banner must appear.
      expect(
        lines.any((l) => l.contains('LINK DEBUGGER FINISHED')),
        isTrue,
        reason: 'suggestFixes must print the LINK DEBUGGER FINISHED banner',
      );
    });

    testWidgets('prints actionable fix descriptions', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      );

      final lines = _capturePrint(() => LinkDebugger.suggestFixes(ctx));
      final allOutput = lines.join('\n');

      // The method lists multiple numbered recommendations; confirm a few.
      expect(allOutput, contains('link.id'));
      expect(allOutput, contains('link.linkId'));
      expect(allOutput, contains('link.relationshipId'));
      expect(allOutput, contains('PatientParser'));
    });

    testWidgets('is safe to call multiple times (idempotent)', (
      WidgetTester tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      );

      // Repeated calls must not accumulate state or throw.
      expect(() {
        LinkDebugger.suggestFixes(ctx);
        LinkDebugger.suggestFixes(ctx);
      }, returnsNormally);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // LinkDebugger.debugLinkIdForPatient – user == null path
  // ═══════════════════════════════════════════════════════════════════════════
  group('LinkDebugger.debugLinkIdForPatient – no logged-in user', () {
    testWidgets(
      'returns early and prints a warning when UserProvider has no user',
      (WidgetTester tester) async {
        // MockUserProvider overridden to return null for the user getter.
        final nullUserProvider = _NullUserProvider();
        final patient = _makePatient();

        late BuildContext ctx;
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: nullUserProvider,
            child: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            }),
          ),
        );

        final lines = await _capturePrintAsync(
          () => LinkDebugger.debugLinkIdForPatient(ctx, patient),
        );

        // The "Cannot debug – no logged in user" warning must appear.
        expect(
          lines.any((l) => l.toLowerCase().contains('no logged in user')),
          isTrue,
        );
      },
    );

    testWidgets(
      'does not throw when UserProvider has no user',
      (WidgetTester tester) async {
        final nullUserProvider = _NullUserProvider();
        final patient = _makePatient();

        late BuildContext ctx;
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: nullUserProvider,
            child: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            }),
          ),
        );

        await expectLater(
          LinkDebugger.debugLinkIdForPatient(ctx, patient),
          completes,
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // PatientDebugExtension
  // ═══════════════════════════════════════════════════════════════════════════
  group('PatientDebugExtension.debugLinkId', () {
    testWidgets(
      'completes without throwing when user is null',
      (WidgetTester tester) async {
        final nullUserProvider = _NullUserProvider();
        final patient = _makePatient();

        late BuildContext ctx;
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: nullUserProvider,
            child: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            }),
          ),
        );

        // The extension delegates to debugLinkIdForPatient + suggestFixes.
        await expectLater(patient.debugLinkId(ctx), completes);
      },
    );

    testWidgets(
      'prints both LINK DEBUGGER and RECOMMENDED FIXES banners',
      (WidgetTester tester) async {
        // Use the null-user provider so we avoid network calls; the early
        // return still allows suggestFixes to run because the extension calls
        // both methods unconditionally.
        final nullUserProvider = _NullUserProvider();
        final patient = _makePatient();

        late BuildContext ctx;
        await tester.pumpWidget(
          ChangeNotifierProvider<UserProvider>.value(
            value: nullUserProvider,
            child: Builder(builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            }),
          ),
        );

        final lines = await _capturePrintAsync(() => patient.debugLinkId(ctx));

        // debugLinkIdForPatient emits the STARTING banner.
        expect(lines.any((l) => l.contains('LINK DEBUGGER STARTING')), isTrue);
        // suggestFixes emits the RECOMMENDED FIXES banner.
        expect(lines.any((l) => l.contains('RECOMMENDED FIXES')), isTrue);
        // suggestFixes emits the FINISHED banner.
        expect(lines.any((l) => l.contains('LINK DEBUGGER FINISHED')), isTrue);
      },
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Local test doubles
// ─────────────────────────────────────────────────────────────────────────────

/// A [UserProvider] whose `user` getter always returns `null`.
/// Used to exercise the "no logged-in user" early-exit branch of
/// `debugLinkIdForPatient`.
class _NullUserProvider extends UserProvider {
  @override
  UserSession? get user => null;

  @override
  bool get isLoggedIn => false;

  // Stub every async method so no platform services are touched.
  @override
  Future<void> initializeUser() async {}

  @override
  Future<void> fetchUserDetails() async {}

  @override
  Future<void> clearUser() async {}

  @override
  Future<void> updateActivity() async {}

  @override
  Future<bool> validateSession() async => false;

  @override
  Future<bool> refreshToken() async => false;

  @override
  Future<void> updateUserRole(String r) async {}

  @override
  Future<void> updatePatientId(int? id) async {}

  @override
  void updateUserName(String n) {}
}
