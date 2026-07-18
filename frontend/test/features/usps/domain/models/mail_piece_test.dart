// Comprehensive tests for MailPiece model.

import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/domain/models/action_links.dart';
import 'package:care_connect_app/features/usps/domain/models/mail_piece.dart';

void main() {
  group('MailPiece', () {
    test('constructor with only required fields', () {
      const piece = MailPiece(id: 'MP-001', actions: ActionLinks());
      expect(piece.id, 'MP-001');
      expect(piece.sender, isNull);
      expect(piece.summary, isNull);
      expect(piece.imageDataUrl, isNull);
      expect(piece.dateIso, isNull);
      expect(piece.actions.track, isNull);
      expect(piece.hasDisplayableImage, isFalse);
      expect(piece.isMissingImageNormalState, isTrue);
    });

    test('constructor with all fields populated', () {
      const actions = ActionLinks(
        track: 'https://track.usps.com/mp1',
        redelivery: 'https://redelivery.usps.com/mp1',
        dashboard: 'https://dash.usps.com',
      );
      const piece = MailPiece(
        id: 'MP-002',
        sender: 'IRS',
        summary: 'Tax refund notice',
        imageDataUrl: 'data:image/jpeg;base64,/9j/4AAQ',
        dateIso: '2026-03-14',
        actions: actions,
      );
      expect(piece.id, 'MP-002');
      expect(piece.sender, 'IRS');
      expect(piece.summary, 'Tax refund notice');
      expect(piece.imageDataUrl, startsWith('data:image/jpeg'));
      expect(piece.dateIso, '2026-03-14');
      expect(piece.actions.track, 'https://track.usps.com/mp1');
      expect(piece.actions.redelivery, 'https://redelivery.usps.com/mp1');
      expect(piece.actions.dashboard, 'https://dash.usps.com');
    });

    test('id can be any string value', () {
      const piece = MailPiece(id: '', actions: ActionLinks());
      expect(piece.id, '');
    });

    test('sender can be empty string', () {
      const piece = MailPiece(id: 'x', sender: '', actions: ActionLinks());
      expect(piece.sender, '');
    });

    test('summary can be empty string', () {
      const piece = MailPiece(id: 'x', summary: '', actions: ActionLinks());
      expect(piece.summary, '');
    });

    test('imageDataUrl stores base64 data URI', () {
      const dataUrl = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      const piece = MailPiece(
        id: 'img-test',
        imageDataUrl: dataUrl,
        actions: ActionLinks(),
      );
      expect(piece.imageDataUrl, dataUrl);
      expect(piece.imageDataUrl, startsWith('data:image/png'));
    });

    test('dateIso stores ISO-formatted date string', () {
      const piece = MailPiece(
        id: 'date-test',
        dateIso: '2026-01-15T10:30:00Z',
        actions: ActionLinks(),
      );
      expect(piece.dateIso, contains('2026-01-15'));
    });

    test('actions field is always accessible even with empty ActionLinks', () {
      const piece = MailPiece(id: 'act-test', actions: ActionLinks());
      expect(piece.actions, isNotNull);
      expect(piece.actions.track, isNull);
      expect(piece.actions.redelivery, isNull);
      expect(piece.actions.dashboard, isNull);
    });

    test('can be used as const', () {
      const a = MailPiece(id: 'const-1', actions: ActionLinks());
      const b = MailPiece(id: 'const-1', actions: ActionLinks());
      expect(identical(a, b), isTrue);
    });

    test('multiple MailPieces with different ids are not identical', () {
      const a = MailPiece(id: 'a', actions: ActionLinks());
      const b = MailPiece(id: 'b', actions: ActionLinks());
      expect(identical(a, b), isFalse);
    });

    test('sender with special characters', () {
      const piece = MailPiece(
        id: 'sp',
        sender: "O'Reilly & Associates, Inc.",
        actions: ActionLinks(),
      );
      expect(piece.sender, contains("O'Reilly"));
      expect(piece.sender, contains('&'));
    });

    test('summary with multiline content', () {
      const piece = MailPiece(
        id: 'ml',
        summary: 'Line 1\nLine 2\nLine 3',
        actions: ActionLinks(),
      );
      expect(piece.summary, contains('\n'));
    });
  });
}
