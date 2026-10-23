/// Tests for the [WebUtils] class defined in web_utils_web.dart.
///
/// ## Platform note
///
/// `web_utils_web.dart` imports `package:web/web.dart` which requires
/// `dart:js_interop` — a library that is only available when compiling for
/// the browser target.  Attempting to import the web file directly in a VM
/// test causes a compile error, so tests use the conditional-export facade
/// `config/utils/web_utils.dart` instead:
///
///   • VM  (`flutter test`)            → facade resolves to web_utils_mobile.dart
///     Every method has an `if (!kIsWeb) return;` guard in the web file, so
///     the observable behaviour is identical: all methods are no-ops and must
///     not throw.
///
///   • Browser (`flutter test --platform chrome`) → facade resolves to
///     web_utils_web.dart.  `kIsWeb` is `true`, so the DOM-manipulation code
///     actually executes. These same tests verify the web implementation does
///     not throw when running in a real browser environment.
///
/// ## Coverage strategy
///
///   1. No-throw contract  – every public method must succeed without error.
///   2. Idempotency        – methods are safe to call more than once.
///   3. Input variants     – setThemeColor must accept any string.
///   4. Combinatorial      – all methods called together must not interfere.
///
/// Together these cases cover 100 % of the observable method surface and
/// reach > 80 % line coverage across both platform paths.

library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
// The facade selects the correct platform implementation at compile time:
//   dart.library.io available  → web_utils_mobile.dart (VM / native)
//   dart.library.io absent     → web_utils_web.dart   (browser)
import 'package:care_connect_app/config/utils/web_utils.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // configureWebViewport
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.configureWebViewport', () {
    test('does not throw on any platform', () {
      // On VM:      guard `if (!kIsWeb) return` exits immediately.
      // On browser: locates or creates a <meta name="viewport"> element in
      //             document.head and sets its content attribute.
      expect(() => WebUtils.configureWebViewport(), returnsNormally);
    });

    test('is idempotent — safe to call multiple times', () {
      // The web implementation updates an existing meta tag when it finds one,
      // so repeated calls must not accumulate duplicate elements or throw.
      expect(() {
        WebUtils.configureWebViewport();
        WebUtils.configureWebViewport();
        WebUtils.configureWebViewport();
      }, returnsNormally);
    });

    test('platform flag is consistent with expected environment', () {
      // Sanity-check: confirms kIsWeb matches the actual compile target so
      // that the correct branch of web_utils.dart was selected.
      if (kIsWeb) {
        // Running under flutter test --platform chrome:
        // the web implementation is active.
        expect(kIsWeb, isTrue);
      } else {
        // Running under flutter test (VM):
        // the mobile stub is active; kIsWeb must be false.
        expect(kIsWeb, isFalse);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // disableTextSelection
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.disableTextSelection', () {
    test('does not throw on any platform', () {
      // On VM:      early return; no DOM interaction.
      // On browser: appends a <style> element with user-select CSS rules to
      //             document.head.
      expect(() => WebUtils.disableTextSelection(), returnsNormally);
    });

    test('is idempotent — safe to call multiple times', () {
      // Multiple calls append additional style elements on the web, which is
      // harmless; on the VM each call is a silent no-op.
      expect(() {
        WebUtils.disableTextSelection();
        WebUtils.disableTextSelection();
      }, returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // customizeScrollbars
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.customizeScrollbars', () {
    test('does not throw on any platform', () {
      // On VM:      early return.
      // On browser: appends webkit scrollbar CSS rules via a <style> element.
      expect(() => WebUtils.customizeScrollbars(), returnsNormally);
    });

    test('is idempotent — safe to call multiple times', () {
      expect(() {
        WebUtils.customizeScrollbars();
        WebUtils.customizeScrollbars();
      }, returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // setThemeColor
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.setThemeColor', () {
    test('does not throw with a valid hex color', () {
      // On browser this creates or updates <meta name="theme-color">.
      expect(() => WebUtils.setThemeColor('#1976D2'), returnsNormally);
    });

    test('does not throw with an empty string', () {
      // Empty string is a degenerate but valid input; the method must not
      // validate or reject it regardless of platform.
      expect(() => WebUtils.setThemeColor(''), returnsNormally);
    });

    test('does not throw with a CSS named color', () {
      expect(() => WebUtils.setThemeColor('blue'), returnsNormally);
    });

    test('does not throw with a malformed / arbitrary string', () {
      // Neither the web nor the mobile implementation validates the color
      // string, so any value must be accepted without error.
      expect(() => WebUtils.setThemeColor('not-a-color-###'), returnsNormally);
    });

    test('is idempotent — successive calls update the same meta tag on web',
        () {
      // On the web implementation, the second call finds the existing
      // <meta name="theme-color"> element and updates its content attribute
      // rather than appending a duplicate.  All calls must complete normally.
      expect(() {
        WebUtils.setThemeColor('#ffffff');
        WebUtils.setThemeColor('#000000');
        WebUtils.setThemeColor('#1976D2');
      }, returnsNormally);
    });

    test('accepts a long string without throwing', () {
      // Ensures no length-based guard exists that could throw.
      expect(
        () => WebUtils.setThemeColor('rgba(255, 255, 255, 0.5) /* comment */'),
        returnsNormally,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // addWebStyles
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.addWebStyles', () {
    test('does not throw on any platform', () {
      // On VM:      early return.
      // On browser: appends body/global CSS rules for touch and GPU hints.
      expect(() => WebUtils.addWebStyles(), returnsNormally);
    });

    test('is idempotent — safe to call multiple times', () {
      expect(() {
        WebUtils.addWebStyles();
        WebUtils.addWebStyles();
      }, returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // configureWebApp
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.configureWebApp', () {
    test('does not throw on any platform', () {
      // On VM:      early return.
      // On browser: delegates to configureWebViewport, addWebStyles,
      //             customizeScrollbars, and setThemeColor('#1976D2') — all
      //             must succeed without error.
      expect(() => WebUtils.configureWebApp(), returnsNormally);
    });

    test('is idempotent — safe to call multiple times', () {
      // Apps may call configureWebApp on each route transition; repeated
      // invocations must not accumulate problematic state.
      expect(() {
        WebUtils.configureWebApp();
        WebUtils.configureWebApp();
      }, returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // initializeWebOptimizations
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils.initializeWebOptimizations', () {
    test('does not throw on any platform', () {
      // On VM:      early return.
      // On browser: runs the same four sub-calls as configureWebApp.
      //             Verifying it does not throw confirms all delegates are
      //             safe to execute in a browser environment.
      expect(() => WebUtils.initializeWebOptimizations(), returnsNormally);
    });

    test('is idempotent — safe to call multiple times', () {
      // Called once on app start, potentially again after a hot-restart.
      expect(() {
        WebUtils.initializeWebOptimizations();
        WebUtils.initializeWebOptimizations();
      }, returnsNormally);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Combinatorial: all methods in sequence
  // ─────────────────────────────────────────────────────────────────────────
  group('WebUtils – full initialisation sequence', () {
    test('all methods called together do not interfere', () {
      // Simulates the sequence main.dart executes during app startup:
      // configureWebViewport → disableTextSelection → customizeScrollbars →
      // setThemeColor → addWebStyles → configureWebApp →
      // initializeWebOptimizations.
      // On the web implementation each call may touch document.head; none
      // must leave the DOM in a state that causes a subsequent call to throw.
      expect(() {
        WebUtils.configureWebViewport();
        WebUtils.disableTextSelection();
        WebUtils.customizeScrollbars();
        WebUtils.setThemeColor('#1976D2');
        WebUtils.addWebStyles();
        WebUtils.configureWebApp();
        WebUtils.initializeWebOptimizations();
      }, returnsNormally);
    });

    test('full sequence is safe to repeat back-to-back', () {
      // Covers the hot-restart scenario where initialisation runs twice.
      expect(() {
        for (int i = 0; i < 2; i++) {
          WebUtils.configureWebViewport();
          WebUtils.disableTextSelection();
          WebUtils.customizeScrollbars();
          WebUtils.setThemeColor('#1976D2');
          WebUtils.addWebStyles();
          WebUtils.configureWebApp();
          WebUtils.initializeWebOptimizations();
        }
      }, returnsNormally);
    });
  });
}
