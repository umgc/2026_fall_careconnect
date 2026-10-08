// Tests for ColorUtils (lib/config/theme/color_utils.dart).
//
// ColorUtils is a static utility class. Most methods return Colors from
// AppTheme or computed color values. The methods that require BuildContext
// are tested with a minimal widget harness.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/config/theme/color_utils.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';

void main() {
  group('ColorUtils – static color accessors', () {
    test('primary returns AppTheme.primary', () {
      expect(ColorUtils.primary, AppTheme.primary);
    });

    test('primaryDark returns AppTheme.primaryDark', () {
      expect(ColorUtils.primaryDark, AppTheme.primaryDark);
    });

    test('primaryLight returns AppTheme.primaryLight', () {
      expect(ColorUtils.primaryLight, AppTheme.primaryLight);
    });

    test('accent returns AppTheme.accent', () {
      expect(ColorUtils.accent, AppTheme.accent);
    });

    test('success returns AppTheme.success', () {
      expect(ColorUtils.success, AppTheme.success);
    });

    test('warning returns AppTheme.warning', () {
      expect(ColorUtils.warning, AppTheme.warning);
    });

    test('error returns AppTheme.error', () {
      expect(ColorUtils.error, AppTheme.error);
    });

    test('info returns AppTheme.info', () {
      expect(ColorUtils.info, AppTheme.info);
    });

    test('textPrimary returns AppTheme.textPrimary', () {
      expect(ColorUtils.textPrimary, AppTheme.textPrimary);
    });

    test('textSecondary returns AppTheme.textSecondary', () {
      expect(ColorUtils.textSecondary, AppTheme.textSecondary);
    });

    test('backgroundPrimary returns AppTheme.backgroundPrimary', () {
      expect(ColorUtils.backgroundPrimary, AppTheme.backgroundPrimary);
    });
  });

  group('ColorUtils – color variation helpers', () {
    test('getSuccessWithOpacity returns a Color with the given opacity', () {
      final c = ColorUtils.getSuccessWithOpacity(0.5);
      expect(c.a, closeTo(0.5, 0.01));
    });

    test('getSuccessLight returns a non-transparent Color', () {
      expect(ColorUtils.getSuccessLight().a, 1.0);
    });

    test('getSuccessLighter returns a non-transparent Color', () {
      expect(ColorUtils.getSuccessLighter().a, 1.0);
    });

    test('getWarningWithOpacity returns a Color with the given opacity', () {
      final c = ColorUtils.getWarningWithOpacity(0.3);
      expect(c.a, closeTo(0.3, 0.01));
    });

    test('getWarningLight returns a non-transparent Color', () {
      expect(ColorUtils.getWarningLight().a, 1.0);
    });

    test('getErrorWithOpacity returns a Color with the given opacity', () {
      final c = ColorUtils.getErrorWithOpacity(0.8);
      expect(c.a, closeTo(0.8, 0.01));
    });

    test('getErrorLight returns a non-transparent Color', () {
      expect(ColorUtils.getErrorLight().a, 1.0);
    });

    test('getInfoWithOpacity returns a Color with the given opacity', () {
      final c = ColorUtils.getInfoWithOpacity(0.2);
      expect(c.a, closeTo(0.2, 0.01));
    });

    test('getInfoLight returns a non-transparent Color', () {
      expect(ColorUtils.getInfoLight().a, 1.0);
    });

    test('getPrimaryWithOpacity returns a Color with the given opacity', () {
      final c = ColorUtils.getPrimaryWithOpacity(0.6);
      expect(c.a, closeTo(0.6, 0.01));
    });

    test('getPrimaryLight returns AppTheme.primaryLight', () {
      expect(ColorUtils.getPrimaryLight(), AppTheme.primaryLight);
    });

    test('getPrimaryLighter returns a non-transparent Color', () {
      expect(ColorUtils.getPrimaryLighter().a, 1.0);
    });
  });

  group('ColorUtils – gradient helpers', () {
    test('getPrimaryGradient returns a LinearGradient with 2 colors', () {
      final g = ColorUtils.getPrimaryGradient();
      expect(g, isA<LinearGradient>());
      expect(g.colors.length, 2);
    });

    test('getSuccessGradient returns a LinearGradient with 2 colors', () {
      final g = ColorUtils.getSuccessGradient();
      expect(g, isA<LinearGradient>());
      expect(g.colors.length, 2);
    });

    test('getInfoGradient returns a LinearGradient with 2 colors', () {
      final g = ColorUtils.getInfoGradient();
      expect(g, isA<LinearGradient>());
      expect(g.colors.length, 2);
    });
  });

  group('ColorUtils – chart colors', () {
    test('getChartPrimary returns AppTheme.primary', () {
      expect(ColorUtils.getChartPrimary(), AppTheme.primary);
    });

    test('getChartSecondary returns a Color', () {
      expect(ColorUtils.getChartSecondary(), isA<Color>());
    });

    test('getChartTertiary returns a Color', () {
      expect(ColorUtils.getChartTertiary(), isA<Color>());
    });

    test('getChartQuaternary returns a Color', () {
      expect(ColorUtils.getChartQuaternary(), isA<Color>());
    });
  });

  group('ColorUtils – platform-specific helpers (widget tests)', () {
    testWidgets('getCardBackgroundForPlatform returns a Color', (tester) async {
      // Verifies the platform-specific card background returns a valid Color.
      late Color result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          result = ColorUtils.getCardBackgroundForPlatform(ctx);
          return const SizedBox();
        }),
      ));
      expect(result, isA<Color>());
    });

    testWidgets('getElevatedButtonColor returns a Color', (tester) async {
      // Verifies the elevated button color method returns a valid Color.
      late Color result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          result = ColorUtils.getElevatedButtonColor(ctx);
          return const SizedBox();
        }),
      ));
      expect(result, isA<Color>());
    });

    testWidgets('getShadowColor returns a Color with opacity < 1', (tester) async {
      // Verifies the shadow color method returns a semi-transparent Color.
      late Color result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          result = ColorUtils.getShadowColor(ctx);
          return const SizedBox();
        }),
      ));
      expect(result.a, lessThan(1.0));
    });
  });
}
