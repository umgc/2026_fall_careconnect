import 'dart:convert';

/// Typed view of the reviewer-facing JSON that the summary backend stores in a
/// ConfirmationItem.payload (the JSON produced by `SummarySafetyGateway.toReviewerJson`
/// on the server).
///
/// Keep these field names in sync with the backend serializer — this is Fon's own
/// contract on both ends, so it can evolve freely as long as both sides move together.
class SummaryConfirmationPayload {
  final String headline;
  final String? type; // ACTION_ITEM | CARE_INSTRUCTION | CONDITION
  final String? detail;
  final int? summaryId;

  const SummaryConfirmationPayload({
    required this.headline,
    this.type,
    this.detail,
    this.summaryId,
  });

  factory SummaryConfirmationPayload.fromJson(String raw) {
    if (raw.isEmpty) {
      return const SummaryConfirmationPayload(headline: 'Unreadable summary item');
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final headline = (map['headline'] as String?)?.trim();
      return SummaryConfirmationPayload(
        headline: (headline != null && headline.isNotEmpty)
            ? headline
            : 'Untitled summary item',
        type: map['type'] as String?,
        detail: map['detail'] as String?,
        summaryId: (map['summaryId'] as num?)?.toInt(),
      );
    } catch (_) {
      // Tolerate a malformed/legacy payload rather than crashing the whole card.
      return const SummaryConfirmationPayload(headline: 'Unreadable summary item');
    }
  }

  /// Human label for the type chip.
  String? get typeLabel => switch (type) {
        'ACTION_ITEM' => 'Action',
        'CARE_INSTRUCTION' => 'Care instruction',
        'CONDITION' => 'Condition',
        _ => type,
      };
}
