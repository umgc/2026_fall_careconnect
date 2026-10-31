import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/usps/domain/models/mail_image_availability.dart';
import 'package:care_connect_app/features/usps/presentation/widgets/mail_piece_image.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MailPieceImage – missing-image normal state', () {
    testWidgets('compact list leading shows calm mail icon, not error text',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MailPieceImage(
            imageRef: null,
            sender: 'CVS Pharmacy',
            summary: 'Prescription ready',
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.missingNormalKey), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline), findsOneWidget);
      expect(find.textContaining('error', findRichText: true), findsNothing);
      expect(find.text('No envelope image'), findsNothing);
    });

    testWidgets('expanded detail shows metadata-first normal messaging',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MailPieceImage(
            imageRef: null,
            expanded: true,
            width: 260,
            height: 168,
            sender: 'Hospital Billing',
            summary: 'Statement available',
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.missingNormalKey), findsOneWidget);
      expect(find.text('No envelope image'), findsOneWidget);
      expect(find.text('Showing details from mail metadata'), findsOneWidget);
      expect(find.text('Hospital Billing'), findsOneWidget);
      expect(find.text('Statement available'), findsOneWidget);
    });

    testWidgets('unresolved cid uses missing normal state', (tester) async {
      await tester.pumpWidget(
        _wrap(const MailPieceImage(imageRef: 'cid:mailpiece-1')),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.missingNormalKey), findsOneWidget);
      expect(find.byKey(MailPieceImage.availableKey), findsNothing);
    });

    testWidgets('backend placeholder summary hides stub as normal state',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MailPieceImage(
            imageRef:
                'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0nMTIwJyBoZWlnaHQ9JzgwJ',
            summary: 'Image not available',
            expanded: true,
            width: 260,
            height: 168,
            sender: 'USPS Mail Piece',
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.missingNormalKey), findsOneWidget);
      expect(find.text('No envelope image'), findsOneWidget);
      // Stub summary must not be shown as content.
      expect(find.text('Image not available'), findsNothing);
    });

    testWidgets('displayable https ref uses available key', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MailPieceImage(
            imageRef: 'https://example.com/envelope.jpg',
            width: 48,
            height: 32,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.availableKey), findsOneWidget);
    });

    testWidgets('raster data URI renders an in-memory image', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MailPieceImage(
            imageRef: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'
                'CAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.availableKey), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('undecodable data URI falls back to the normal state',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const MailPieceImage(imageRef: 'data:image/png;base64,%%%')),
      );
      await tester.pump();

      expect(find.byKey(MailPieceImage.missingNormalKey), findsOneWidget);
    });

    testWidgets('svg stub containing "image not available" is a placeholder',
        (tester) async {
      // base64 of "<svg>Image not available</svg>"
      const ref = 'data:image/svg+xml;base64,'
          'PHN2Zz5JbWFnZSBub3QgYXZhaWxhYmxlPC9zdmc+';
      expect(MailImageClassifier.hasDisplayableImage(ref), isFalse);
      expect(
        MailImageClassifier.hasDisplayableImage('https://example.com/a.png'),
        isTrue,
      );
      expect(
        MailImageClassifier.classify('data:image/svg+xml;base64,%%%'),
        MailImageAvailability.available,
      );
      await tester.pumpWidget(_wrap(const MailPieceImage(imageRef: ref)));
      await tester.pump();
      expect(find.byKey(MailPieceImage.missingNormalKey), findsOneWidget);
    });
  });

  group('MailMetadataOnlyBadge', () {
    testWidgets('renders Metadata chip', (tester) async {
      await tester.pumpWidget(_wrap(const MailMetadataOnlyBadge()));
      await tester.pump();

      expect(find.byKey(MailMetadataOnlyBadge.badgeKey), findsOneWidget);
      expect(find.text('Metadata'), findsOneWidget);
    });
  });
}
