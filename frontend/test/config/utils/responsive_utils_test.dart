import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/config/utils/responsive_utils.dart';

/// Injects a [MediaQuery] with the given [size] and captures a value from
/// [BuildContext] via [fn]. This is more reliable than [setSurfaceSize]
/// because it controls [MediaQuery.of(context)] directly without depending
/// on binding-level surface size propagation timing.
Future<T> _withSize<T>(
  WidgetTester tester,
  Size size,
  T Function(BuildContext) fn,
) async {
  late T result;
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(builder: (context) {
          result = fn(context);
          return const SizedBox.shrink();
        }),
      ),
    ),
  );
  return result;
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────────
  // Breakpoint constants
  // ─────────────────────────────────────────────────────────────────────────────
  group('Breakpoint constants', () {
    test('mobileBreakpoint is 600', () {
      // Verifies the documented mobile breakpoint value has not been changed.
      expect(ResponsiveUtils.mobileBreakpoint, 600);
    });

    test('tabletBreakpoint is 900', () {
      // Verifies the documented tablet breakpoint value has not been changed.
      expect(ResponsiveUtils.tabletBreakpoint, 900);
    });

    test('desktopBreakpoint is 1200', () {
      // Verifies the documented desktop breakpoint value has not been changed.
      expect(ResponsiveUtils.desktopBreakpoint, 1200);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getDeviceType – all branches + boundary conditions
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getDeviceType', () {
    testWidgets('returns mobile when width < 600', (tester) async {
      // Width 400 is well below the 600-px mobile breakpoint.
      final type = await _withSize(
        tester,
        const Size(400, 800),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.mobile);
    });

    testWidgets('returns mobile at exactly width 599 (one below breakpoint)',
        (tester) async {
      // Boundary: 599 is still mobile (strict less-than comparison).
      final type = await _withSize(
        tester,
        const Size(599, 800),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.mobile);
    });

    testWidgets('returns tablet when width == mobileBreakpoint (600)',
        (tester) async {
      // At exactly 600 the condition `width < 600` is false, so result is tablet.
      final type = await _withSize(
        tester,
        const Size(600, 800),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.tablet);
    });

    testWidgets('returns tablet for mid-range widths (800)', (tester) async {
      // 800 is between 600 and 900, so tablet range.
      final type = await _withSize(
        tester,
        const Size(800, 800),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.tablet);
    });

    testWidgets('returns tablet at exactly width 899 (one below tablet upper)',
        (tester) async {
      final type = await _withSize(
        tester,
        const Size(899, 800),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.tablet);
    });

    testWidgets('returns desktop when width == tabletBreakpoint (900)',
        (tester) async {
      // At exactly 900 the condition `width < 900` is false, so result is desktop.
      final type = await _withSize(
        tester,
        const Size(900, 800),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.desktop);
    });

    testWidgets('returns desktop for large widths (1400)', (tester) async {
      final type = await _withSize(
        tester,
        const Size(1400, 900),
        ResponsiveUtils.getDeviceType,
      );
      expect(type, DeviceType.desktop);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Platform detection (smoke tests – actual value is platform-dependent)
  // ─────────────────────────────────────────────────────────────────────────────
  group('Platform detection getters', () {
    test('isMobile does not throw', () {
      // In the test VM these return false; we just verify no exception is raised.
      expect(() => ResponsiveUtils.isMobile, returnsNormally);
    });

    test('isWeb does not throw', () {
      expect(() => ResponsiveUtils.isWeb, returnsNormally);
    });

    test('isIOS does not throw', () {
      expect(() => ResponsiveUtils.isIOS, returnsNormally);
    });

    test('isAndroid does not throw', () {
      expect(() => ResponsiveUtils.isAndroid, returnsNormally);
    });

    test('isMobile is false in the test VM (neither Android nor iOS)', () {
      // Flutter unit tests run on a host VM, so Platform.isAndroid/isIOS are
      // both false – hence isMobile must also be false.
      expect(ResponsiveUtils.isMobile, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // isLandscape
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.isLandscape', () {
    testWidgets('returns true when width > height (landscape)', (tester) async {
      // A surface wider than it is tall should be considered landscape.
      // MediaQueryData derives orientation from the size automatically.
      final result = await _withSize(
        tester,
        const Size(1024, 600),
        ResponsiveUtils.isLandscape,
      );
      expect(result, isTrue);
    });

    testWidgets('returns false when height > width (portrait)', (tester) async {
      // A surface taller than it is wide is portrait.
      final result = await _withSize(
        tester,
        const Size(400, 800),
        ResponsiveUtils.isLandscape,
      );
      expect(result, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getResponsivePadding
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getResponsivePadding', () {
    testWidgets('returns 16/12 padding for mobile (width 400)', (tester) async {
      // Mobile devices should use tight padding to preserve screen real-estate.
      final padding = await _withSize(
        tester,
        const Size(400, 800),
        ResponsiveUtils.getResponsivePadding,
      );
      expect(padding, const EdgeInsets.symmetric(horizontal: 16, vertical: 12));
    });

    testWidgets('returns 24/16 padding for tablet (width 800)', (tester) async {
      // Tablets have more room, so padding increases.
      final padding = await _withSize(
        tester,
        const Size(800, 1200),
        ResponsiveUtils.getResponsivePadding,
      );
      expect(padding, const EdgeInsets.symmetric(horizontal: 24, vertical: 16));
    });

    testWidgets('returns 32/24 padding for desktop (width 1200)',
        (tester) async {
      // Desktop gets the most generous padding.
      final padding = await _withSize(
        tester,
        const Size(1200, 900),
        ResponsiveUtils.getResponsivePadding,
      );
      expect(padding, const EdgeInsets.symmetric(horizontal: 32, vertical: 24));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getResponsiveFontSize
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getResponsiveFontSize', () {
    const base = 16.0;

    testWidgets('returns base size on mobile (width 400)', (tester) async {
      // Mobile uses the base font size unmodified.
      final size = await _withSize(
        tester,
        const Size(400, 800),
        (ctx) => ResponsiveUtils.getResponsiveFontSize(ctx, base),
      );
      expect(size, base);
    });

    testWidgets('returns base * 1.1 on tablet (width 800)', (tester) async {
      // Tablet scales up slightly for readability on larger screens.
      final size = await _withSize(
        tester,
        const Size(800, 1200),
        (ctx) => ResponsiveUtils.getResponsiveFontSize(ctx, base),
      );
      expect(size, closeTo(base * 1.1, 0.001));
    });

    testWidgets('returns base * 1.2 on desktop (width 1200)', (tester) async {
      // Desktop has the largest font scaling.
      final size = await _withSize(
        tester,
        const Size(1200, 900),
        (ctx) => ResponsiveUtils.getResponsiveFontSize(ctx, base),
      );
      expect(size, closeTo(base * 1.2, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getResponsiveIconSize
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getResponsiveIconSize', () {
    const base = 24.0;

    testWidgets('returns base size on mobile (width 400)', (tester) async {
      final size = await _withSize(
        tester,
        const Size(400, 800),
        (ctx) => ResponsiveUtils.getResponsiveIconSize(ctx, base),
      );
      expect(size, base);
    });

    testWidgets('returns base * 1.2 on tablet (width 800)', (tester) async {
      final size = await _withSize(
        tester,
        const Size(800, 1200),
        (ctx) => ResponsiveUtils.getResponsiveIconSize(ctx, base),
      );
      expect(size, closeTo(base * 1.2, 0.001));
    });

    testWidgets('returns base * 1.4 on desktop (width 1200)', (tester) async {
      final size = await _withSize(
        tester,
        const Size(1200, 900),
        (ctx) => ResponsiveUtils.getResponsiveIconSize(ctx, base),
      );
      expect(size, closeTo(base * 1.4, 0.001));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getCardElevation
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getCardElevation', () {
    test('returns a non-negative elevation value', () {
      // The specific value depends on the platform; we verify a sensible result.
      expect(ResponsiveUtils.getCardElevation(), greaterThanOrEqualTo(0));
    });

    test('returns 2 in the test host environment (not web, not iOS)', () {
      // On the test host VM isWeb and isIOS are both false, so the fallback
      // Android/other branch returns 2.
      expect(ResponsiveUtils.getCardElevation(), 2.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getSafeAreaPadding
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getSafeAreaPadding', () {
    testWidgets('returns an EdgeInsets (does not throw)', (tester) async {
      // We inject a MediaQueryData with explicit padding to verify the method
      // correctly delegates to MediaQuery.of(context).padding.
      late EdgeInsets padding;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: EdgeInsets.fromLTRB(0, 44, 0, 34),
            ),
            child: Builder(builder: (context) {
              padding = ResponsiveUtils.getSafeAreaPadding(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(padding, isA<EdgeInsets>());
    });

    testWidgets('returns the MediaQuery padding value unchanged', (tester) async {
      // getSafeAreaPadding should be a transparent wrapper around
      // MediaQuery.of(context).padding.
      const expected = EdgeInsets.fromLTRB(0, 44, 0, 34);
      late EdgeInsets padding;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              padding: expected,
            ),
            child: Builder(builder: (context) {
              padding = ResponsiveUtils.getSafeAreaPadding(context);
              return const SizedBox.shrink();
            }),
          ),
        ),
      );
      expect(padding, expected);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getResponsiveWidth
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getResponsiveWidth', () {
    testWidgets('returns 50% of screen width correctly', (tester) async {
      // 50% of an 800-px wide surface should be 400.
      const surfaceWidth = 800.0;
      final width = await _withSize(
        tester,
        const Size(surfaceWidth, 600),
        (ctx) => ResponsiveUtils.getResponsiveWidth(ctx, 50),
      );
      expect(width, closeTo(surfaceWidth * 0.5, 0.001));
    });

    testWidgets('returns 100% of screen width correctly', (tester) async {
      // 100% should equal the full surface width.
      const surfaceWidth = 1024.0;
      final width = await _withSize(
        tester,
        const Size(surfaceWidth, 768),
        (ctx) => ResponsiveUtils.getResponsiveWidth(ctx, 100),
      );
      expect(width, closeTo(surfaceWidth, 0.001));
    });

    testWidgets('returns 0 for 0%', (tester) async {
      final width = await _withSize(
        tester,
        const Size(800, 600),
        (ctx) => ResponsiveUtils.getResponsiveWidth(ctx, 0),
      );
      expect(width, 0.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getResponsiveHeight
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getResponsiveHeight', () {
    testWidgets('returns 50% of screen height correctly', (tester) async {
      // 50% of an 800-px tall surface should be 400.
      const surfaceHeight = 800.0;
      final height = await _withSize(
        tester,
        const Size(400, surfaceHeight),
        (ctx) => ResponsiveUtils.getResponsiveHeight(ctx, 50),
      );
      expect(height, closeTo(surfaceHeight * 0.5, 0.001));
    });

    testWidgets('returns 100% of screen height correctly', (tester) async {
      const surfaceHeight = 1024.0;
      final height = await _withSize(
        tester,
        const Size(768, surfaceHeight),
        (ctx) => ResponsiveUtils.getResponsiveHeight(ctx, 100),
      );
      expect(height, closeTo(surfaceHeight, 0.001));
    });

    testWidgets('returns 0 for 0%', (tester) async {
      final height = await _withSize(
        tester,
        const Size(800, 600),
        (ctx) => ResponsiveUtils.getResponsiveHeight(ctx, 0),
      );
      expect(height, 0.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // getBorderRadius
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.getBorderRadius', () {
    test('returns a non-negative radius', () {
      // The exact value is platform-dependent; any non-negative value is valid.
      expect(ResponsiveUtils.getBorderRadius(), greaterThanOrEqualTo(0));
    });

    test('returns 8 in test environment (not iOS)', () {
      // On the test host VM isIOS is false, so the fallback (Android/Web)
      // branch returns 8.
      expect(ResponsiveUtils.getBorderRadius(), 8.0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // shouldUseDesktopUI
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveUtils.shouldUseDesktopUI', () {
    testWidgets('returns false when width < tabletBreakpoint (400)',
        (tester) async {
      // Narrow screens should not use desktop UI.
      final result = await _withSize(
        tester,
        const Size(400, 800),
        ResponsiveUtils.shouldUseDesktopUI,
      );
      expect(result, isFalse);
    });

    testWidgets('returns false when width is 899 (one below breakpoint)',
        (tester) async {
      final result = await _withSize(
        tester,
        const Size(899, 600),
        ResponsiveUtils.shouldUseDesktopUI,
      );
      expect(result, isFalse);
    });

    testWidgets('returns true when width == tabletBreakpoint (900)',
        (tester) async {
      // The boundary: at exactly 900 desktop UI should activate.
      final result = await _withSize(
        tester,
        const Size(900, 600),
        ResponsiveUtils.shouldUseDesktopUI,
      );
      expect(result, isTrue);
    });

    testWidgets('returns true when width > tabletBreakpoint (1400)',
        (tester) async {
      final result = await _withSize(
        tester,
        const Size(1400, 900),
        ResponsiveUtils.shouldUseDesktopUI,
      );
      expect(result, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // ResponsiveBuilder widget
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResponsiveBuilder widget', () {
    /// Builds a [ResponsiveBuilder] inside an injected [MediaQuery] of [size].
    Widget buildTree(Size size, Key mobileKey, Key tabletKey, Key desktopKey) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: ResponsiveBuilder(
            builder: (context, deviceType) {
              switch (deviceType) {
                case DeviceType.mobile:
                  return Container(key: mobileKey);
                case DeviceType.tablet:
                  return Container(key: tabletKey);
                case DeviceType.desktop:
                  return Container(key: desktopKey);
              }
            },
          ),
        ),
      );
    }

    testWidgets('renders mobile child at width 400', (tester) async {
      // Confirms the builder callback receives DeviceType.mobile.
      const mk = Key('m');
      const tk = Key('t');
      const dk = Key('d');
      await tester.pumpWidget(buildTree(const Size(400, 800), mk, tk, dk));
      expect(find.byKey(mk), findsOneWidget);
      expect(find.byKey(tk), findsNothing);
      expect(find.byKey(dk), findsNothing);
    });

    testWidgets('renders tablet child at width 800', (tester) async {
      // Confirms the builder callback receives DeviceType.tablet.
      const mk = Key('m');
      const tk = Key('t');
      const dk = Key('d');
      await tester.pumpWidget(buildTree(const Size(800, 1200), mk, tk, dk));
      expect(find.byKey(mk), findsNothing);
      expect(find.byKey(tk), findsOneWidget);
      expect(find.byKey(dk), findsNothing);
    });

    testWidgets('renders desktop child at width 1200', (tester) async {
      // Confirms the builder callback receives DeviceType.desktop.
      const mk = Key('m');
      const tk = Key('t');
      const dk = Key('d');
      await tester.pumpWidget(buildTree(const Size(1200, 800), mk, tk, dk));
      expect(find.byKey(mk), findsNothing);
      expect(find.byKey(tk), findsNothing);
      expect(find.byKey(dk), findsOneWidget);
    });

    testWidgets('updates child when MediaQuery size changes from mobile to desktop',
        (tester) async {
      // Verifies that ResponsiveBuilder reacts correctly to a MediaQuery update
      // (e.g. simulating a window resize on desktop).
      const mk = Key('m');
      const tk = Key('t');
      const dk = Key('d');

      // Start at mobile width.
      await tester.pumpWidget(buildTree(const Size(400, 800), mk, tk, dk));
      expect(find.byKey(mk), findsOneWidget);

      // Switch to desktop width by pumping a new tree with updated MediaQuery.
      await tester.pumpWidget(buildTree(const Size(1400, 900), mk, tk, dk));
      await tester.pumpAndSettle();
      expect(find.byKey(dk), findsOneWidget);
      expect(find.byKey(mk), findsNothing);
    });
  });
}
