import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/app_bar_actions.dart';

/// Helper class to create consistent AppBars across the application
class AppBarHelper {
  /// Creates a standard AppBar with consistent styling
  static PreferredSizeWidget createAppBar(
    BuildContext context, {
    required String title,
    List<Widget>? additionalActions,
    Widget? leading,
    PreferredSizeWidget? bottom,
    bool centerTitle = false,
    bool automaticallyImplyLeading = true,
  }) {
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      iconTheme: Theme.of(context).appBarTheme.iconTheme,
      title: Text(title, style: Theme.of(context).appBarTheme.titleTextStyle),
      centerTitle: centerTitle,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading ??
          IconButton(
            icon: const Icon(Icons.arrow_back),
            // A name for screen readers (WCAG 4.1.2); "Back", localized.
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () {
              if (Navigator.canPop(context)) {
                Navigator.of(context).pop();
              } else {
                // A directly opened page (for example voice navigation to
                // Calendar) has no parent to pop. Make Home the navigation
                // root so subsequent Back actions cannot reopen that page.
                context.go('/dashboard');
              }
            },
          ),
      bottom: bottom,
      actions: [
        AppBarActions(additionalActions: additionalActions),
        const SizedBox(width: 8),
      ],
    );
  }
}
