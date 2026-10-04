import 'package:flutter/material.dart';

/// Readable glossary typography and controls, scoped to the glossary surface.
ThemeData helpGlossaryTheme(ThemeData theme) {
  final colors = theme.colorScheme;
  final foreground = colors.onSurface;
  final primary = theme.brightness == Brightness.light
      ? const Color(0xFF00677D)
      : colors.primary;
  final outline = theme.brightness == Brightness.light
      ? const Color(0xFF64748B)
      : const Color(0xFF9CA3AF);
  return theme.copyWith(
    colorScheme: colors.copyWith(
        primary: primary,
        onPrimary: theme.brightness == Brightness.light
            ? Colors.white
            : colors.onPrimary,
        onSurfaceVariant: foreground,
        outline: outline),
    textTheme: theme.textTheme.copyWith(
      titleLarge: theme.textTheme.titleLarge
          ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
      titleMedium: theme.textTheme.titleMedium
          ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      bodyLarge: theme.textTheme.bodyLarge?.copyWith(
          color: foreground, fontWeight: FontWeight.w500, height: 1.5),
    ),
    cardTheme: theme.cardTheme
        .copyWith(color: colors.surface, surfaceTintColor: Colors.transparent),
    textButtonTheme: TextButtonThemeData(
        style: theme.textButtonTheme.style
            ?.copyWith(foregroundColor: WidgetStatePropertyAll(primary))),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w500),
      floatingLabelStyle:
          TextStyle(color: primary, fontWeight: FontWeight.w600),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2)),
    ),
  );
}
