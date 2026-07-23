// Tests for InviteResult model parsing (issue #69).
//
// InviteResult.fromJson maps the backend CreateInviteResponse (issue #53) into
// the model the QR share screen renders. These are pure, deterministic tests
// with no network or widget dependencies.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invite_share/models/invite_result.dart';

void main() {
  group('InviteResult.fromJson', () {
    test('parses a complete response', () {
      final json = <String, dynamic>{
        'tokenId': 42,
        'token': 'abc123rawtoken',
        'inviteUrl': 'https://app.careconnect.io/invite/abc123rawtoken',
        'linkId': 5,
        'linkType': 'PERMANENT',
        'status': 'PENDING',
        'expiresAt': '2026-07-10T12:00:00',
      };

      final result = InviteResult.fromJson(json);

      expect(result.tokenId, 42);
      expect(result.token, 'abc123rawtoken');
      expect(result.inviteUrl, 'https://app.careconnect.io/invite/abc123rawtoken');
      expect(result.linkId, 5);
      expect(result.linkType, 'PERMANENT');
      expect(result.status, 'PENDING');
      expect(result.expiresAt, isNotNull);
      expect(result.expiresAt!.year, 2026);
      expect(result.expiresAt!.month, 7);
      expect(result.expiresAt!.day, 10);
    });

    test('handles a null expiresAt gracefully', () {
      final json = <String, dynamic>{
        'tokenId': 1,
        'token': 't',
        'inviteUrl': 'https://x/invite/t',
        'linkId': 2,
        'linkType': 'TEMPORARY',
        'status': 'PENDING',
        'expiresAt': null,
      };

      final result = InviteResult.fromJson(json);

      expect(result.expiresAt, isNull);
      expect(result.linkType, 'TEMPORARY');
    });

    test('falls back to safe defaults on missing fields', () {
      final result = InviteResult.fromJson(<String, dynamic>{});

      expect(result.tokenId, 0);
      expect(result.token, '');
      expect(result.inviteUrl, '');
      expect(result.linkId, 0);
      expect(result.linkType, 'UNKNOWN');
      expect(result.status, 'UNKNOWN');
      expect(result.expiresAt, isNull);
    });

    test('tolerates an unparseable expiresAt string', () {
      final json = <String, dynamic>{
        'tokenId': 1,
        'token': 't',
        'inviteUrl': 'u',
        'linkId': 2,
        'linkType': 'PERMANENT',
        'status': 'PENDING',
        'expiresAt': 'not-a-date',
      };

      final result = InviteResult.fromJson(json);

      expect(result.expiresAt, isNull);
    });
  });
}
