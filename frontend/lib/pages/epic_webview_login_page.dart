import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// In-app Epic (MyChart) SMART-on-FHIR sign-in (Epic Phase 0).
///
/// Loads the backend-issued `authUrl` in an embedded [WebView] so the patient signs in without
/// leaving the app. The backend callback finishes the token exchange and then redirects to the
/// `careconnect://epic/linked?status=ok|error` deep link (see `EpicOAuthController`); this page
/// intercepts that redirect (a custom scheme the WebView can't load), reads `status`, and pops
/// with `true` on success. The caller (`EpicConnectTile`) then re-polls `GET /api/epic/status`.
///
/// Mobile only (Android/iOS) — `webview_flutter` has no web backend, so on web the connect flow
/// keeps the full-page redirect in `EpicService.connect()`.
class EpicWebViewLoginPage extends StatefulWidget {
  const EpicWebViewLoginPage({super.key, required this.authUrl});

  /// The Epic authorize URL returned by `GET /api/epic/authorize`.
  final String authUrl;

  @override
  State<EpicWebViewLoginPage> createState() => _EpicWebViewLoginPageState();
}

class _EpicWebViewLoginPageState extends State<EpicWebViewLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  // Guards against a double pop if the return URL fires more than one navigation event.
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_isReturnUrl(request.url)) {
              _finish(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (url) {
            // A redirect to the custom-scheme deep link can surface here rather than as a
            // navigation request on some platforms — treat it the same way.
            if (_isReturnUrl(url)) {
              _finish(url);
              return;
            }
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    _controller = controller;
  }

  /// True for the Epic connect return trip: the `careconnect://epic/linked` deep link (mobile) or,
  /// defensively, the `/epic-linked` web-return route.
  bool _isReturnUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final isDeepLink = uri.scheme == 'careconnect' && uri.host == 'epic';
    final isWebReturn = uri.path.contains('epic-linked');
    return isDeepLink || isWebReturn;
  }

  void _finish(String url) {
    if (_completed || !mounted) return;
    _completed = true;
    final status = Uri.tryParse(url)?.queryParameters['status'];
    // Reaching the return URL means the callback ran; treat anything but an explicit error as ok.
    Navigator.of(context).pop(status != 'error');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to Epic'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () {
            if (!_completed) Navigator.of(context).pop(false);
          },
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
