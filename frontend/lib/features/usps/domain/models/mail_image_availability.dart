import 'dart:convert';

/// How a mailpiece image reference should be treated in the UI.
///
/// Missing / unresolved / backend-placeholder images are **normal** states:
/// the mail record remains useful from sender/summary metadata (TC-E-USPS-001 /
/// Task 3.14.8). They must not be rendered as load failures.
enum MailImageAvailability {
  /// Displayable http(s) or raster data: URL.
  available,

  /// Null/empty image — expected when Informed Delivery only has metadata.
  missing,

  /// Unresolved `cid:` reference (inline part not resolved client-side).
  unresolvedCid,

  /// Backend SVG stub used when a slot exists but no scan was attached.
  backendPlaceholder,
}

extension MailImageAvailabilityX on MailImageAvailability {
  bool get isDisplayable => this == MailImageAvailability.available;

  /// True when the UI should use the calm "no envelope image" normal state.
  bool get isMissingNormalState =>
      this == MailImageAvailability.missing ||
      this == MailImageAvailability.unresolvedCid ||
      this == MailImageAvailability.backendPlaceholder;
}

/// Classifies a mailpiece image URL / data URI for UI rendering.
class MailImageClassifier {
  MailImageClassifier._();

  /// Known USPS digest backend stub (GmailParser.PLACEHOLDER_IMAGE).
  static const String backendPlaceholderDataUriPrefix =
      'data:image/svg+xml;base64,PHN2ZyB3aWR0aD0nMTIwJyBoZWlnaHQ9JzgwJ';

  static MailImageAvailability classify(
    String? imageRef, {
    String? summary,
  }) {
    final trimmedSummary = summary?.trim().toLowerCase();
    if (trimmedSummary == 'image not available') {
      return MailImageAvailability.backendPlaceholder;
    }

    if (imageRef == null || imageRef.trim().isEmpty) {
      return MailImageAvailability.missing;
    }

    final ref = imageRef.trim();
    if (ref.toLowerCase().startsWith('cid:')) {
      return MailImageAvailability.unresolvedCid;
    }

    if (_looksLikeBackendPlaceholder(ref)) {
      return MailImageAvailability.backendPlaceholder;
    }

    if (ref.startsWith('data:') ||
        ref.startsWith('http://') ||
        ref.startsWith('https://')) {
      return MailImageAvailability.available;
    }

    return MailImageAvailability.missing;
  }

  static bool hasDisplayableImage(String? imageRef, {String? summary}) =>
      classify(imageRef, summary: summary).isDisplayable;

  static bool _looksLikeBackendPlaceholder(String ref) {
    final lower = ref.toLowerCase();
    if (lower.startsWith(backendPlaceholderDataUriPrefix.toLowerCase())) {
      return true;
    }
    if (!lower.startsWith('data:image/svg+xml')) {
      return false;
    }
    try {
      final b64 = ref.split(',').last;
      final decoded = utf8.decode(base64Decode(b64));
      return decoded.toLowerCase().contains('image not available');
    } catch (_) {
      return false;
    }
  }
}
