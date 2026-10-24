// IdentityConflictService: until the backend endpoint exists it must never
// report a save that didn't happen, and the sample conflict is opt-in only.
// Test IDs TC-EHR-REC-065..069 are permanent. Never renumber, never reuse.

import 'package:care_connect_app/features/health/health_data/models/identity_conflict.dart';
import 'package:care_connect_app/features/health/health_data/services/identity_conflict_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('with the demo data off (the default)', () {
    final service = IdentityConflictService(useMock: false);

    test('TC-EHR-REC-065: there is nothing pending', () async {
      expect(await service.fetchPending(), isEmpty);
    });

    test('TC-EHR-REC-066: a choice is never reported as saved, because nothing is saved yet', () async {
      expect(await service.resolve(1, accepted: true), isFalse);
      expect(await service.resolve(1, accepted: false), isFalse);
    });
  });

  test('TC-EHR-REC-067: the default build has the demo data off', () {
    expect(IdentityConflictService().useMock, isFalse);
  });

  group('with the demo data on (CARECONNECT_DOB_MOCK=true)', () {
    final service = IdentityConflictService(useMock: true);

    test('TC-EHR-REC-068: one pending date-of-birth conflict is offered, from a named source', () async {
      final pending = await service.fetchPending();

      expect(pending, hasLength(1));
      final conflict = pending.single;
      expect(conflict.isDob, isTrue);
      expect(conflict.isPending, isTrue);
      expect(conflict.status, ConflictStatus.pending);
      expect(conflict.canonicalValueBefore, isNot(conflict.incomingValue));
      expect(conflict.incomingSourceLabel, isNotEmpty);
    });

    test('TC-EHR-REC-069: resolving succeeds either way', () async {
      expect(await service.resolve(1, accepted: true), isTrue);
      expect(await service.resolve(1, accepted: false), isTrue);
    });
  });

  group('a date of birth two connected sources disagree on (FR-XSRC-10…15)',
      () {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      IdentityConflictService.clearFound();
    });

    Future<DateTime?> report() => IdentityConflictService.reportDobDisagreement(
          current: DateTime(1980, 5, 14),
          currentSource: 'Epic',
          incoming: DateTime(1980, 5, 15),
          incomingSource: 'athenahealth',
        );

    test('is queued for the confirmation screen once, from named sources',
        () async {
      expect(await report(), isNull);
      expect(await report(), isNull);
      final pending = await IdentityConflictService(useMock: false).fetchPending();
      expect(pending, hasLength(1));
      final c = pending.single;
      expect(c.isDob, isTrue);
      expect(c.isPending, isTrue);
      expect(c.id, isNegative);
      expect(c.canonicalValueBefore, '05/14/1980');
      expect(c.incomingValue, '05/15/1980');
      expect(c.canonicalSourceLabel, 'Epic');
      expect(c.incomingSourceLabel, 'athenahealth');
    });

    for (final accepted in [true, false]) {
      test('${accepted ? 'Use new date' : 'Keep current'} is saved, leaves '
          'nothing pending, and decides the date shown', () async {
        await report();
        final service = IdentityConflictService(useMock: false);
        final id = (await service.fetchPending()).single.id;
        expect(await service.resolve(id, accepted: accepted), isTrue);
        expect(await service.fetchPending(), isEmpty);
        expect(await report(),
            accepted ? DateTime(1980, 5, 15) : DateTime(1980, 5, 14));
        expect(await service.fetchPending(), isEmpty);
      });
    }

    test('no date of birth is stored on the device', () async {
      await report();
      final service = IdentityConflictService(useMock: false);
      await service.resolve((await service.fetchPending()).single.id,
          accepted: true);
      final stored =
          (await SharedPreferences.getInstance()).getString('health_data.dob_choices')!;
      for (final text in ['1980', '05/14', '05/15', '14', '15']) {
        expect(stored.contains(text), isFalse, reason: text);
      }
    });

    test('a backend conflict id is still never reported as saved', () async {
      await report();
      expect(await IdentityConflictService(useMock: false)
          .resolve(1, accepted: true), isFalse);
    });
  });
}
