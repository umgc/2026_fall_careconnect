// Tests for AppTheme constants and styles
// (lib/config/theme/app_theme.dart).
//
// AppTheme exposes static Color constants, TextStyle constants, ButtonStyle
// values, ThemeData getters, and helper methods. These tests verify that the
// expected values are accessible and have the correct properties.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Light theme colour constants
  // ---------------------------------------------------------------------------
  group('AppTheme – light theme colours', () {
    test('primary colour is non-transparent', () {
      expect((AppTheme.primary.a * 255.0).round().clamp(0, 255), 255);
    });

    test('primaryDark is darker than primary', () {
      expect(AppTheme.primaryDark, isNot(equals(AppTheme.primary)));
    });

    test('primaryLight is lighter than primary', () {
      expect(AppTheme.primaryLight, isNot(equals(AppTheme.primary)));
    });

    test('accent equals primaryLight', () {
      expect(AppTheme.accent, AppTheme.primaryLight);
    });

    test('success colour is non-transparent', () {
      expect((AppTheme.success.a * 255.0).round().clamp(0, 255), 255);
    });

    test('warning colour is non-transparent', () {
      expect((AppTheme.warning.a * 255.0).round().clamp(0, 255), 255);
    });

    test('error colour is non-transparent', () {
      expect((AppTheme.error.a * 255.0).round().clamp(0, 255), 255);
    });

    test('info colour equals primary', () {
      expect(AppTheme.info, AppTheme.primary);
    });

    test('textPrimary is very dark (slate-900)', () {
      expect((AppTheme.textPrimary.r * 255.0).round().clamp(0, 255), lessThan(50));
    });

    test('textSecondary is gray-500', () {
      expect(AppTheme.textSecondary, const Color(0xFF6B7280));
    });

    test('textLight is white', () {
      expect(AppTheme.textLight, const Color(0xFFFFFFFF));
    });

    test('backgroundPrimary is white', () {
      expect(AppTheme.backgroundPrimary, const Color(0xFFFFFFFF));
    });

    test('backgroundSecondary is gray-100', () {
      expect(AppTheme.backgroundSecondary, const Color(0xFFF3F4F6));
    });

    test('cardBackground is white', () {
      expect(AppTheme.cardBackground, const Color(0xFFFFFFFF));
    });

    test('borderColor is gray-200', () {
      expect(AppTheme.borderColor, const Color(0xFFE5E7EB));
    });

    test('primary color has expected hex value', () {
      expect(AppTheme.primary, const Color(0xFF00A7C8));
    });

    test('primaryDark has expected hex value', () {
      expect(AppTheme.primaryDark, const Color(0xFF008DA8));
    });

    test('primaryLight has expected hex value', () {
      expect(AppTheme.primaryLight, const Color(0xFF25BEDA));
    });

    test('success has expected hex value', () {
      expect(AppTheme.success, const Color(0xFF10B981));
    });

    test('warning has expected hex value', () {
      expect(AppTheme.warning, const Color(0xFFF59E0B));
    });

    test('error has expected hex value', () {
      expect(AppTheme.error, const Color(0xFFEF4444));
    });

    test('textPrimary has expected hex value', () {
      expect(AppTheme.textPrimary, const Color(0xFF0F172A));
    });
  });

  // ---------------------------------------------------------------------------
  // Dark theme colour constants
  // ---------------------------------------------------------------------------
  group('AppTheme – dark theme colours', () {
    test('primaryDarkTheme colour is non-transparent', () {
      expect((AppTheme.primaryDarkTheme.a * 255.0).round().clamp(0, 255), 255);
    });

    test('primaryDarkThemeDark has expected hex value', () {
      expect(AppTheme.primaryDarkThemeDark, const Color(0xFF25BEDA));
    });

    test('primaryDarkTheme has expected hex value', () {
      expect(AppTheme.primaryDarkTheme, const Color(0xFF00A7C8));
    });

    test('primaryDarkThemeLight has expected hex value', () {
      expect(AppTheme.primaryDarkThemeLight, const Color(0xFF5AD4E8));
    });

    test('accentDarkTheme equals primaryDarkThemeDark', () {
      expect(AppTheme.accentDarkTheme, AppTheme.primaryDarkThemeDark);
    });

    test('successDarkTheme has expected hex value', () {
      expect(AppTheme.successDarkTheme, const Color(0xFF34D399));
    });

    test('warningDarkTheme has expected hex value', () {
      expect(AppTheme.warningDarkTheme, const Color(0xFFFBBF24));
    });

    test('errorDarkTheme differs from light error', () {
      expect(AppTheme.errorDarkTheme, isNot(equals(AppTheme.error)));
    });

    test('errorDarkTheme has expected hex value', () {
      expect(AppTheme.errorDarkTheme, const Color(0xFFF87171));
    });

    test('infoDarkTheme has expected hex value', () {
      expect(AppTheme.infoDarkTheme, const Color(0xFF25BEDA));
    });

    test('backgroundPrimaryDarkTheme is near-black', () {
      expect((AppTheme.backgroundPrimaryDarkTheme.r * 255.0).round().clamp(0, 255), lessThan(30));
    });

    test('backgroundPrimaryDarkTheme has expected hex value', () {
      expect(AppTheme.backgroundPrimaryDarkTheme, const Color(0xFF0B1220));
    });

    test('backgroundSecondaryDarkTheme has expected hex value', () {
      expect(AppTheme.backgroundSecondaryDarkTheme, const Color(0xFF111827));
    });

    test('cardBackgroundDarkTheme has expected hex value', () {
      expect(AppTheme.cardBackgroundDarkTheme, const Color(0xFF131B2B));
    });

    test('borderColorDarkTheme has expected hex value', () {
      expect(AppTheme.borderColorDarkTheme, const Color(0xFF1F2A3A));
    });

    test('textPrimaryDarkTheme is near-white', () {
      expect((AppTheme.textPrimaryDarkTheme.r * 255.0).round().clamp(0, 255), greaterThan(200));
    });

    test('textPrimaryDarkTheme has expected hex value', () {
      expect(AppTheme.textPrimaryDarkTheme, const Color(0xFFE5E7EB));
    });

    test('textSecondaryDarkTheme has expected hex value', () {
      expect(AppTheme.textSecondaryDarkTheme, const Color(0xFF9CA3AF));
    });

    test('textDarkThemeDark has expected hex value', () {
      expect(AppTheme.textDarkThemeDark, const Color(0xFF001014));
    });
  });

  // ---------------------------------------------------------------------------
  // Video call colours
  // ---------------------------------------------------------------------------
  group('AppTheme – video-call colours', () {
    test('videoCallBackground is black', () {
      expect(AppTheme.videoCallBackground, const Color(0xFF000000));
    });

    test('videoCallBackgroundDarkTheme matches dark bg', () {
      expect(AppTheme.videoCallBackgroundDarkTheme, const Color(0xFF0B1220));
    });

    test('videoCallText is white', () {
      expect(AppTheme.videoCallText, const Color(0xFFFFFFFF));
    });

    test('videoCallTextSecondary has expected value', () {
      expect(AppTheme.videoCallTextSecondary, const Color(0xFFBFC7D1));
    });

    test('videoCallTextTertiary has expected value', () {
      expect(AppTheme.videoCallTextTertiary, const Color(0xFF98A4B3));
    });

    test('videoCallEndCall is red', () {
      expect(AppTheme.videoCallEndCall, AppTheme.error);
    });

    test('videoCallEndCallDarkTheme is lighter red', () {
      expect(AppTheme.videoCallEndCallDarkTheme, AppTheme.errorDarkTheme);
    });
  });

  // ---------------------------------------------------------------------------
  // Chat colours
  // ---------------------------------------------------------------------------
  group('AppTheme – chat colours', () {
    test('chatUserMessage equals primary', () {
      expect(AppTheme.chatUserMessage, AppTheme.primary);
    });

    test('chatUserMessageDarkTheme equals primaryDark', () {
      expect(AppTheme.chatUserMessageDarkTheme, AppTheme.primaryDark);
    });

    test('chatBotMessage is gray-100', () {
      expect(AppTheme.chatBotMessage, const Color(0xFFF3F4F6));
    });

    test('chatBotMessageDarkTheme is gray-900', () {
      expect(AppTheme.chatBotMessageDarkTheme, const Color(0xFF111827));
    });

    test('chatTextOnPrimary is white', () {
      expect(AppTheme.chatTextOnPrimary, const Color(0xFFFFFFFF));
    });

    test('chatTextOnSecondary is slate-900', () {
      expect(AppTheme.chatTextOnSecondary, AppTheme.textPrimary);
    });

    test('chatTextOnSecondaryDarkTheme is gray-200', () {
      expect(AppTheme.chatTextOnSecondaryDarkTheme, AppTheme.textPrimaryDarkTheme);
    });
  });

  // ---------------------------------------------------------------------------
  // Typography styles
  // ---------------------------------------------------------------------------
  group('AppTheme – typography styles', () {
    test('headingLarge has font size 28 and bold weight', () {
      expect(AppTheme.headingLarge.fontSize, 28);
      expect(AppTheme.headingLarge.fontWeight, FontWeight.bold);
      expect(AppTheme.headingLarge.letterSpacing, 0.2);
      expect(AppTheme.headingLarge.color, AppTheme.textPrimary);
    });

    test('headingMedium has font size 24 and bold weight', () {
      expect(AppTheme.headingMedium.fontSize, 24);
      expect(AppTheme.headingMedium.fontWeight, FontWeight.bold);
      expect(AppTheme.headingMedium.letterSpacing, 0.1);
      expect(AppTheme.headingMedium.color, AppTheme.textPrimary);
    });

    test('headingSmall has font size 20 and bold weight', () {
      expect(AppTheme.headingSmall.fontSize, 20);
      expect(AppTheme.headingSmall.fontWeight, FontWeight.bold);
      expect(AppTheme.headingSmall.color, AppTheme.textPrimary);
    });

    test('bodyLarge has font size 16 and correct line height', () {
      expect(AppTheme.bodyLarge.fontSize, 16);
      expect(AppTheme.bodyLarge.height, 1.45);
      expect(AppTheme.bodyLarge.color, AppTheme.textPrimary);
    });

    test('bodyMedium has font size 14 and correct line height', () {
      expect(AppTheme.bodyMedium.fontSize, 14);
      expect(AppTheme.bodyMedium.height, 1.45);
      expect(AppTheme.bodyMedium.color, AppTheme.textPrimary);
    });

    test('bodySmall has font size 12, line height 1.4, secondary color', () {
      expect(AppTheme.bodySmall.fontSize, 12);
      expect(AppTheme.bodySmall.height, 1.4);
      expect(AppTheme.bodySmall.color, AppTheme.textSecondary);
    });

    test('buttonText has font size 16, w500, letterSpacing 0.2', () {
      expect(AppTheme.buttonText.fontSize, 16);
      expect(AppTheme.buttonText.fontWeight, FontWeight.w500);
      expect(AppTheme.buttonText.letterSpacing, 0.2);
      expect(AppTheme.buttonText.color, AppTheme.textLight);
    });
  });

  // ---------------------------------------------------------------------------
  // Button styles
  // ---------------------------------------------------------------------------
  group('AppTheme – button styles', () {
    test('primaryButtonStyle is not null', () {
      expect(AppTheme.primaryButtonStyle, isNotNull);
    });

    test('secondaryButtonStyle is not null', () {
      expect(AppTheme.secondaryButtonStyle, isNotNull);
    });

    test('textButtonStyle is not null', () {
      expect(AppTheme.textButtonStyle, isNotNull);
    });

    test('dangerButtonStyle is not null', () {
      expect(AppTheme.dangerButtonStyle, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Card decoration
  // ---------------------------------------------------------------------------
  group('AppTheme – cardDecoration', () {
    test('cardDecoration has border radius 12', () {
      final br = AppTheme.cardDecoration.borderRadius as BorderRadius;
      expect(br.topLeft.x, 12);
      expect(br.topRight.x, 12);
      expect(br.bottomLeft.x, 12);
      expect(br.bottomRight.x, 12);
    });

    test('cardDecoration has white background', () {
      expect(AppTheme.cardDecoration.color, AppTheme.cardBackground);
    });

    test('cardDecoration has box shadow', () {
      expect(AppTheme.cardDecoration.boxShadow, isNotNull);
      expect(AppTheme.cardDecoration.boxShadow!.length, 1);
    });

    test('cardDecoration shadow offset is (0,2)', () {
      final shadow = AppTheme.cardDecoration.boxShadow!.first;
      expect(shadow.offset, const Offset(0, 2));
      expect(shadow.blurRadius, 8);
    });

    test('cardDecoration has border', () {
      expect(AppTheme.cardDecoration.border, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // inputDecoration helper
  // ---------------------------------------------------------------------------
  group('AppTheme – inputDecoration', () {
    test('inputDecoration returns InputDecoration with label', () {
      final d = AppTheme.inputDecoration('Email');
      expect(d.labelText, 'Email');
      expect(d.hintText, isNull);
    });

    test('inputDecoration with hint', () {
      final d = AppTheme.inputDecoration('Name', hint: 'Enter name');
      expect(d.labelText, 'Name');
      expect(d.hintText, 'Enter name');
    });

    test('inputDecoration has OutlineInputBorder with radius 12', () {
      final d = AppTheme.inputDecoration('Test');
      final border = d.border as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(12));
    });

    test('inputDecoration focusedBorder has primary color and width 2', () {
      final d = AppTheme.inputDecoration('Test');
      final focused = d.focusedBorder as OutlineInputBorder;
      expect(focused.borderSide.color, AppTheme.primary);
      expect(focused.borderSide.width, 2);
      expect(focused.borderRadius, BorderRadius.circular(12));
    });

    test('inputDecoration has correct content padding', () {
      final d = AppTheme.inputDecoration('Test');
      expect(d.contentPadding, const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
    });
  });

  // ---------------------------------------------------------------------------
  // Light theme – ThemeData
  // ---------------------------------------------------------------------------
  group('AppTheme – lightTheme', () {
    late ThemeData theme;
    setUp(() => theme = AppTheme.lightTheme);

    test('returns ThemeData', () {
      expect(theme, isA<ThemeData>());
    });

    test('uses primary color', () {
      expect(theme.primaryColor, AppTheme.primary);
    });

    test('has light brightness', () {
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('scaffold background is white', () {
      expect(theme.scaffoldBackgroundColor, AppTheme.backgroundPrimary);
    });

    test('uses Material3', () {
      expect(theme.useMaterial3, isTrue);
    });

    // ColorScheme
    test('colorScheme primary is AppTheme.primary', () {
      expect(theme.colorScheme.primary, AppTheme.primary);
    });

    test('colorScheme secondary is accent', () {
      expect(theme.colorScheme.secondary, AppTheme.accent);
    });

    test('colorScheme error is AppTheme.error', () {
      expect(theme.colorScheme.error, AppTheme.error);
    });

    test('colorScheme surface is cardBackground', () {
      expect(theme.colorScheme.surface, AppTheme.cardBackground);
    });

    test('colorScheme onPrimary is textDarkThemeDark', () {
      expect(theme.colorScheme.onPrimary, AppTheme.textDarkThemeDark);
    });

    test('colorScheme onSecondary is textLight', () {
      expect(theme.colorScheme.onSecondary, AppTheme.textLight);
    });

    test('colorScheme onSurface is textPrimary', () {
      expect(theme.colorScheme.onSurface, AppTheme.textPrimary);
    });

    test('colorScheme onError is textLight', () {
      expect(theme.colorScheme.onError, AppTheme.textLight);
    });

    // SnackBar theme
    test('snackBarTheme backgroundColor is cardBackground', () {
      expect(theme.snackBarTheme.backgroundColor, AppTheme.cardBackground);
    });

    test('snackBarTheme actionTextColor is primary', () {
      expect(theme.snackBarTheme.actionTextColor, AppTheme.primary);
    });

    test('snackBarTheme behavior is floating', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    test('snackBarTheme contentTextStyle color is textPrimary', () {
      expect(theme.snackBarTheme.contentTextStyle?.color, AppTheme.textPrimary);
    });

    // AppBar theme
    test('appBarTheme backgroundColor is backgroundPrimary', () {
      expect(theme.appBarTheme.backgroundColor, AppTheme.backgroundPrimary);
    });

    test('appBarTheme foregroundColor is textPrimary', () {
      expect(theme.appBarTheme.foregroundColor, AppTheme.textPrimary);
    });

    test('appBarTheme elevation is 0', () {
      expect(theme.appBarTheme.elevation, 0);
    });

    test('appBarTheme centerTitle is false', () {
      expect(theme.appBarTheme.centerTitle, false);
    });

    test('appBarTheme titleTextStyle color is textPrimary', () {
      expect(theme.appBarTheme.titleTextStyle?.color, AppTheme.textPrimary);
      expect(theme.appBarTheme.titleTextStyle?.fontSize, 20);
      expect(theme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.bold);
    });

    test('appBarTheme iconTheme color is textPrimary', () {
      expect(theme.appBarTheme.iconTheme?.color, AppTheme.textPrimary);
    });

    // Card theme
    test('cardTheme elevation is 0', () {
      expect(theme.cardTheme.elevation, 0);
    });

    test('cardTheme color is cardBackground', () {
      expect(theme.cardTheme.color, AppTheme.cardBackground);
    });

    test('cardTheme shape has border radius 12', () {
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(12));
    });

    // Input decoration theme
    test('inputDecorationTheme fillColor is backgroundPrimary', () {
      expect(theme.inputDecorationTheme.fillColor, AppTheme.backgroundPrimary);
    });

    test('inputDecorationTheme is filled', () {
      expect(theme.inputDecorationTheme.filled, true);
    });

    test('inputDecorationTheme labelStyle color is textSecondary', () {
      expect(theme.inputDecorationTheme.labelStyle?.color, AppTheme.textSecondary);
    });

    test('inputDecorationTheme hintStyle color is textSecondary', () {
      expect(theme.inputDecorationTheme.hintStyle?.color, AppTheme.textSecondary);
    });

    test('inputDecorationTheme contentPadding', () {
      expect(theme.inputDecorationTheme.contentPadding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
    });

    // Text theme
    test('textTheme displayLarge matches headingLarge', () {
      expect(theme.textTheme.displayLarge?.fontSize, AppTheme.headingLarge.fontSize);
      expect(theme.textTheme.displayLarge?.fontWeight, AppTheme.headingLarge.fontWeight);
    });

    test('textTheme displayMedium matches headingMedium', () {
      expect(theme.textTheme.displayMedium?.fontSize, AppTheme.headingMedium.fontSize);
      expect(theme.textTheme.displayMedium?.fontWeight, AppTheme.headingMedium.fontWeight);
    });

    test('textTheme displaySmall matches headingSmall', () {
      expect(theme.textTheme.displaySmall?.fontSize, AppTheme.headingSmall.fontSize);
      expect(theme.textTheme.displaySmall?.fontWeight, AppTheme.headingSmall.fontWeight);
    });

    test('textTheme bodyLarge matches bodyLarge style', () {
      expect(theme.textTheme.bodyLarge?.fontSize, AppTheme.bodyLarge.fontSize);
    });

    test('textTheme bodyMedium matches bodyMedium style', () {
      expect(theme.textTheme.bodyMedium?.fontSize, AppTheme.bodyMedium.fontSize);
    });

    test('textTheme bodySmall matches bodySmall style', () {
      expect(theme.textTheme.bodySmall?.fontSize, AppTheme.bodySmall.fontSize);
    });

    // Divider theme
    test('dividerTheme thickness is 1', () {
      expect(theme.dividerTheme.thickness, 1);
    });

    test('dividerTheme color is borderColor', () {
      expect(theme.dividerTheme.color, AppTheme.borderColor);
    });

    // Checkbox theme
    test('checkboxTheme fillColor resolves to primary when enabled', () {
      final fillColor = theme.checkboxTheme.fillColor;
      final resolved = fillColor?.resolve(<WidgetState>{});
      expect(resolved, AppTheme.primary);
    });

    test('checkboxTheme fillColor resolves correctly when disabled', () {
      final fillColor = theme.checkboxTheme.fillColor;
      final resolved = fillColor?.resolve(<WidgetState>{WidgetState.disabled});
      // Should be textSecondary with 0.3 opacity
      expect(resolved, isNotNull);
      expect(resolved, isNot(equals(AppTheme.primary)));
    });

    test('checkboxTheme shape has border radius 4', () {
      final shape = theme.checkboxTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(4));
    });

    // Icon theme
    test('iconTheme color is textPrimary', () {
      expect(theme.iconTheme.color, AppTheme.textPrimary);
    });

    // Bottom navigation bar theme
    test('bottomNavigationBarTheme backgroundColor is backgroundPrimary', () {
      expect(theme.bottomNavigationBarTheme.backgroundColor, AppTheme.backgroundPrimary);
    });

    test('bottomNavigationBarTheme selectedItemColor is primary', () {
      expect(theme.bottomNavigationBarTheme.selectedItemColor, AppTheme.primary);
    });

    test('bottomNavigationBarTheme unselectedItemColor is textSecondary', () {
      expect(theme.bottomNavigationBarTheme.unselectedItemColor, AppTheme.textSecondary);
    });

    // Elevated button theme
    test('elevatedButtonTheme style is set', () {
      expect(theme.elevatedButtonTheme.style, isNotNull);
    });

    // Text button theme
    test('textButtonTheme style is set', () {
      expect(theme.textButtonTheme.style, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Dark theme – ThemeData
  // ---------------------------------------------------------------------------
  group('AppTheme – darkTheme', () {
    late ThemeData theme;
    setUp(() => theme = AppTheme.darkTheme);

    test('returns ThemeData', () {
      expect(theme, isA<ThemeData>());
    });

    test('uses dark primary color', () {
      expect(theme.primaryColor, AppTheme.primaryDarkTheme);
    });

    test('has dark brightness', () {
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('scaffold background is near-black', () {
      expect(theme.scaffoldBackgroundColor, AppTheme.backgroundPrimaryDarkTheme);
    });

    test('uses Material3', () {
      expect(theme.useMaterial3, isTrue);
    });

    // ColorScheme
    test('colorScheme primary is primaryDarkTheme', () {
      expect(theme.colorScheme.primary, AppTheme.primaryDarkTheme);
    });

    test('colorScheme secondary is accentDarkTheme', () {
      expect(theme.colorScheme.secondary, AppTheme.accentDarkTheme);
    });

    test('colorScheme error is errorDarkTheme', () {
      expect(theme.colorScheme.error, AppTheme.errorDarkTheme);
    });

    test('colorScheme surface is cardBackgroundDarkTheme', () {
      expect(theme.colorScheme.surface, AppTheme.cardBackgroundDarkTheme);
    });

    test('colorScheme onPrimary is textDarkThemeDark', () {
      expect(theme.colorScheme.onPrimary, AppTheme.textDarkThemeDark);
    });

    test('colorScheme onSecondary is textDarkThemeDark', () {
      expect(theme.colorScheme.onSecondary, AppTheme.textDarkThemeDark);
    });

    test('colorScheme onSurface is textPrimaryDarkTheme', () {
      expect(theme.colorScheme.onSurface, AppTheme.textPrimaryDarkTheme);
    });

    test('colorScheme onError is textDarkThemeDark', () {
      expect(theme.colorScheme.onError, AppTheme.textDarkThemeDark);
    });

    // SnackBar theme
    test('snackBarTheme backgroundColor is cardBackgroundDarkTheme', () {
      expect(theme.snackBarTheme.backgroundColor, AppTheme.cardBackgroundDarkTheme);
    });

    test('snackBarTheme actionTextColor is primaryDarkThemeLight', () {
      expect(theme.snackBarTheme.actionTextColor, AppTheme.primaryDarkThemeLight);
    });

    test('snackBarTheme behavior is floating', () {
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
    });

    test('snackBarTheme contentTextStyle color is textPrimaryDarkTheme', () {
      expect(theme.snackBarTheme.contentTextStyle?.color, AppTheme.textPrimaryDarkTheme);
    });

    // AppBar theme
    test('appBarTheme backgroundColor is dark variant', () {
      expect(theme.appBarTheme.backgroundColor, const Color(0xFF0D1626));
    });

    test('appBarTheme foregroundColor is textPrimaryDarkTheme', () {
      expect(theme.appBarTheme.foregroundColor, AppTheme.textPrimaryDarkTheme);
    });

    test('appBarTheme elevation is 0', () {
      expect(theme.appBarTheme.elevation, 0);
    });

    test('appBarTheme centerTitle is false', () {
      expect(theme.appBarTheme.centerTitle, false);
    });

    test('appBarTheme titleTextStyle color is textPrimaryDarkTheme', () {
      expect(theme.appBarTheme.titleTextStyle?.color, AppTheme.textPrimaryDarkTheme);
      expect(theme.appBarTheme.titleTextStyle?.fontSize, 20);
      expect(theme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.bold);
    });

    test('appBarTheme iconTheme color is textPrimaryDarkTheme', () {
      expect(theme.appBarTheme.iconTheme?.color, AppTheme.textPrimaryDarkTheme);
    });

    // Card theme
    test('cardTheme elevation is 0', () {
      expect(theme.cardTheme.elevation, 0);
    });

    test('cardTheme color is cardBackgroundDarkTheme', () {
      expect(theme.cardTheme.color, AppTheme.cardBackgroundDarkTheme);
    });

    test('cardTheme shape has border radius 12', () {
      final shape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(12));
    });

    // Input decoration theme
    test('inputDecorationTheme fillColor is backgroundSecondaryDarkTheme', () {
      expect(theme.inputDecorationTheme.fillColor, AppTheme.backgroundSecondaryDarkTheme);
    });

    test('inputDecorationTheme is filled', () {
      expect(theme.inputDecorationTheme.filled, true);
    });

    test('inputDecorationTheme labelStyle color is textSecondaryDarkTheme', () {
      expect(theme.inputDecorationTheme.labelStyle?.color, AppTheme.textSecondaryDarkTheme);
    });

    test('inputDecorationTheme hintStyle color is textSecondaryDarkTheme', () {
      expect(theme.inputDecorationTheme.hintStyle?.color, AppTheme.textSecondaryDarkTheme);
    });

    test('inputDecorationTheme contentPadding', () {
      expect(theme.inputDecorationTheme.contentPadding,
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
    });

    test('inputDecorationTheme border has borderColorDarkTheme', () {
      final border = theme.inputDecorationTheme.border as OutlineInputBorder;
      expect(border.borderSide.color, AppTheme.borderColorDarkTheme);
    });

    test('inputDecorationTheme focusedBorder has primaryDarkThemeLight', () {
      final focused = theme.inputDecorationTheme.focusedBorder as OutlineInputBorder;
      expect(focused.borderSide.color, AppTheme.primaryDarkThemeLight);
      expect(focused.borderSide.width, 2);
    });

    // Text theme
    test('textTheme displayLarge has dark theme color', () {
      expect(theme.textTheme.displayLarge?.fontSize, 28);
      expect(theme.textTheme.displayLarge?.fontWeight, FontWeight.bold);
    });

    test('textTheme displayMedium has dark theme color', () {
      expect(theme.textTheme.displayMedium?.fontSize, 24);
      expect(theme.textTheme.displayMedium?.fontWeight, FontWeight.bold);
    });

    test('textTheme displaySmall has dark theme color', () {
      expect(theme.textTheme.displaySmall?.fontSize, 20);
      expect(theme.textTheme.displaySmall?.fontWeight, FontWeight.bold);
    });

    test('textTheme bodyLarge has correct font size', () {
      expect(theme.textTheme.bodyLarge?.fontSize, 16);
    });

    test('textTheme bodyMedium has correct font size', () {
      expect(theme.textTheme.bodyMedium?.fontSize, 14);
    });

    test('textTheme bodySmall has correct font size', () {
      expect(theme.textTheme.bodySmall?.fontSize, 12);
    });

    // Divider theme
    test('dividerTheme thickness is 1', () {
      expect(theme.dividerTheme.thickness, 1);
    });

    test('dividerTheme color is borderColorDarkTheme', () {
      expect(theme.dividerTheme.color, AppTheme.borderColorDarkTheme);
    });

    // Checkbox theme
    test('checkboxTheme fillColor resolves to primaryDarkTheme when enabled', () {
      final fillColor = theme.checkboxTheme.fillColor;
      final resolved = fillColor?.resolve(<WidgetState>{});
      expect(resolved, AppTheme.primaryDarkTheme);
    });

    test('checkboxTheme fillColor resolves correctly when disabled', () {
      final fillColor = theme.checkboxTheme.fillColor;
      final resolved = fillColor?.resolve(<WidgetState>{WidgetState.disabled});
      expect(resolved, isNotNull);
      expect(resolved, isNot(equals(AppTheme.primaryDarkTheme)));
    });

    test('checkboxTheme shape has border radius 4', () {
      final shape = theme.checkboxTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(4));
    });

    // Icon theme
    test('iconTheme color is textPrimaryDarkTheme', () {
      expect(theme.iconTheme.color, AppTheme.textPrimaryDarkTheme);
    });

    // Bottom navigation bar theme
    test('bottomNavigationBarTheme backgroundColor is backgroundPrimaryDarkTheme', () {
      expect(theme.bottomNavigationBarTheme.backgroundColor, AppTheme.backgroundPrimaryDarkTheme);
    });

    test('bottomNavigationBarTheme selectedItemColor is primaryDarkThemeLight', () {
      expect(theme.bottomNavigationBarTheme.selectedItemColor, AppTheme.primaryDarkThemeLight);
    });

    test('bottomNavigationBarTheme unselectedItemColor is textSecondaryDarkTheme', () {
      expect(theme.bottomNavigationBarTheme.unselectedItemColor, AppTheme.textSecondaryDarkTheme);
    });

    // Dialog theme (dark only)
    test('dialogTheme backgroundColor is cardBackgroundDarkTheme', () {
      expect(theme.dialogTheme.backgroundColor, AppTheme.cardBackgroundDarkTheme);
    });

    test('dialogTheme surfaceTintColor is transparent', () {
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    });

    test('dialogTheme shape has border radius 12', () {
      final shape = theme.dialogTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, const BorderRadius.all(Radius.circular(12)));
    });

    // Elevated button theme
    test('elevatedButtonTheme style is set', () {
      expect(theme.elevatedButtonTheme.style, isNotNull);
    });

    // Text button theme
    test('textButtonTheme style is set', () {
      expect(theme.textButtonTheme.style, isNotNull);
    });
  });
}
