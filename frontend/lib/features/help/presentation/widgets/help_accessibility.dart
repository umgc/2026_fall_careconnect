import 'package:flutter/material.dart';

/// The bundled Help content and all current Help label fallbacks are English.
/// Keep the language explicit for screen readers when the app locale differs.
class HelpAccessibility extends StatelessWidget {
  const HelpAccessibility({super.key, required this.builder, this.pageTitle});
  final WidgetBuilder builder;
  final String? pageTitle;

  @override
  Widget build(BuildContext context) {
    final theme = helpTheme(Theme.of(context));
    final content = Semantics(
      localeForSubtree: const Locale('en'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: Builder(builder: builder)),
      ),
    );
    return Theme(
        data: theme,
        child: pageTitle == null
            ? content
            : Title(
                title: '$pageTitle | CareConnect Help',
                color: theme.colorScheme.primary,
                child: content));
  }
}

/// Contrast, readable type, targets and visible keyboard focus across Help.
ThemeData helpTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  final foreground = colors.onSurface;
  final primary = theme.brightness == Brightness.light
      ? const Color(0xFF00677D)
      : const Color(0xFF5AD4E8);
  final outline = theme.brightness == Brightness.light
      ? const Color(0xFF64748B)
      : const Color(0xFF9CA3AF);
  final buttonStyle = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge
        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
    side: WidgetStateProperty.resolveWith((states) =>
        states.contains(WidgetState.focused)
            ? BorderSide(color: foreground, width: 3)
            : BorderSide.none),
  );
  return theme.copyWith(
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    colorScheme: colors.copyWith(
        primary: primary,
        onPrimary: theme.brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF001014),
        onSurfaceVariant: foreground,
        outline: outline),
    textTheme: theme.textTheme.copyWith(
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      titleMedium: theme.textTheme.titleMedium
          ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      bodyLarge: theme.textTheme.bodyLarge?.copyWith(
          color: foreground, fontWeight: FontWeight.w500, height: 1.5),
      bodyMedium: theme.textTheme.bodyMedium
          ?.copyWith(fontSize: 16, color: foreground, height: 1.5),
      bodySmall: theme.textTheme.bodySmall
          ?.copyWith(fontSize: 16, color: foreground, height: 1.5),
      labelLarge:
          theme.textTheme.labelLarge?.copyWith(fontSize: 16, color: foreground),
    ),
    cardTheme: theme.cardTheme
        .copyWith(color: colors.surface, surfaceTintColor: Colors.transparent),
    textButtonTheme: TextButtonThemeData(
        style: (theme.textButtonTheme.style ?? const ButtonStyle())
            .merge(buttonStyle)
            .copyWith(foregroundColor: WidgetStatePropertyAll(primary))),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle.copyWith(
        foregroundColor: WidgetStatePropertyAll(primary),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.focused) ? foreground : outline,
            width: states.contains(WidgetState.focused) ? 3 : 1.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    iconButtonTheme: IconButtonThemeData(style: buttonStyle),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 16, color: foreground, fontWeight: FontWeight.w500),
      // Material scales floating labels to 75%; retain a visible 16px label.
      floatingLabelStyle: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 16 / 0.75, color: primary, fontWeight: FontWeight.w600),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline, width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 3)),
    ),
  );
}
