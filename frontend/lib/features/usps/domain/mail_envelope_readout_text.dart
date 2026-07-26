/// Builds spoken envelope-level mail text for ADA readout (Task 3.14.10 / #127).
///
/// Uses Informed Delivery metadata already on the wire — sender and summary —
/// not full OCR blobs.
String buildMailEnvelopeReadoutText({
  String? sender,
  String? summary,
  bool includeMissingImageNote = false,
}) {
  final cleanedSender = _cleanField(sender, stripPrefixes: _senderPrefixes);
  final cleanedSummary = _cleanField(summary, stripPrefixes: _summaryPrefixes);

  final fromPart = cleanedSender.isEmpty ? 'Unknown sender' : cleanedSender;
  final summaryPart = cleanedSummary.isEmpty
      ? 'No envelope summary available'
      : cleanedSummary;

  final buffer = StringBuffer('From: $fromPart. $summaryPart.');
  if (includeMissingImageNote) {
    buffer.write(
      ' No envelope image is available; showing details from mail metadata.',
    );
  }
  return buffer.toString();
}

const List<String> _senderPrefixes = ['sender:', 'from:'];
const List<String> _summaryPrefixes = ['summary:', 'subject:'];

String _cleanField(String? value, {required List<String> stripPrefixes}) {
  if (value == null) return '';
  var text = value.trim();
  if (text.isEmpty) return '';

  final lower = text.toLowerCase();
  for (final prefix in stripPrefixes) {
    if (lower.startsWith(prefix)) {
      text = text.substring(prefix.length).trim();
      break;
    }
  }

  // Backend stub copy is not useful envelope content.
  if (text.toLowerCase() == 'image not available') {
    return '';
  }
  return text;
}
