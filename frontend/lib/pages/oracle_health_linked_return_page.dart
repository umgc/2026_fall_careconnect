import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Web landing page after Oracle Health SMART authorization.
///
/// The backend redirects here with ?status=ok or ?status=error.
/// The Settings connection tile checks the backend for the actual
/// connection state when Settings is opened again.
class OracleHealthLinkedReturnPage extends StatefulWidget {
  const OracleHealthLinkedReturnPage({
    super.key,
    this.status,
  });

  final String? status;

  @override
  State<OracleHealthLinkedReturnPage> createState() =>
      _OracleHealthLinkedReturnPageState();
}

class _OracleHealthLinkedReturnPageState
    extends State<OracleHealthLinkedReturnPage> {
  Timer? _redirectTimer;

  bool get _successful => widget.status == 'ok';

  @override
  void initState() {
    super.initState();

    _redirectTimer = Timer(
      const Duration(seconds: 3),
      _returnToSettings,
    );
  }

  @override
  void dispose() {
    _redirectTimer?.cancel();
    super.dispose();
  }

  void _returnToSettings() {
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
                _successful ? Icons.check_circle_outline : Icons.error_outline,
                color: _successful ? Colors.green : Colors.orange,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _successful
                    ? 'Oracle Health connected'
                    : 'Oracle Health connection was not completed',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _successful
                    ? 'Your Oracle Health account was linked successfully. '
                        'CareConnect will now check your connection status.'
                    : 'You can try connecting again from Settings.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _returnToSettings,
                child: const Text('Return to Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
