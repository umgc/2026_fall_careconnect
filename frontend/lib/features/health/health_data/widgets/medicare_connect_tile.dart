import 'package:flutter/material.dart';
import '../services/medicare_connect_service.dart';

/// Drop-in "Connect Medicare" tile for the integrations / settings area.
///
/// Mirrors Team D's EpicConnectTile: shows connection status, launches the
/// Blue Button OAuth connect flow, and offers Disconnect. Re-polls status when
/// the app resumes (after returning from the external browser). Wire it into
/// the integrations/settings screen next to the Epic tile, e.g.:
/// `const MedicareConnectTile()`.
class MedicareConnectTile extends StatefulWidget {
  const MedicareConnectTile({super.key});

  @override
  State<MedicareConnectTile> createState() => _MedicareConnectTileState();
}

class _MedicareConnectTileState extends State<MedicareConnectTile>
    with WidgetsBindingObserver {
  static const _teal = Color(0xFF00A7C8);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _success = Color(0xFF10B981);
  static const _error = Color(0xFFEF4444);

  bool _loading = true;
  bool _connected = false;
  bool _busy = false;

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
    // Re-check after returning from the external browser (Medicare consent).
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final status = await MedicareConnectService.status();
      if (!mounted) return;
      setState(() {
        _connected = status['connected'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      await MedicareConnectService.connect();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the Medicare connection.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    final ok = await MedicareConnectService.disconnect();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _connected = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: _teal, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Medicare',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _text)),
                const SizedBox(height: 2),
                _loading
                    ? const Text('Checking…',
                        style: TextStyle(color: _muted, fontSize: 13))
                    : _statusLine(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _action(),
        ],
      ),
    );
  }

  Widget _statusLine() {
    final color = _connected ? _success : _muted;
    return Row(
      children: [
        Icon(_connected ? Icons.check_circle : Icons.remove_circle_outline,
            size: 14, color: color),
        const SizedBox(width: 4),
        Text(_connected ? 'Connected' : 'Not connected',
            style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }

  Widget _action() {
    if (_busy || _loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
      );
    }
    if (_connected) {
      return TextButton(
        onPressed: _disconnect,
        child: const Text('Disconnect', style: TextStyle(color: _error)),
      );
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size(96, 44),
      ),
      onPressed: _connect,
      child: const Text('Connect'),
    );
  }
}