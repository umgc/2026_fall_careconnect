// IdentityConflictService: until the backend endpoint exists it must never
// report a save that didn't happen, and the sample conflict is opt-in only.

import 'package:care_connect_app/features/health/health_data/models/identity_conflict.dart';
import 'package:care_connect_app/features/health/health_data/services/identity_conflict_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('with the demo data off (the default)', () {
    final service = IdentityConflictService(useMock: false);

    test('there is nothing pending', () async {
      expect(await service.fetchPending(), isEmpty);
    });

    test('a choice is never reported as saved, because nothing is saved yet', () async {
      expect(await service.resolve(1, accepted: true), isFalse);
      expect(await service.resolve(1, accepted: false), isFalse);
    });
  });

  test('the default build has the demo data off', () {
    expect(IdentityConflictService().useMock, isFalse);
  });

  group('with the demo data on (CARECONNECT_DOB_MOCK=true)', () {
    final service = IdentityConflictService(useMock: true);

    test('one pending date-of-birth conflict is offered, from a named source', () async {
      final pending = await service.fetchPending();

      expect(pending, hasLength(1));
      final conflict = pending.single;
      expect(conflict.isDob, isTrue);
      expect(conflict.isPending, isTrue);
      expect(conflict.status, ConflictStatus.pending);
      expect(conflict.canonicalValueBefore, isNot(conflict.incomingValue));
      expect(conflict.incomingSourceLabel, isNotEmpty);
    });

    test('resolving succeeds either way', () async {
      expect(await service.resolve(1, accepted: true), isTrue);
      expect(await service.resolve(1, accepted: false), isTrue);
    });
  });
}
