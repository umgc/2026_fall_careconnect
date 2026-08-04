import 'package:flutter/material.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import '../../config/theme/app_theme.dart';

/// Which approved disclaimer to show.
enum DisclaimerVariant { ai, medication }

/// Accessibility-size disclaimer banner shown on AI output,
/// medication, care items (3.15.4).
///
/// Copy is localized in [AppLocalizations] (`aiDisclaimer` /
/// `medicationDisclaimer`) so it lives in the ARB
/// files and must be reviewed. 
class DisclaimerBanner extends StatelessWidget {
  /// Minimum accessible font size (WCAG 2.1)
  static const double kFontSize = 18.0;

  final DisclaimerVariant variant;

  const DisclaimerBanner({super.key, required this.variant});

  /// Disclaimer for (chat, summaries, insights)
  const DisclaimerBanner.ai({super.key}) : variant = DisclaimerVariant.ai;

  /// Disclaimer for medication / care items
  const DisclaimerBanner.medication({super.key})
      : variant = DisclaimerVariant.medication;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bool isAi = variant == DisclaimerVariant.ai;
    final String text = isAi ? l10n.aiDisclaimer : l10n.medicationDisclaimer;
    final IconData icon =
        isAi ? Icons.smart_toy_outlined : Icons.medication_outlined;

    final bool dark = Theme.of(context).brightness == Brightness.dark;

    // Amber/warning palette for a noticeable but non-alarming notice.
    final Color accent = dark ? AppTheme.warningDarkTheme : AppTheme.warning;
    final Color fg =
        dark ? AppTheme.warningDarkTheme : const Color(0xFF92400E); // amber-800
    final Color bg = accent.withValues(alpha: dark ? 0.15 : 0.12);
    final Color border = accent.withValues(alpha: 0.40);

    return Semantics(
      label: l10n.disclaimerLabel,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: kFontSize + 2, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: kFontSize,
                  height: 1.35,
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
