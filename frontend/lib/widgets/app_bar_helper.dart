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
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final scaler = MediaQuery.textScalerOf(context);
    final compact = width < 600 || scaler.scale(16) > 24;
    final titleStyle =
        theme.appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge!;
    final titleText = Text(title,
        style: titleStyle, softWrap: true, overflow: TextOverflow.visible);
    double titleHeight = 0;
    if (compact) {
      final painter = TextPainter(
        text: TextSpan(text: title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout(maxWidth: (width - 32).clamp(1.0, double.infinity));
      titleHeight = painter.height + 16;
      painter.dispose();
    }
    return AppBar(
      backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
      iconTheme: Theme.of(context).appBarTheme.iconTheme,
      title: compact ? null : titleText,
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
      bottom: compact
          ? PreferredSize(
              preferredSize: Size.fromHeight(
                  titleHeight + (bottom?.preferredSize.height ?? 0)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Semantics(headingLevel: 1, child: titleText),
                  ),
                  if (bottom != null) bottom,
                ],
              ),
            )
          : bottom,
      actions: [
        AppBarActions(additionalActions: additionalActions),
        const SizedBox(width: 8),
      ],
    );
  }
}
