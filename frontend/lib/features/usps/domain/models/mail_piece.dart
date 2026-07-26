import 'package:care_connect_app/features/usps/domain/models/action_links.dart';
import 'package:care_connect_app/features/usps/domain/models/mail_image_availability.dart';

class MailPiece {
  final String id;
  final String? sender, summary, imageDataUrl, dateIso;
  final ActionLinks actions;
  const MailPiece({
    required this.id,
    this.sender,
    this.summary,
    this.imageDataUrl,
    this.dateIso,
    required this.actions,
  });

  /// True when a real envelope scan can be shown (not missing / CID / stub).
  bool get hasDisplayableImage =>
      MailImageClassifier.hasDisplayableImage(imageDataUrl, summary: summary);

  /// Missing image is a normal Informed Delivery state backed by metadata.
  bool get isMissingImageNormalState =>
      MailImageClassifier.classify(imageDataUrl, summary: summary)
          .isMissingNormalState;
}