import 'package:web/web.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Utility class for web-specific functionality
/// These functions will only be used when running on web platforms
class WebUtils {
  /// Enable viewport meta for better responsive behavior on web
  static void configureWebViewport() {
    if (!kIsWeb) return;

    // Preserve responsive sizing without blocking browser pinch-zoom.
    final meta =
        document.querySelector('meta[name="viewport"]') as HTMLMetaElement?;
    if (meta != null) {
      meta.content = 'width=device-width, initial-scale=1.0';
    } else {
      final viewportMeta = HTMLMetaElement()
        ..name = 'viewport'
        ..content = 'width=device-width, initial-scale=1.0';
      document.head!.append(viewportMeta);
    }
  }

  /// Disable text selection on web
  static void disableTextSelection() {
    if (!kIsWeb) return;

    final styleElement = HTMLStyleElement()
      ..type = 'text/css'
      ..text = '''
        * {
          -webkit-user-select: none;
          -moz-user-select: none;
          -ms-user-select: none;
          user-select: none;
        }
        input, textarea {
          -webkit-user-select: text;
          -moz-user-select: text;
          -ms-user-select: text;
          user-select: text;
        }
      ''';
    document.head!.append(styleElement);
  }

  /// Enable scrollbar customization on web
  static void customizeScrollbars() {
    if (!kIsWeb) return;

    final styleElement = HTMLStyleElement()
      ..type = 'text/css'
      ..text = '''
        ::-webkit-scrollbar {
          width: 8px;
          height: 8px;
        }
        ::-webkit-scrollbar-track {
          background: #f1f1f1;
          border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb {
          background: #c1c1c1;
          border-radius: 4px;
        }
        ::-webkit-scrollbar-thumb:hover {
          background: #a8a8a8;
        }
      ''';
    document.head!.append(styleElement);
  }

  /// Set theme color for browser UI
  static void setThemeColor(String color) {
    if (!kIsWeb) return;

    var themeColor =
        document.querySelector('meta[name="theme-color"]') as HTMLMetaElement?;
    if (themeColor == null) {
      themeColor = HTMLMetaElement()
        ..name = 'theme-color'
        ..content = color;
      document.head!.append(themeColor);
    } else {
      themeColor.content = color;
    }
  }

  /// Add web-specific CSS styles
  static void addWebStyles() {
    if (!kIsWeb) return;

    final styleElement = HTMLStyleElement()
      ..type = 'text/css'
      ..text = '''
        body {
          margin: 0;
          padding: 0;
          overflow: hidden;
        }
        * {
          -webkit-tap-highlight-color: transparent;
          touch-action: manipulation;
        }
        .flutter-widget {
          transform: translateZ(0);
          backface-visibility: hidden;
          perspective: 1000px;
        }
      ''';
    document.head!.append(styleElement);
  }

  /// Configure web app manifest properties
  static void configureWebApp() {
    if (!kIsWeb) return;

    configureWebViewport();
    addWebStyles();
    customizeScrollbars();
    setThemeColor('#1976D2');
  }

  /// Initialize all web optimizations
  static void initializeWebOptimizations() {
    if (!kIsWeb) return;

    configureWebViewport();
    addWebStyles();
    customizeScrollbars();
    setThemeColor('#1976D2');
  }
}
