import 'package:flutter/material.dart';
import '../services/medicare_connect_service.dart';

/// Drop-in "Connect Medicare" tile.
///
/// Mirrors Team D's EpicConnectTile: shows connection status, starts the
/// connect flow, and offers Disconnect. When the browser comes back from
/// Medicare, pass the backend's ?medicare= value as [result] and the tile
/// shows a plain-language message for it.
class MedicareConnectTile extends StatefulWidget {
  const MedicareConnectTile({super.key, this.result, this.service});

  /// Outcome reported by the backend on return, if any.
  final MedicareConnectResult? result;

  /// Injected in tests; defaults to [MedicareConnectService.instance].
  final MedicareConnectService? service;

  @override
  State<MedicareConnectTile> createState() => _MedicareConnectTileState();
}

enum _Status { loading, connected, notConnected, unknown }

class _MedicareConnectTileState extends State<MedicareConnectTile>
    with WidgetsBindingObserver {
  // Darker teal than the old 0xFF00A7C8 so white button text and teal text
  // both meet WCAG AA contrast.
  static const _teal = Color(0xFF00788F);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  static const _border = Color(0xFFE5E7EB);
  static const _success = Color(0xFF047857);
  static const _error = Color(0xFFB91C1C);

  _Status _status = _Status.loading;
  DateTime? _connectedAt;
  bool _busy = false;
  _Message? _message;

  MedicareConnectService get _service =>
      widget.service ?? MedicareConnectService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _message = _Message.forResult(widget.result);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MedicareConnectTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same page, new ?medicare= value (in-app navigation, no reload).
    if (widget.result != null && widget.result != oldWidget.result) {
      _message = _Message.forResult(widget.result);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mobile: re-check after returning from the external browser.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final s = await _service.status();
    if (!mounted) return;
    setState(() {
      if (s == null) {
        _status = _Status.unknown;
      } else {
        _status = s.connected ? _Status.connected : _Status.notConnected;
        _connectedAt = s.connectedAt;
      }
    });
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _service.connect();
      // Web navigates away here; on mobile the resume handler re-checks.
    } on MedicareConnectException catch (e) {
      if (mounted) setState(() => _message = _Message.forError(e.error));
    } catch (_) {
      if (mounted) {
        setState(() => _message = _Message.forError(MedicareConnectError.server));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Medicare?'),
        content: const Text(
          'CareConnect will stop getting new information from your Medicare '
          'account. You can connect again anytime.',
          style: TextStyle(fontSize: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep connected'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _error),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await _service.disconnect();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _status = _Status.notConnected;
        _connectedAt = null;
        _message = const _Message(_Tone.info,
            'Medicare is disconnected. You can connect again anytime.');
      } else {
        _message = const _Message(_Tone.error,
            'We couldn\'t disconnect Medicare. Please try again.');
      }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_message != null) ...[
            _messageBanner(_message!),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const ExcludeSemantics(
                child: Icon(Icons.shield_outlined, color: _teal, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Medicare',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _text)),
                    const SizedBox(height: 2),
                    _statusLine(),
                  ],
                ),
              ),
              if (!_offersConnect) ...[
                const SizedBox(width: 8),
                _action(),
              ],
            ],
          ),
          // The connect control gets its own full-width row so its SRS name,
          // "Connect Medicare Account", fits on a phone.
          if (_offersConnect) ...[
            const SizedBox(height: 12),
            _action(),
          ],
        ],
      ),
    );
  }

  Widget _statusLine() {
    switch (_status) {
      case _Status.loading:
        return const Text('Checking…',
            style: TextStyle(color: _muted, fontSize: 14));
      case _Status.unknown:
        return const Text('Couldn\'t check the connection',
            style: TextStyle(color: _muted, fontSize: 14));
      case _Status.connected:
      case _Status.notConnected:
        final connected = _status == _Status.connected;
        final color = connected ? _success : _muted;
        final since = connected && _connectedAt != null
            ? ' since ${_shortDate(_connectedAt!)}'
            : '';
        // Icon shape + words carry the meaning, not color alone.
        return Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                  connected ? Icons.check_circle : Icons.remove_circle_outline,
                  size: 16,
                  color: color),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(connected ? 'Connected$since' : 'Not connected',
                  style: TextStyle(color: color, fontSize: 14)),
            ),
          ],
        );
    }
  }

  bool get _offersConnect => !_busy && _status == _Status.notConnected;

  Widget _action() {
    if (_busy || _status == _Status.loading) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Semantics(
          label: 'Please wait',
          child: const CircularProgressIndicator(strokeWidth: 2.5, color: _teal),
        ),
      );
    }
    if (_status == _Status.unknown) {
      return TextButton(
        onPressed: () {
          setState(() => _status = _Status.loading);
          _refresh();
        },
        style: TextButton.styleFrom(
            foregroundColor: _teal, minimumSize: const Size(48, 48)),
        child: const Text('Try again'),
      );
    }
    if (_status == _Status.connected) {
      return TextButton(
        onPressed: _disconnect,
        style: TextButton.styleFrom(
            foregroundColor: _error, minimumSize: const Size(48, 48)),
        child: const Text('Disconnect'),
      );
    }
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: const Size.fromHeight(48),
      ),
      onPressed: _connect,
      child: const Text('Connect Medicare Account'),
    );
  }

  Widget _messageBanner(_Message m) {
    final (Color fg, Color bg, IconData icon) = switch (m.tone) {
      _Tone.success => (_success, const Color(0xFFECFDF5), Icons.check_circle),
      _Tone.info => (const Color(0xFF1E40AF), const Color(0xFFEFF6FF),
          Icons.info_outline),
      _Tone.error => (_error, const Color(0xFFFEF2F2), Icons.error_outline),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: fg.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, color: fg, size: 20),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(m.text,
                  style: const TextStyle(
                      fontSize: 15, height: 1.4, color: _text)),
            ),
            IconButton(
              tooltip: 'Dismiss message',
              icon: const Icon(Icons.close, size: 20, color: _muted),
              onPressed: () => setState(() => _message = null),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

enum _Tone { success, info, error }

class _Message {
  final _Tone tone;
  final String text;
  const _Message(this.tone, this.text);

  /// Plain-language copy for each ?medicare= result.
  static _Message? forResult(MedicareConnectResult? r) {
    switch (r) {
      case null:
        return null;
      case MedicareConnectResult.connected:
        // SRS FR-MCR-04 / AC-MCR-04-1.
        return const _Message(_Tone.success,
            'Medicare account connected. Your Medicare claims will show in Health Data.');
      case MedicareConnectResult.cancelled:
        return const _Message(_Tone.info,
            'You didn\'t finish connecting Medicare, so nothing changed. '
            'You can try again anytime.');
      case MedicareConnectResult.failed:
        return const _Message(_Tone.error,
            'We couldn\'t connect to Medicare. Please try again in a few minutes.');
      case MedicareConnectResult.linkExpired:
        return const _Message(_Tone.info,
            'The connection timed out before it finished. '
            'Press Connect Medicare Account to try again.');
      case MedicareConnectResult.alreadyLinked:
        // Backend: ALREADY_LINKED_ELSEWHERE, i.e. a different patient.
        return const _Message(_Tone.error,
            'This Medicare account is already connected to a different '
            'CareConnect account, so we didn\'t connect it here. '
            'If you didn\'t expect this, please contact support.');
    }
  }

  static _Message forError(MedicareConnectError e) {
    switch (e) {
      case MedicareConnectError.offline:
        // SRS ERR-MCR-04 (FR-MCR-26).
        return const _Message(_Tone.error,
            'You need an internet connection to connect your Medicare account.');
      case MedicareConnectError.signedOut:
        return const _Message(_Tone.error,
            'Your sign-in has expired. Please sign in again, then connect Medicare.');
      case MedicareConnectError.notPatient:
        return const _Message(_Tone.info,
            'Only the patient can connect their own Medicare account. '
            'Please sign in with the patient\'s account to connect it.');
      case MedicareConnectError.network:
        return const _Message(_Tone.error,
            'We couldn\'t reach CareConnect. Check your internet connection and try again.');
      case MedicareConnectError.launch:
        return const _Message(_Tone.error,
            'We couldn\'t open the Medicare sign-in page. Please try again.');
      case MedicareConnectError.server:
        return const _Message(_Tone.error,
            'We couldn\'t start the Medicare connection. Please try again in a few minutes.');
    }
  }
}
