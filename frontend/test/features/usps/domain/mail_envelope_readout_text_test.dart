import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/domain/mail_envelope_readout_text.dart';

void main() {
  group('buildMailEnvelopeReadoutText', () {
    test('speaks sender and summary as envelope-level utterance', () {
      expect(
        buildMailEnvelopeReadoutText(
          sender: 'Acme Bank',
          summary: 'Monthly statement',
        ),
        'From: Acme Bank. Monthly statement.',
      );
    });

    test('strips display prefixes used by Informed Delivery tiles', () {
      expect(
        buildMailEnvelopeReadoutText(
          sender: 'Sender: Hospital Billing',
          summary: 'Summary: Lab results ready',
        ),
        'From: Hospital Billing. Lab results ready.',
      );
    });

    test('uses fallbacks when metadata is missing', () {
      expect(
        buildMailEnvelopeReadoutText(sender: null, summary: '  '),
        'From: Unknown sender. No envelope summary available.',
      );
    });

    test('ignores image-not-available stub summary', () {
      expect(
        buildMailEnvelopeReadoutText(
          sender: 'USPS Mail Piece',
          summary: 'Image not available',
        ),
        'From: USPS Mail Piece. No envelope summary available.',
      );
    });

    test('appends missing-image metadata note when requested', () {
      expect(
        buildMailEnvelopeReadoutText(
          sender: 'CVS Pharmacy',
          summary: 'Prescription ready',
          includeMissingImageNote: true,
        ),
        'From: CVS Pharmacy. Prescription ready. '
        'No envelope image is available; showing details from mail metadata.',
      );
    });
  });
}
