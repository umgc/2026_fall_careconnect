import 'package:flutter/material.dart';

/// Banner surfacing SOAP-derived clinical urgency at the top of a summary display.
///
/// ## Backend contract
///
/// The [riskLevel] input comes from the `riskLevel` field of the Bedrock
/// summary payload. Normalization lives in the backend at
/// `backend/core/src/main/java/com/careconnect/service/BedrockSentimentService.java`
/// (method `extractRiskLevel`), which coerces the raw model output to
/// exactly one of `"HIGH"`, `"MODERATE"`, or `"LOW"`. Unknown or malformed
/// values default to `"LOW"` at the backend. A `null` reaches this widget
/// when the summary payload is absent entirely — for example when the call
/// summary row's `status` is `NO_TRANSCRIPT` or `ERROR`.
///
/// The widget accepts case-insensitive input (`"high"` → HIGH) as defence
/// in depth, but the backend contract emits uppercase.
///
/// The `caregiverVisibility` field on the same payload is enforced at the
/// API / RBAC layer, not in this widget. Do not use this widget to gate
/// visibility — only urgency display.
///
/// Related backend files:
///
///  * `BedrockSentimentService.parseSummaryResponse` — payload assembly
///  * `BedrockSentimentService.extractRiskLevel` — value normalization
///  * `CallSummaryService.buildStoredSummary` — persistence wiring (PR #269)
///
/// ## Display
///
/// The banner renders differently by risk:
///
///  * `HIGH` — red strip with warning icon and prominent copy urging review.
///  * `MODERATE` — amber strip with caution icon.
///  * `LOW`, `null`, or any unrecognized value — hidden entirely
///    ([SizedBox.shrink]) so callers can drop this widget in without
///    conditional guards.
///
/// Copy is 18pt minimum per Prof. Assadullah's STML accessibility standard.
/// A [Semantics] wrapper announces the banner to screen readers with an
/// urgency-appropriate label.
///
/// Callers may override the visible text via [message]; the default copy is
/// clinically neutral and safe for both call and visit summary contexts.
///
/// Part of WBS 3.4.6.
class ClinicalUrgencyBanner extends StatelessWidget {
  /// Risk classification from the summary payload. Case-insensitive.
  final String? riskLevel;

  /// Optional override for the banner text. When null the widget renders
  /// the default copy for the resolved risk level.
  final String? message;

  const ClinicalUrgencyBanner({
    super.key,
    required this.riskLevel,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = riskLevel?.trim().toUpperCase();
    if (normalized != 'HIGH' && normalized != 'MODERATE') {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bool isHigh = normalized == 'HIGH';
    final Color background = isHigh ? cs.error : Colors.amber.shade700;
    final Color foreground = isHigh ? cs.onError : Colors.black;
    final IconData icon =
        isHigh ? Icons.warning_amber_rounded : Icons.info_outline;
    final String defaultCopy = isHigh
        ? 'High clinical risk — review recommended'
        : 'Moderate clinical concern — monitor closely';
    final String semanticsLabel =
        isHigh ? 'High clinical risk alert' : 'Moderate clinical concern';

    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, color: foreground, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message ?? defaultCopy,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}