import 'package:flutter/material.dart';

import '../services/oracle_health_service.dart';

/// Oracle Health SMART-on-FHIR connection controls for Settings.
class OracleHealthConnectTile extends StatefulWidget {
  const OracleHealthConnectTile({
    super.key,
    this.client = const DefaultOracleHealthConnectionClient(),
  });

  final OracleHealthConnectionClient client;

  @override
  State<OracleHealthConnectTile> createState() =>
      _OracleHealthConnectTileState();
}

class _OracleHealthConnectTileState extends State<OracleHealthConnectTile>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _busy = false;
  bool _statusUnavailable = false;
  OracleHealthConnectionStatus? _connection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final result = await widget.client.status();
      if (!mounted) return;

      setState(() {
        _connection = result;
        _statusUnavailable = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _statusUnavailable = true;
        _loading = false;
      });
    }
  }

  Future<void> _connect() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      await widget.client.connect();

      if (!mounted) return;

      // On mobile, the browser may return after this method completes.
      // didChangeAppLifecycleState will refresh connection status.
      await _refresh();
    } catch (_) {
      _showMessage('Unable to start Oracle Health connection.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disconnect() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Oracle Health?'),
        content: const Text(
          'CareConnect will no longer be connected to your '
          'Oracle Health account. You can reconnect later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() => _busy = true);

    try {
      await widget.client.disconnect();
      if (!mounted) return;

      _showMessage('Oracle Health disconnected.');
      await _refresh();
    } catch (_) {
      _showMessage('Unable to disconnect Oracle Health.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _connected => _connection?.connected == true;

  bool get _authorizationExpired {
    final status = _connection?.status?.toUpperCase();
    return status == 'EXPIRED' ||
        status == 'REAUTH_REQUIRED' ||
        status == 'REAUTHORIZATION_REQUIRED';
  }

  String get _subtitle {
    if (_loading) {
      return 'Checking Oracle Health connection...';
    }

    if (_statusUnavailable) {
      return 'Unable to check Oracle Health connection.';
    }

    if (_connected) {
      return 'Connected to Oracle Health';
    }

    if (_authorizationExpired) {
      return 'Authorization expired. Reconnect to continue.';
    }

    return 'Connect to access your Oracle Health records';
  }

  Widget _buildAction() {
    if (_loading || _busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (_statusUnavailable) {
      return TextButton(
        onPressed: _refresh,
        child: const Text('Retry'),
      );
    }

    if (_connected) {
      return TextButton(
        onPressed: _disconnect,
        child: const Text('Disconnect'),
      );
    }

    return FilledButton(
      onPressed: _connect,
      child: Text(_authorizationExpired ? 'Reconnect' : 'Connect'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_hospital_outlined),
        title: const Text('Oracle Health (Cerner)'),
        subtitle: Text(_subtitle),
        trailing: _buildAction(),
      ),
    );
  }
}
