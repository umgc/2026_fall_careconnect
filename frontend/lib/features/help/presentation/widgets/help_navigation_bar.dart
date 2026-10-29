import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';
import '../../help_routes.dart';

/// Persistent shortcuts out of a Help browsing history.
class HelpNavigationBar extends StatelessWidget {
  const HelpNavigationBar({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final style = OutlinedButton.styleFrom(
      textStyle: Theme.of(context).textTheme.titleMedium,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.start,
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              style: style,
              onPressed: () => context.go(HelpRoutes.home),
              icon: const Icon(Icons.home_outlined),
              label: Text(t.helpCenterHome),
            ),
            OutlinedButton.icon(
              style: style,
              onPressed: () => context.go('/settings'),
              icon: const Icon(Icons.settings_outlined),
              label: Text(t.helpBackToSettings),
            ),
          ],
        ),
      ),
    );
  }
}
