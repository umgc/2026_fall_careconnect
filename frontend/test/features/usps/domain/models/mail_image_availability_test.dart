import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/domain/models/mail_image_availability.dart';
import 'package:care_connect_app/features/usps/domain/models/mail_piece.dart';
import 'package:care_connect_app/features/usps/domain/models/action_links.dart';

void main() {
  group('MailImageClassifier', () {
    test('null / empty → missing normal state', () {
      expect(
        MailImageClassifier.classify(null),
        MailImageAvailability.missing,
      );
      expect(
        MailImageClassifier.classify('   '),
        MailImageAvailability.missing,
      );
      expect(MailImageClassifier.classify(null).isMissingNormalState, isTrue);
      expect(MailImageClassifier.hasDisplayableImage(null), isFalse);
    });

    test('unresolved cid is normal, not displayable', () {
      final availability = MailImageClassifier.classify('cid:piece1');
      expect(availability, MailImageAvailability.unresolvedCid);
      expect(availability.isMissingNormalState, isTrue);
      expect(availability.isDisplayable, isFalse);
    });

    test('http(s) and data URLs are displayable', () {
      expect(
        MailImageClassifier.classify('https://example.com/mail.jpg'),
        MailImageAvailability.available,
      );
      expect(
        MailImageClassifier.classify(
          'data:image/png;base64,iVBORw0KGgo=',
        ),
        MailImageAvailability.available,
      );
    });

    test('backend placeholder summary marks stub as normal', () {
      final availability = MailImageClassifier.classify(
        'https://example.com/ignored.png',
        summary: 'Image not available',
      );
      expect(availability, MailImageAvailability.backendPlaceholder);
      expect(MailImageClassifier.hasDisplayableImage(
        'https://example.com/ignored.png',
        summary: 'Image not available',
      ), isFalse);
    });

    test('known backend SVG data URI is placeholder normal state', () {
      final availability = MailImageClassifier.classify(
        '${MailImageClassifier.backendPlaceholderDataUriPrefix}AAAA',
      );
      expect(availability, MailImageAvailability.backendPlaceholder);
    });
  });

  group('MailPiece missing-image helpers', () {
    test('hasDisplayableImage false when image absent', () {
      const piece = MailPiece(
        id: 'm1',
        sender: 'CVS Pharmacy',
        summary: 'Prescription notice',
        actions: ActionLinks(),
      );
      expect(piece.hasDisplayableImage, isFalse);
      expect(piece.isMissingImageNormalState, isTrue);
    });

    test('hasDisplayableImage true for https scan', () {
      const piece = MailPiece(
        id: 'm2',
        imageDataUrl: 'https://usps.example/scan.jpg',
        actions: ActionLinks(),
      );
      expect(piece.hasDisplayableImage, isTrue);
      expect(piece.isMissingImageNormalState, isFalse);
    });
  });
}
