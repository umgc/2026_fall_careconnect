import 'package:flutter/material.dart';

import 'package:care_connect_app/features/usps/domain/mail_envelope_readout_text.dart';
import 'package:care_connect_app/features/usps/presentation/mail_envelope_tts.dart';

/// ADA control that reads envelope-level sender/summary aloud (Task 3.14.10).
class MailEnvelopeReadAloudButton extends StatefulWidget {
  const MailEnvelopeReadAloudButton({
    super.key,
    this.sender,
    this.summary,
    this.includeMissingImageNote = false,
    this.tts,
    this.iconSize = 22,
    this.color,
    this.tooltip = 'Read mail details aloud',
  });

  final String? sender;
  final String? summary;
  final bool includeMissingImageNote;
  final MailEnvelopeTts? tts;
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
  bool _speaking = false;

  MailEnvelopeTts get _tts => widget.tts ?? MailEnvelopeTtsService.instance;

  String get _utterance => buildMailEnvelopeReadoutText(
        sender: widget.sender,
        summary: widget.summary,
        includeMissingImageNote: widget.includeMissingImageNote,
      );

  Future<void> _toggle() async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }

    setState(() => _speaking = true);
    try {
      await _tts.speak(_utterance);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  void dispose() {
    // Stop only if this control started speech; shared service may be in use
    // by another tile — stopping on dispose is the safer accessibility default.
    if (_speaking) {
      _tts.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = _speaking ? 'Stop reading mail details' : widget.tooltip;
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        key: MailEnvelopeReadAloudButton.buttonKey,
        tooltip: label,
        iconSize: widget.iconSize,
        icon: Icon(
          _speaking ? Icons.volume_off : Icons.volume_up,
          color: widget.color,
        ),
        onPressed: _toggle,
      ),
    );
  }
}
