import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_token_manager.dart';
import '../services/oracle_health_service.dart';
import '../services/pending_oracle_health_launch.dart';

typedef OracleHealthAuthHeadersLoader = Future<Map<String, String>> Function();
typedef OracleHealthConnector = Future<void> Function({String? launch});

/// Entry point for an Oracle Health EHR-initiated SMART launch.
class OracleHealthLaunchPage extends StatefulWidget {
  const OracleHealthLaunchPage({
    super.key,
    this.errorMessage,
    this.authHeadersLoader = AuthTokenManager.getAuthHeaders,
    this.connector = OracleHealthService.connect,
  });

  final String? errorMessage;
  final OracleHealthAuthHeadersLoader authHeadersLoader;
  final OracleHealthConnector connector;

  @override
  State<OracleHealthLaunchPage> createState() => _OracleHealthLaunchPageState();
}

class _OracleHealthLaunchPageState extends State<OracleHealthLaunchPage> {
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();

    if (widget.errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startAuthorization();
        }
      });
    }
  }

  Future<void> _startAuthorization() async {
    if (_started) return;
    _started = true;

    try {
      final headers = await widget.authHeadersLoader();
      final hasAuthorization =
          (headers['Authorization'] ?? '').trim().isNotEmpty;

      if (!mounted) return;

      if (!hasAuthorization) {
        context.go('/login');
        return;
      }

      final pending = PendingOracleHealthLaunch.take();

      if (pending == null) {
        setState(() {
          _error = 'No pending Oracle Health launch was found.';
        });
        return;
      }

      await widget.connector(
        launch: pending.launch,
      );
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'Unable to start Oracle Health authorization. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.errorMessage ?? _error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Oracle Health Connection'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) ...[
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  error,
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                const Text(
                  'Preparing Oracle Health connection...',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
