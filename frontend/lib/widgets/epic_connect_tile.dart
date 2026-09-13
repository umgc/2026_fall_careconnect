import 'package:flutter/material.dart';
import '../services/epic_service.dart';

/// Drop-in "Connect to Epic (MyChart)" tile for the integrations / settings area (Epic Phase 0).
///
/// Shows connection status, launches the SMART-on-FHIR connect flow, and offers Disconnect.
/// After the browser round-trip returns via the `careconnect://epic/linked` deep link, the tile
/// re-polls status. Wire it into the integrations screen next to Wearables, e.g.:
/// `const EpicConnectTile()`.
class EpicConnectTile extends StatefulWidget {
  const EpicConnectTile({super.key});

  @override
  State<EpicConnectTile> createState() => _EpicConnectTileState();
}

class _EpicConnectTileState extends State<EpicConnectTile> with WidgetsBindingObserver {
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
    // Re-check after returning from the external browser (Epic consent).
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    try {
      final status = await EpicService.status();
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
      await EpicService.connect();
    } catch (e) {
      _snack('Could not start Epic connection: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    try {
      final ok = await EpicService.disconnect();
      if (ok) {
        _snack('Disconnected from Epic.');
        await _refresh();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_hospital_outlined),
        title: const Text('Epic (MyChart)'),
        subtitle: Text(
          _loading
              ? 'Checking…'
              : _connected
                  ? 'Connected — your records help answer Ask AI'
                  : 'Connect to import your clinical records',
        ),
        trailing: _busy
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : _connected
                ? TextButton(onPressed: _disconnect, child: const Text('Disconnect'))
                : FilledButton(onPressed: _connect, child: const Text('Connect')),
      ),
    );
  }
}
