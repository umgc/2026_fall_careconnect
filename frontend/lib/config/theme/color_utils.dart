import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'app_theme.dart';
import '../utils/responsive_utils.dart';

/// A utility class for accessing consistent colors throughout the application
/// This helps maintain a unified color scheme and allows for easy updates
/// Now with platform-specific color adjustments for better rendering across web, iOS, and Android
class ColorUtils {
  // Primary theme colors
  static Color get primary => AppTheme.primary;
  static Color get primaryDark => AppTheme.primaryDark;
  static Color get primaryLight => AppTheme.primaryLight;
  static Color get accent => AppTheme.accent;

  // Status colors
  static Color get success => AppTheme.success;
  static Color get warning => AppTheme.warning;
  static Color get error => AppTheme.error;
  static Color get info => AppTheme.info;

  // Text colors
  static Color get textPrimary => AppTheme.textPrimary;
  static Color get textSecondary => AppTheme.textSecondary;
  static Color get textLight => AppTheme.textLight;

  // Background colors
  static Color get backgroundPrimary => AppTheme.backgroundPrimary;
  static Color get backgroundSecondary => AppTheme.backgroundSecondary;
  static Color get cardBackground => AppTheme.cardBackground;

  // Helper methods for creating color variations
  static Color getSuccessWithOpacity(double opacity) =>
      AppTheme.success.withOpacity(opacity);
  static Color getSuccessLight() => const Color(0xFFEFFBF6);
  static Color getSuccessLighter() => const Color(0xFFD6F5E9);

  static Color getWarningWithOpacity(double opacity) =>
      AppTheme.warning.withOpacity(opacity);
  static Color getWarningLight() => const Color(0xFFFFFAEB);
  static Color getWarningLighter() => const Color(0xFFFEF3C7);

  static Color getErrorWithOpacity(double opacity) =>
      AppTheme.error.withOpacity(opacity);
  static Color getErrorLight() => const Color(0xFFFFF1F2);
  static Color getErrorLighter() => const Color(0xFFFECACA);

  static Color getInfoWithOpacity(double opacity) =>
      AppTheme.info.withOpacity(opacity);
  static Color getInfoLight() => const Color(0xFFE6F9FD);
  static Color getInfoLighter() => const Color(0xFFCFF3FA);

  static Color getPrimaryWithOpacity(double opacity) =>
      AppTheme.primary.withOpacity(opacity);
  static Color getPrimaryLight() => AppTheme.primaryLight;
  static Color getPrimaryLighter() => const Color(0xFFE6F9FD);

  // Consistent gradient generators
  static LinearGradient getPrimaryGradient() => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.primary, AppTheme.primaryDark],
      );

  static LinearGradient getSuccessGradient() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [getSuccessLight(), getSuccessLighter()],
      );

  static LinearGradient getInfoGradient() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [getInfoLight(), getInfoLighter()],
      );

  // Chart colors - tuned for dark backgrounds
  static Color getChartPrimary() => AppTheme.primary;
  static Color getChartSecondary() => const Color(0xFF60A5FA); // blue-400
  static Color getChartTertiary() => const Color(0xFFA78BFA); // violet-300
  static Color getChartQuaternary() => const Color(0xFF34D399); // emerald-400

  // Platform-specific color utilities
  static Color getCardBackgroundForPlatform(BuildContext context) {
    if (ResponsiveUtils.isIOS) {
      return const Color(0xFFFFFFFF); // iOS slightly brighter card
    }
    return AppTheme.cardBackground;
  }

  static Color getElevatedButtonColor(BuildContext context) {
    if (kIsWeb) {
      return AppTheme.primaryDark; // slightly darker for web contrast
    }
    return AppTheme.primary;
  }

  static Color getShadowColor(BuildContext context) {
    if (ResponsiveUtils.isIOS) {
      return Colors.black.withOpacity(0.10);
    } else if (ResponsiveUtils.isAndroid) {
      return Colors.black.withOpacity(0.18);
    }
    return Colors.black.withOpacity(0.12);
  }
}
