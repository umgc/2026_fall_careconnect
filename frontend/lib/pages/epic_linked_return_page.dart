import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Web landing target for the Epic connect return trip.
///
/// On web there is no `careconnect://epic/linked` deep link, so the backend callback redirects the
/// browser here (`/epic-linked?status=ok|error`, see `EpicOAuthController` + `epic.oauth.web-return-url`).
/// This page shows a brief result and then routes the user back to Settings, where `EpicConnectTile`
/// re-polls `GET /api/epic/status` on init and flips to the "Connected" state.
///
/// Mobile (Android/iOS) is unaffected — it still returns via the deep link handled in `main.dart`.
class EpicLinkedReturnPage extends StatefulWidget {
  final String? status;
  const EpicLinkedReturnPage({super.key, this.status});

  @override
  State<EpicLinkedReturnPage> createState() => _EpicLinkedReturnPageState();
}

class _EpicLinkedReturnPageState extends State<EpicLinkedReturnPage> {
  Timer? _redirectTimer;

  bool get _ok => widget.status == 'ok';

  @override
  void initState() {
    super.initState();
    // Auto-return to Settings so the Epic tile refreshes; the user can also tap the button.
    _redirectTimer = Timer(const Duration(seconds: 3), _goToSettings);
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  void _goToSettings() {
    if (!mounted) return;
    context.go('/settings');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _ok ? Icons.check_circle_outline : Icons.error_outline,
                color: _ok ? Colors.green : Colors.orange,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _ok ? 'Epic connected' : 'Epic connection was not completed',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _ok
                    ? 'Your clinical records are importing in the background and will help answer Ask AI.'
                    : 'You can try connecting again from Settings.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _goToSettings,
                child: const Text('Return to Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
