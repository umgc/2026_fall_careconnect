// In-memory WebView platform for widget tests.
//
// webview_flutter needs a platform implementation (WebViewPlatform.instance)
// before a WebViewController can be constructed. Widget tests have no native
// WebView, so this fake records what the app asks the WebView to do and lets
// the test drive the page lifecycle and JavaScript-channel messages by hand.
//
// Usage:
//   final platform = FakeWebViewPlatform();
//   WebViewPlatform.instance = platform;
//   ... pump a widget that creates a WebViewController ...
//   final controller = platform.controllers.single;
//   controller.finishPage();                         // fires onPageFinished
//   controller.sendToChannel('Bridge', '{"a":1}');   // JS -> Flutter message

import 'package:flutter/widgets.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class FakeWebViewPlatform extends WebViewPlatform {
  final List<FakePlatformWebViewController> controllers =
      <FakePlatformWebViewController>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = FakePlatformWebViewController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return FakePlatformNavigationDelegate(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return FakePlatformWebViewWidget(params);
  }
}

class FakePlatformWebViewController extends PlatformWebViewController {
  FakePlatformWebViewController(super.params) : super.implementation();

  final Map<String, JavaScriptChannelParams> channels =
      <String, JavaScriptChannelParams>{};
  final List<String> scripts = <String>[];
  String? loadedHtml;
  String? loadedBaseUrl;
  FakePlatformNavigationDelegate? navigationDelegate;

  /// When true, [runJavaScript] throws, as a torn-down WebView would.
  bool failJavaScript = false;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    channels[javaScriptChannelParams.name] = javaScriptChannelParams;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    navigationDelegate = handler as FakePlatformNavigationDelegate;
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    loadedHtml = html;
    loadedBaseUrl = baseUrl;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {}

  @override
  Future<void> runJavaScript(String javaScript) async {
    if (failJavaScript) {
      throw StateError('WebView is gone');
    }
    scripts.add(javaScript);
  }

  /// Simulates the page calling `<channel>.postMessage(message)`.
  void sendToChannel(String channel, String message) {
    channels[channel]!.onMessageReceived(JavaScriptMessage(message: message));
  }

  void startPage([String url = 'https://localhost']) =>
      navigationDelegate?.onPageStarted?.call(url);

  void finishPage([String url = 'https://localhost']) =>
      navigationDelegate?.onPageFinished?.call(url);

  void failResource(WebResourceError error) =>
      navigationDelegate?.onWebResourceError?.call(error);
}

class FakePlatformNavigationDelegate extends PlatformNavigationDelegate {
  FakePlatformNavigationDelegate(super.params) : super.implementation();

  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onWebResourceError;

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    this.onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    this.onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    this.onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {}

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {}

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {}

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {}
}

class FakePlatformWebViewWidget extends PlatformWebViewWidget {
  FakePlatformWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: ValueKey<String>('fake-webview'));
}
