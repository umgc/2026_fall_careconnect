import 'package:flutter/material.dart';

/// Centralized theme configuration for the CareConnect app
/// This ensures consistent colors, typography, and component styles across the app
class AppTheme {
  // Light Theme Colors
  // Main app colors (Alexa-like cyan)
  static const Color primaryDark = Color(0xFF008DA8);
  static const Color primary = Color(0xFF00A7C8);
  static const Color primaryLight = Color(0xFF25BEDA);
  static const Color accent = Color(0xFF25BEDA);

  // Status colors
  static const Color success = Color(0xFF10B981); // emerald-500
  static const Color warning = Color(0xFFF59E0B); // amber-500
  static const Color error = Color(0xFFEF4444); // red-500
  static const Color info = Color(0xFF00A7C8); // cyan accent

  // Text colors
  static const Color textPrimary = Color(0xFF0F172A); // slate-900
  static const Color textSecondary = Color(0xFF6B7280); // gray-500/600
  static const Color textLight = Color(0xFFFFFFFF); // white

  // Background colors
  static const Color backgroundPrimary = Color(0xFFFFFFFF); // white
  static const Color backgroundSecondary = Color(0xFFF3F4F6); // gray-100
  static const Color cardBackground = Color(0xFFFFFFFF); // white

  // Border colors
  static const Color borderColor = Color(0xFFE5E7EB); // gray-200

  // Dark Theme Colors
  // Main app colors (same hue, tuned for dark)
  static const Color primaryDarkThemeDark = Color(0xFF25BEDA);
  static const Color primaryDarkTheme = Color(0xFF00A7C8);
  static const Color primaryDarkThemeLight = Color(0xFF5AD4E8);
  static const Color accentDarkTheme = Color(0xFF25BEDA);

  // Status colors - slightly lighter for dark theme
  static const Color successDarkTheme = Color(0xFF34D399); // emerald-400
  static const Color warningDarkTheme = Color(0xFFFBBF24); // amber-400
  static const Color errorDarkTheme = Color(0xFFF87171); // red-400
  static const Color infoDarkTheme = Color(0xFF25BEDA);

  // Text colors for dark theme
  static const Color textPrimaryDarkTheme = Color(0xFFE5E7EB); // gray-200
  static const Color textSecondaryDarkTheme = Color(0xFF9CA3AF); // gray-400
  static const Color textDarkThemeDark = Color(0xFF001014); // on-cyan

  // Background colors for dark theme
  static const Color backgroundPrimaryDarkTheme =
      Color(0xFF0B1220); // near-black with blue hint
  static const Color backgroundSecondaryDarkTheme =
      Color(0xFF111827); // gray-900
  static const Color cardBackgroundDarkTheme = Color(0xFF131B2B); // lifted card
  // Border colors for dark theme
  static const Color borderColorDarkTheme = Color(0xFF1F2A3A); // deep slate

  // Video call specific colors
  static const Color videoCallBackground = Color(0xFF000000); // black
  static const Color videoCallBackgroundDarkTheme =
      Color(0xFF0B1220); // dark background
  static const Color videoCallText = Color(0xFFFFFFFF); // white
  static const Color videoCallTextSecondary = Color(0xFFBFC7D1);
  static const Color videoCallTextTertiary = Color(0xFF98A4B3);
  static const Color videoCallEndCall = Color(0xFFEF4444); // red
  static const Color videoCallEndCallDarkTheme =
      Color(0xFFF87171); // lighter red for dark

  // Chat/messaging specific colors
  static const Color chatUserMessage = Color(0xFF00A7C8);
  static const Color chatUserMessageDarkTheme = Color(0xFF008DA8);
  static const Color chatBotMessage = Color(0xFFF3F4F6); // gray-100
  static const Color chatBotMessageDarkTheme = Color(0xFF111827); // gray-900
  static const Color chatTextOnPrimary =
      Color(0xFFFFFFFF); // white text on cyan
  static const Color chatTextOnSecondary = Color(0xFF0F172A); // slate-900
  static const Color chatTextOnSecondaryDarkTheme =
      Color(0xFFE5E7EB); // gray-200

  // Typography styles
  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.2,
    color: textPrimary,
  );

  static const TextStyle headingMedium = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.1,
    color: textPrimary,
  );

  static const TextStyle headingSmall = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.45,
    color: textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    height: 1.45,
    color: textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: textSecondary,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: textLight,
  );

  // Button styles
  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: primary,
    foregroundColor: textDarkThemeDark, // better on-cyan contrast
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    elevation: 1,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: buttonText,
  );

  static ButtonStyle secondaryButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: primary,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: primary, width: 1.5),
    ),
    textStyle: buttonText,
  );

  static ButtonStyle textButtonStyle = TextButton.styleFrom(
    foregroundColor: primary,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
  );

  static ButtonStyle dangerButtonStyle = ElevatedButton.styleFrom(
    backgroundColor: error,
    foregroundColor: textLight,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    textStyle: buttonText,
  );

  // Card styles
  static BoxDecoration cardDecoration = BoxDecoration(
    color: cardBackground,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: borderColor),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // Input decoration
  static InputDecoration inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  // Generate theme data for MaterialApp
  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        error: error,
        surface: cardBackground,
        onPrimary: textDarkThemeDark, // on-cyan
        onSecondary: textLight,
        onSurface: textPrimary,
        onError: textLight,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: backgroundPrimary,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardBackground,
        contentTextStyle: const TextStyle(color: textPrimary),
        actionTextColor: primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundPrimary,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: cardBackground,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryButtonStyle),
      textButtonTheme: TextButtonThemeData(style: textButtonStyle),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        fillColor: backgroundPrimary,
        filled: true,
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      textTheme: const TextTheme(
        displayLarge: headingLarge,
        displayMedium: headingMedium,
        displaySmall: headingSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
      ),
      dividerTheme: const DividerThemeData(thickness: 1, color: borderColor),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return textSecondary.withOpacity(0.3);
          }
          return primary;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      iconTheme: const IconThemeData(color: textPrimary),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: backgroundPrimary,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary,
      ),
      useMaterial3: true,
    );
  }

  // Generate dark theme data for MaterialApp
  static ThemeData get darkTheme {
    return ThemeData(
      primaryColor: primaryDarkTheme,
      colorScheme: const ColorScheme.dark(
        primary: primaryDarkTheme,
        secondary: accentDarkTheme,
        error: errorDarkTheme,
        surface: cardBackgroundDarkTheme,
        onPrimary: textDarkThemeDark,
        onSecondary: textDarkThemeDark,
        onSurface: textPrimaryDarkTheme,
        onError: textDarkThemeDark,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: backgroundPrimaryDarkTheme,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardBackgroundDarkTheme,
        contentTextStyle: const TextStyle(color: textPrimaryDarkTheme),
        actionTextColor: primaryDarkThemeLight,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D1626), // slightly lighter than page bg
        foregroundColor: textPrimaryDarkTheme,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimaryDarkTheme,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: textPrimaryDarkTheme),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: cardBackgroundDarkTheme,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDarkTheme,
          foregroundColor: textDarkThemeDark,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryDarkThemeLight,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: borderColorDarkTheme),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryDarkThemeLight, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        fillColor: backgroundSecondaryDarkTheme,
        filled: true,
        labelStyle: const TextStyle(color: textSecondaryDarkTheme),
        hintStyle: const TextStyle(color: textSecondaryDarkTheme),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: textPrimaryDarkTheme,
        ),
        displayMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: textPrimaryDarkTheme,
        ),
        displaySmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: textPrimaryDarkTheme,
        ),
        bodyLarge:
            TextStyle(fontSize: 16, height: 1.5, color: textPrimaryDarkTheme),
        bodyMedium:
            TextStyle(fontSize: 14, height: 1.5, color: textPrimaryDarkTheme),
        bodySmall:
            TextStyle(fontSize: 12, height: 1.4, color: textSecondaryDarkTheme),
      ),
      dividerTheme: const DividerThemeData(
        thickness: 1,
        color: borderColorDarkTheme,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return textSecondaryDarkTheme.withOpacity(0.3);
          }
          return primaryDarkTheme;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      iconTheme: const IconThemeData(color: textPrimaryDarkTheme),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: backgroundPrimaryDarkTheme,
        selectedItemColor: primaryDarkThemeLight,
        unselectedItemColor: textSecondaryDarkTheme,
      ),
      useMaterial3: true,
      dialogTheme: const DialogThemeData(
        backgroundColor: cardBackgroundDarkTheme,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    );
  }
}
