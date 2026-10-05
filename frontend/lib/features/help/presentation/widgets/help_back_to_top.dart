import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';

/// The floating shortcut retains a visible focus ring and readable label.
class HelpBackToTop extends StatefulWidget {
  const HelpBackToTop({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<HelpBackToTop> createState() => _HelpBackToTopState();
}

class _HelpBackToTopState extends State<HelpBackToTop> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Focus(
      skipTraversal: true,
      onFocusChange: (value) => setState(() => _focused = value),
      child: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        extendedTextStyle: theme.textTheme.labelLarge
            ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
                color: _focused ? colors.onPrimary : Colors.transparent,
                width: 3)),
        onPressed: widget.onPressed,
        icon: const ExcludeSemantics(child: Icon(Icons.arrow_upward)),
        label: Text(AppLocalizations.of(context)!.helpBackToTop),
      ),
    );
  }
}
