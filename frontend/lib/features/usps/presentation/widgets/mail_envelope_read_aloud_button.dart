import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:care_connect_app/features/usps/domain/mail_envelope_readout_text.dart';
import 'package:care_connect_app/features/usps/presentation/mail_envelope_tts.dart';

/// ADA control that reads envelope-level sender/summary aloud (Task 3.14.10).
///
/// Each instance owns a unique [sessionId]. Buttons listen to the shared
/// [MailEnvelopeTts] session so a preempted control resets to Start.
class MailEnvelopeReadAloudButton extends StatefulWidget {
  const MailEnvelopeReadAloudButton({
    super.key,
    this.sender,
    this.summary,
    this.includeMissingImageNote = false,
    this.tts,
    this.sessionId,
    this.iconSize = 22,
    this.color,
    this.tooltip = 'Start reading mail aloud',
  });

  final String? sender;
  final String? summary;
  final bool includeMissingImageNote;
  final MailEnvelopeTts? tts;
  /// Stable id for this button instance; auto-generated when omitted.
  final String? sessionId;
  final double iconSize;
  final Color? color;
  final String tooltip;

  static const Key buttonKey = Key('mailEnvelopeReadAloudButton');

  @override
  State<MailEnvelopeReadAloudButton> createState() =>
      _MailEnvelopeReadAloudButtonState();
}

class _MailEnvelopeReadAloudButtonState
    extends State<MailEnvelopeReadAloudButton> {
  late final String _sessionId;
  MailEnvelopeTts? _boundTts;

  MailEnvelopeTts get _tts => widget.tts ?? MailEnvelopeTtsService.instance;

  String get _utterance => buildMailEnvelopeReadoutText(
        sender: widget.sender,
        summary: widget.summary,
        includeMissingImageNote: widget.includeMissingImageNote,
      );

  bool get _isThisSessionSpeaking {
    final state = _tts.sessionListenable.value;
    return state.isSpeaking && state.activeSessionId == _sessionId;
  }

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId ??
        'mail-tts-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';
    _bindTts(_tts);
  }

  @override
  void didUpdateWidget(MailEnvelopeReadAloudButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tts != widget.tts) {
      _unbindTts();
      _bindTts(_tts);
    }
  }

  void _bindTts(MailEnvelopeTts tts) {
    _boundTts = tts;
    tts.sessionListenable.addListener(_onSessionChanged);
  }

  void _unbindTts() {
    _boundTts?.sessionListenable.removeListener(_onSessionChanged);
    _boundTts = null;
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    if (_isThisSessionSpeaking) {
      await _tts.stop();
      return;
    }
    await _tts.speak(_sessionId, _utterance);
  }

  @override
  void dispose() {
    final wasSpeaking = _isThisSessionSpeaking;
    _unbindTts();
    if (wasSpeaking) {
      // Do not await — avoid notifying listeners after this State is disposed.
      unawaited(_tts.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final speaking = _isThisSessionSpeaking;
    final semanticsLabel =
        speaking ? 'Stop reading' : 'Start reading mail aloud';
    final label = speaking ? 'Stop' : 'Start';
    final icon = speaking ? Icons.stop_circle_outlined : Icons.volume_up;

    return Semantics(
      key: MailEnvelopeReadAloudButton.buttonKey,
      button: true,
      label: semanticsLabel,
      child: ExcludeSemantics(
        child: TextButton.icon(
          onPressed: _toggle,
          icon: Icon(icon, size: widget.iconSize, color: widget.color),
          label: Text(label),
          style: TextButton.styleFrom(
            minimumSize: const Size(88, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            foregroundColor: widget.color,
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ),
    );
  }
}
