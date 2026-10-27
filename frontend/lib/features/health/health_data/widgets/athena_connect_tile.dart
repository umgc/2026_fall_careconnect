import 'package:flutter/material.dart';
import '../services/athena_connect_service.dart';

/// Drop-in "Connect athenahealth" tile.
///
/// Mirrors MedicareConnectTile: shows connection status, connects, refreshes
/// and disconnects. athenahealth has no sign-in page (2-legged OAuth), so the
/// patient's agreement to [consentText] here is the only authorization the
/// backend has; Connect stays disabled until they agree.
///
/// Hidden when the signed-in user is not a patient (403): the API accepts
/// patients only. When the server has athenahealth turned off (404) it reads
/// as not connected and Connect says it isn't available, as Epic's tile does.
///
/// [compact] is the Settings version, laid out like EpicConnectTile: one
/// card row with Connect or Disconnect. [buttonOnly] is just the Connect
/// button, for the Health Data screen's "not connected" banner. In both,
/// Connect asks for consent in a dialog and results show in a snackbar, as
/// Epic's do.
class AthenaConnectTile extends StatefulWidget {
  const AthenaConnectTile(
      {super.key,
      this.service,
      this.onChanged,
      this.compact = false,
      this.buttonOnly = false})
      : assert(!(compact && buttonOnly), 'Pick one layout');

  /// One card row for Settings, matching EpicConnectTile.
  final bool compact;

  /// Only the Connect button (consent dialog, then connect in place), for a
  /// banner that already says athenahealth isn't connected.
  final bool buttonOnly;

  /// Consent comes from a dialog and results from a snackbar.
  bool get _inline => compact || buttonOnly;

  /// Injected in tests; defaults to [AthenaConnectService.instance].
  final AthenaConnectService? service;

  /// Called after a connect, refresh or disconnect changes the records.
  final VoidCallback? onChanged;

  /// Based on the Medicare consent text (medicarehelp_consentBody), for a
  /// source that is read by CareConnect rather than signed in to.
  static const consentText =
      'When you connect, CareConnect looks for your chart at your '
      'athenahealth provider using the name, date of birth and gender in your '
      'profile, then reads your health records, such as conditions, '
      'medications, allergies, test results, immunizations and visits. '
      'CareConnect can only read this information. It can\'t change anything '
      'in your athenahealth chart. If you don\'t agree, nothing is connected '
      'and nothing is saved.';

  /// Based on the Medicare disconnect text (medicarehelp_disconnectBody).
  static const disconnectText =
      'CareConnect will delete your athenahealth connection and the '
      'athenahealth records it brought in, and stop getting new ones. Your '
      'CareConnect account and information from other sources stay. You can '
      'connect again later.';

  @override
  State<AthenaConnectTile> createState() => _AthenaConnectTileState();
}

enum _Status { loading, connected, notConnected, hidden }

class _AthenaConnectTileState extends State<AthenaConnectTile> {
  // Same palette as MedicareConnectTile (WCAG AA).
  static const _teal = Color(0xFF00788F);
  static const _text = Color(0xFF0F172A);
  static const _muted = Color(0xFF4B5563);
  static const _border = Color(0xFFE5E7EB);
  static const _success = Color(0xFF047857);
  static const _error = Color(0xFFB91C1C);

  _Status _status = _Status.loading;
  bool _busy = false;
  bool _agreed = false;
  _Message? _message;

  AthenaConnectService get _service =>
      widget.service ?? AthenaConnectService.instance;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await _service.status();
    if (!mounted) return;
    setState(() {
      if (s == null) {
        // A status that can't be read (offline, or a server with athena
        // turned off answering 500 for the missing route; R381-D01) reads as
        // not connected, as the Settings row, the banner and Epic's tile do.
        // Connect then says what went wrong; a "Try again" here would loop.
        _status = _Status.notConnected;
      } else if (!s.shown) {
        _status = _Status.hidden;
      } else {
        _status = s.connected ? _Status.connected : _Status.notConnected;
        // A failed link is remembered by the backend as NOT_LINKED after
        // consent; say what the patient can do about it.
        if (!s.connected &&
            s.reason == AthenaNotConnectedReason.notLinked &&
            !widget._inline) {
          _message ??= _Message.forReason(s.reason!);
        }
      }
    });
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final s = await _service.connect();
      if (!mounted) return;
      setState(() => _status =
          s.connected ? _Status.connected : _Status.notConnected);
      _show(s.connected
          ? widget.compact
              ? const _Message(_Tone.success, 'athenahealth connected.')
              : _Message.forSync(s.sync, connected: true)
          : _Message.forReason(s.reason!));
      widget.onChanged?.call();
    } on AthenaConnectException catch (e) {
      if (mounted) _show(_Message.forError(e.error));
    } catch (_) {
      if (mounted) _show(_Message.forError(AthenaConnectError.server));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await _service.sync();
      if (!mounted) return;
      _show(_Message.forSync(r, connected: false));
      widget.onChanged?.call();
    } on AthenaConnectException catch (e) {
      if (!mounted) return;
      if (e.error == AthenaConnectError.notConnected) {
        setState(() => _status = _Status.notConnected);
      }
      _show(_Message.forError(e.error));
    } catch (_) {
      if (mounted) _show(_Message.forError(AthenaConnectError.server));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect athenahealth?'),
        content: const Text(
          AthenaConnectTile.disconnectText,
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
        _agreed = false;
      }
    });
    _show(ok
        ? widget.compact
            ? const _Message(_Tone.info, 'Disconnected from athenahealth.')
            : const _Message(_Tone.info,
                'athenahealth is disconnected and its records were removed. '
                'You can connect again anytime.')
        : const _Message(_Tone.error,
            'We couldn\'t disconnect athenahealth. Please try again.'));
    if (ok) widget.onChanged?.call();
  }

  /// The full tile shows [m] in its banner; the compact one in a snackbar,
  /// like EpicConnectTile.
  void _show(_Message m) {
    if (!mounted) return;
    if (widget._inline) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(m.text)));
    } else {
      setState(() => _message = m);
    }
  }

  /// Compact Connect: the consent the full tile shows inline, as a dialog.
  /// Connects only when the patient agrees.
  Future<void> _connectWithConsent() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConsentDialog(),
    );
    if (agreed == true && mounted) await _connect();
  }

  /// The banner's action: Connect until it's connected, "Please wait" while
  /// connecting. Shown while the status loads too, so the banner's button
  /// doesn't pop in late; a status that can't be checked still offers
  /// Connect, which reports any problem itself.
  Widget _connectButton() {
    if (_status == _Status.connected) return const SizedBox.shrink();
    if (_busy) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: Semantics(
                container: true,
                label: 'Please wait',
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: _teal)),
          ),
        ),
      );
    }
    return TextButton(
      onPressed: _connectWithConsent,
      // Same style as the screen's other banner actions.
      style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF006B80),
          minimumSize: const Size(48, 48)),
      child: const Text('Connect athenahealth'),
    );
  }

  /// Laid out like EpicConnectTile: a card row with a status line and one
  /// action. Never says athenahealth is connected, only when it isn't.
  /// Same card, icon, wording and buttons as EpicConnectTile. As Epic's
  /// does, a status that can't be checked reads as not connected. The
  /// connected line differs only where Epic's would be untrue: athena records
  /// aren't in Ask AI.
  Widget _compact() {
    final connected = _status == _Status.connected;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.local_hospital_outlined),
        title: const Text('athenahealth'),
        subtitle: Text(
          _status == _Status.loading
              ? 'Checking…'
              : connected
                  ? 'Connected — your records show in Health Data'
                  : 'Connect to import your clinical records',
        ),
        trailing: _busy
            ? SizedBox(
                width: 20,
                height: 20,
                child: Semantics(
                    container: true,
                    label: 'Please wait',
                    child: const CircularProgressIndicator(strokeWidth: 2)))
            : connected
                ? TextButton(
                    onPressed: _disconnect, child: const Text('Disconnect'))
                : FilledButton(
                    onPressed: _connectWithConsent,
                    child: const Text('Connect')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_status == _Status.hidden) return const SizedBox.shrink();
    if (widget.compact) return _compact();
    if (widget.buttonOnly) return _connectButton();
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
                child:
                    Icon(Icons.local_hospital_outlined, color: _teal, size: 32),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('athenahealth',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: _text)),
                    const SizedBox(height: 2),
                    _statusLine(),
                  ],
                ),
              ),
              if (_status == _Status.loading ||
                  (_busy && _status != _Status.notConnected)) ...[
                const SizedBox(width: 8),
                _spinner(),
              ],
            ],
          ),
          if (_status == _Status.notConnected) ..._consent(),
          if (_status == _Status.connected && !_busy) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _sync,
                  icon: const Icon(Icons.refresh),
                  style: TextButton.styleFrom(
                      foregroundColor: _teal, minimumSize: const Size(48, 48)),
                  label: const Text('Refresh records'),
                ),
                TextButton(
                  onPressed: _disconnect,
                  style: TextButton.styleFrom(
                      foregroundColor: _error, minimumSize: const Size(48, 48)),
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _consent() => [
        const SizedBox(height: 12),
        const Text('What you\'re agreeing to',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: _text)),
        const SizedBox(height: 4),
        const Text(AthenaConnectTile.consentText,
            style: TextStyle(fontSize: 15, height: 1.45, color: _text)),
        const SizedBox(height: 8),
        // Its own Material so the tile's ink isn't hidden by the white box.
        Material(
          type: MaterialType.transparency,
          child: CheckboxListTile(
            value: _agreed,
            onChanged:
                _busy ? null : (v) => setState(() => _agreed = v == true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: _teal,
            title: const Text(
                'I agree to let CareConnect read my athenahealth records.',
                style: TextStyle(fontSize: 15, color: _text)),
          ),
        ),
        const SizedBox(height: 8),
        _busy
            ? Center(child: _spinner())
            : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white,
                  // Readable before the patient agrees (4.5:1), not just
                  // the theme's faint disabled grey.
                  disabledBackgroundColor: _border,
                  disabledForegroundColor: _muted,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _agreed ? _connect : null,
                child: const Text('Connect athenahealth'),
              ),
      ];

  Widget _statusLine() {
    switch (_status) {
      case _Status.loading:
        return const Text('Checking…',
            style: TextStyle(color: _muted, fontSize: 14));
      case _Status.hidden:
        return const SizedBox.shrink();
      case _Status.connected:
        // Never says a source is connected, only when it isn't.
        return const SizedBox.shrink();
      case _Status.notConnected:
        // Icon shape + words carry the meaning, not color alone.
        return const Row(
          children: [
            ExcludeSemantics(
              child: Icon(Icons.remove_circle_outline, size: 16, color: _muted),
            ),
            SizedBox(width: 4),
            Flexible(
              child: Text('Not connected',
                  style: TextStyle(color: _muted, fontSize: 14)),
            ),
          ],
        );
    }
  }

  Widget _spinner() => SizedBox(
        width: 24,
        height: 24,
        // Its own node, so the label isn't merged into nearby text and lost.
        child: Semantics(
          container: true,
          label: 'Please wait',
          child:
              const CircularProgressIndicator(strokeWidth: 2.5, color: _teal),
        ),
      );

  Widget _messageBanner(_Message m) {
    final (Color fg, Color bg, IconData icon) = switch (m.tone) {
      _Tone.success => (_success, const Color(0xFFECFDF5), Icons.check_circle),
      _Tone.info => (
          const Color(0xFF1E40AF),
          const Color(0xFFEFF6FF),
          Icons.info_outline
        ),
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
                  style:
                      const TextStyle(fontSize: 15, height: 1.4, color: _text)),
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

}

/// The consent text with an "I agree" box; Connect stays off until it's
/// ticked, as on the full tile.
class _ConsentDialog extends StatefulWidget {
  const _ConsentDialog();

  @override
  State<_ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<_ConsentDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect athenahealth'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What you\'re agreeing to',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(AthenaConnectTile.consentText,
                style: TextStyle(height: 1.4)),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _agreed,
              onChanged: (v) => setState(() => _agreed = v == true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                  'I agree to let CareConnect read my athenahealth records.'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          // The light theme's primary is 2.85:1 on white (WCAG 1.4.3).
          style: Theme.of(context).brightness == Brightness.dark
              ? null
              : TextButton.styleFrom(
                  foregroundColor: const Color(0xFF006B80)),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

enum _Tone { success, info, error }

class _Message {
  final _Tone tone;
  final String text;
  const _Message(this.tone, this.text);

  /// Summary of a sync, telling "no data" apart from "not shared" and
  /// "couldn't reach athenahealth" (AthenaSyncResult outcomes).
  /// Never says athenahealth is connected or names it as the source.
  static _Message forSync(AthenaSyncResult? r, {required bool connected}) {
    final lead = connected ? 'You\'re all set. ' : '';
    if (r == null) {
      return _Message(
          _Tone.success, '${lead}Your records will show in Health Data.');
    }
    if (!r.completed) {
      return _Message(_Tone.error,
          '${lead}We couldn\'t get your records just now. '
          'Please try Refresh records in a few minutes.');
    }
    final parts = <String>[
      r.storedCount == 0
          ? 'No new records were found.'
          : '${r.storedCount} '
              '${r.storedCount == 1 ? 'record is' : 'records are'} '
              'now in Health Data.',
    ];
    if (r.notShared.isNotEmpty) {
      parts.add('Your provider doesn\'t share '
          '${_typeList(r.notShared)} with CareConnect.');
    }
    if (r.failed.isNotEmpty) {
      parts.add('We couldn\'t get ${_typeList(r.failed)} this time.');
    }
    return _Message(
        r.failed.isEmpty ? _Tone.success : _Tone.info, lead + parts.join(' '));
  }

  static _Message forReason(AthenaNotConnectedReason reason) {
    switch (reason) {
      case AthenaNotConnectedReason.noPatientProfile:
        return const _Message(_Tone.error,
            'We need your patient profile to find your athenahealth chart. '
            'Please finish your profile, then connect again.');
      case AthenaNotConnectedReason.incompleteProfile:
        return const _Message(_Tone.error,
            'Your profile needs your first name, last name and date of birth '
            'to find your athenahealth chart. Please add them, then connect '
            'again.');
      case AthenaNotConnectedReason.notMatched:
        return const _Message(_Tone.info,
            'We couldn\'t find an athenahealth chart that matches your '
            'profile. Check that your name and date of birth match your '
            'provider\'s records, then connect again.');
      case AthenaNotConnectedReason.ambiguousMatch:
        return const _Message(_Tone.error,
            'More than one athenahealth chart matches your profile, so we '
            'didn\'t connect any of them. Please contact support.');
      case AthenaNotConnectedReason.linkConflict:
        return const _Message(_Tone.error,
            'This athenahealth chart is already connected to a different '
            'CareConnect account, so we didn\'t connect it here. If you '
            'didn\'t expect this, please contact support.');
      case AthenaNotConnectedReason.sourceUnavailable:
        return const _Message(_Tone.error,
            'We couldn\'t reach athenahealth. Please try again in a few '
            'minutes.');
      case AthenaNotConnectedReason.notLinked:
        return const _Message(_Tone.info,
            'Your athenahealth chart isn\'t linked yet. Check your profile '
            'details, then connect again.');
      case AthenaNotConnectedReason.notConsented:
      case AthenaNotConnectedReason.unknown:
        return const _Message(_Tone.error,
            'We couldn\'t connect athenahealth. Please try again in a few '
            'minutes.');
    }
  }

  static _Message forError(AthenaConnectError e) {
    switch (e) {
      case AthenaConnectError.offline:
        return const _Message(_Tone.error,
            'You need an internet connection to connect athenahealth.');
      case AthenaConnectError.signedOut:
        return const _Message(_Tone.error,
            'Your sign-in has expired. Please sign in again, then try again.');
      case AthenaConnectError.notPatient:
        return const _Message(_Tone.info,
            'Only the patient can connect their own athenahealth records. '
            'Please sign in with the patient\'s account.');
      case AthenaConnectError.network:
        return const _Message(_Tone.error,
            'We couldn\'t reach CareConnect. Check your internet connection '
            'and try again.');
      case AthenaConnectError.syncInProgress:
        return const _Message(_Tone.info,
            'Your records are already being updated. Please wait a moment, '
            'then check Health Data.');
      case AthenaConnectError.notConnected:
        return const _Message(_Tone.info,
            'athenahealth isn\'t connected anymore. Please connect again.');
      case AthenaConnectError.sourceUnavailable:
        return const _Message(_Tone.error,
            'We couldn\'t reach your provider. Please try again in a few '
            'minutes.');
      case AthenaConnectError.disabled:
        return const _Message(_Tone.error,
            'athenahealth isn\'t available right now. Please try again '
            'later.');
      case AthenaConnectError.server:
        return const _Message(_Tone.error,
            'We couldn\'t complete that. Please try again in a few minutes.');
    }
  }

  static String _typeList(List<AthenaTypeResult> types) {
    final names = types.map((t) => _typeName(t.resourceType)).toSet().toList();
    if (names.length == 1) return names.single;
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// Plain-language names for the types AthenaSyncService syncs.
  static String _typeName(String fhirType) {
    switch (fhirType) {
      case 'AllergyIntolerance':
        return 'allergies';
      case 'Condition':
        return 'conditions';
      case 'MedicationRequest':
        return 'medications';
      case 'Observation':
        return 'test results';
      case 'DiagnosticReport':
        return 'lab reports';
      case 'Immunization':
        return 'immunizations';
      case 'Procedure':
        return 'procedures';
      case 'Encounter':
        return 'visits';
      case 'CarePlan':
        return 'care plans';
      case 'Goal':
        return 'goals';
      case 'CareTeam':
        return 'care team';
      case 'FamilyMemberHistory':
        return 'family history';
      case 'Coverage':
        return 'insurance';
      case 'Device':
        return 'devices';
      default:
        return fhirType;
    }
  }
}
