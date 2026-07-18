// Tests for the invite acceptance handoff (issue #75): InvitePreview parsing
// and the PendingInvite holder. Both are pure Dart, no network or widgets.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invite_accept/models/invite_preview.dart';
import 'package:care_connect_app/features/invite_accept/services/pending_invite.dart';

void main() {
  group('InvitePreview.fromJson', () {
    test('parses a valid preview with full context', () {
      final json = <String, dynamic>{
        'valid': true,
        'status': 'VALID',
        'nextAction': 'ACCEPT',
        'linkId': 5,
        'linkType': 'PERMANENT',
        'inviterName': 'Jane Doe',
        'patientName': 'John Smith',
        'inviteReason': 'Please help with Dad',
        'invitedEmail': 'bob@test.com',
        'expiresAt': '2026-07-10T12:00:00',
      };

      final p = InvitePreview.fromJson(json);

      expect(p.valid, isTrue);
      expect(p.status, 'VALID');
      expect(p.nextAction, 'ACCEPT');
      expect(p.linkId, 5);
      expect(p.inviterName, 'Jane Doe');
      expect(p.patientName, 'John Smith');
      expect(p.expiresAt, isNotNull);
    });

    test('parses a non-valid preview with null context (non-enumerating)', () {
      final json = <String, dynamic>{
        'valid': false,
        'status': 'EXPIRED',
        'nextAction': 'REQUEST_NEW',
        'linkId': null,
        'linkType': null,
        'inviterName': null,
        'patientName': null,
        'inviteReason': null,
        'invitedEmail': null,
        'expiresAt': null,
      };

      final p = InvitePreview.fromJson(json);

      expect(p.valid, isFalse);
      expect(p.status, 'EXPIRED');
      expect(p.nextAction, 'REQUEST_NEW');
      expect(p.linkId, isNull);
      expect(p.inviterName, isNull);
    });

    test('falls back to safe defaults on empty json', () {
      final p = InvitePreview.fromJson(<String, dynamic>{});
      expect(p.valid, isFalse);
      expect(p.status, 'INVALID');
      expect(p.nextAction, 'NONE');
    });

    test('contextSummary includes inviter and reason when present', () {
      final p = InvitePreview.fromJson(<String, dynamic>{
        'valid': true,
        'status': 'VALID',
        'nextAction': 'ACCEPT',
        'inviterName': 'Jane',
        'patientName': 'John',
        'inviteReason': 'Join us',
      });
      expect(p.contextSummary, contains('Jane'));
      expect(p.contextSummary, contains('John'));
      expect(p.contextSummary, contains('Join us'));
    });
  });

  group('PendingInvite', () {
    setUp(PendingInvite.clear);

    test('starts empty', () {
      expect(PendingInvite.hasPending, isFalse);
      expect(PendingInvite.token, isNull);
    });

    test('set then read', () {
      PendingInvite.set('abc123');
      expect(PendingInvite.hasPending, isTrue);
      expect(PendingInvite.token, 'abc123');
    });

    test('take consumes and clears', () {
      PendingInvite.set('abc123');
      final taken = PendingInvite.take();
      expect(taken, 'abc123');
      expect(PendingInvite.hasPending, isFalse);
      expect(PendingInvite.token, isNull);
    });

    test('clear empties without returning', () {
      PendingInvite.set('abc123');
      PendingInvite.clear();
      expect(PendingInvite.hasPending, isFalse);
    });

    test('empty string is not considered pending', () {
      PendingInvite.set('');
      expect(PendingInvite.hasPending, isFalse);
    });
  });
}
