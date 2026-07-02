import 'dart:async';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum _VoiceStatus { idle, listening, processing, success, captured, fallback, error }

class VoiceCommandAI extends StatefulWidget {
  final bool singleShot;

  const VoiceCommandAI({
    super.key,
    this.singleShot = false,
  });

  @override
  State<VoiceCommandAI> createState() => _VoiceCommandAIState();
}

class _VoiceCommandAIState extends State<VoiceCommandAI> {
  PorcupineManager? _porcupine;
  late stt.SpeechToText _speech;

  bool _isListening = false;
  bool _wakeDetected = false;
  Timer? _timeoutTimer;

  String _buffer = '';
  bool _initialized = false;

  String _recognizedText = '';
  _VoiceStatus _voiceStatus = _VoiceStatus.idle;
  String _statusDetail = '';

  Duration get _statusDisplayDelay =>
      kDebugMode ? const Duration(seconds: 5) : const Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _initPorcupine();
    }
  }

  Future<void> _initPorcupine() async {
    // Porcupine wake word detection is not supported on web
    if (kIsWeb) {
      debugPrint('Porcupine wake word detection disabled on web - use mic button instead');
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      final mgr = await PorcupineManager.fromBuiltInKeywords(
        'Qxjb+VJuMnPDRseioWb9czxnyKe7EWFMdNNMbIWrJiARG2q9Tvo5XA==',
        [BuiltInKeyword.PORCUPINE],
        _onWakeDetected,
      );

      if (!mounted) return;
      _porcupine = mgr;

      await _porcupine?.start();
    } on PorcupineException catch (e) {
      debugPrint('Porcupine init failed: ${e.message}');

      messenger?.showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)?.voicecommand_wakeWordError}: ${e.message}')),
      );
    } catch (e, st) {
      debugPrint('Unexpected init error: $e\n$st');
    }
  }

  void _onWakeDetected(int _) {
    if (!mounted) return;
    setState(() => _wakeDetected = true);
    _startListening();
  }

  void _setStatus({
    required _VoiceStatus status,
    String? recognizedText,
    String? detail,
  }) {
    if (!mounted) return;
    setState(() {
      _voiceStatus = status;
      if (recognizedText != null) {
        _recognizedText = recognizedText;
      }
      if (detail != null) {
        _statusDetail = detail;
      }
    });
  }

  String _phaseLabel() {
    switch (_voiceStatus) {
      case _VoiceStatus.idle:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_phaseLabelReady ?? 'Ready'}';
      case _VoiceStatus.listening:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_listeningState ?? 'Listening'}';
      case _VoiceStatus.processing:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_processingState ?? 'Processing'}';
      case _VoiceStatus.success:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_phaseLabelRecognized ?? 'Command recognized'}';
      case _VoiceStatus.captured:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_phaseLabelCapture ?? 'Captured'}';
      case _VoiceStatus.fallback:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_phaseLabelNotRecognized ?? 'Command not recognized'}';
      case _VoiceStatus.error:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_phaseLabelError ?? 'Error'}';
    }
  }

  Color _statusColor() {
    switch (_voiceStatus) {
      case _VoiceStatus.idle:
        return Colors.grey.shade700;
      case _VoiceStatus.listening:
      case _VoiceStatus.processing:
        return Colors.blue.shade700;
      case _VoiceStatus.success:
      case _VoiceStatus.captured:
        return Colors.green.shade700;
      case _VoiceStatus.fallback:
        return Colors.orange.shade800;
      case _VoiceStatus.error:
        return Colors.red.shade700;
    }
  }

  Future<void> _startListening() async {
    if (!mounted || _isListening) return;

    // Initialize speech recognition - this will request permission if needed
    bool available = await _speech.initialize(
      onError: (error) => debugPrint('Speech error: $error'),
      onStatus: (status) => debugPrint('Speech status: $status'),
    );

    if (!mounted || !available) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context)?.voicecommand_voiceCommandsUnavailable ?? 'Speech recognition not available');
      _reset();
      return;
    }

    // Check if we have permission - initialize() should have requested it
    final hasPermission = await _speech.hasPermission;
    if (!mounted || !hasPermission) {
      if (!mounted) return;
      _showError(AppLocalizations.of(context)?.voicecommand_micPermissionsDenied ?? 'Microphone permission denied');
      _reset();
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _voiceStatus = _VoiceStatus.listening;
      _recognizedText = '';
      _statusDetail = '';
    });

    _speech.listen(
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 2),
      onResult: (r) {
        if (r.recognizedWords.isNotEmpty) {
          _buffer = r.recognizedWords;
          if (mounted) {
            setState(() {
              _recognizedText = r.recognizedWords;
              _voiceStatus = _VoiceStatus.listening;
            });
          }
        }
        if (r.finalResult) {
          _timeoutTimer?.cancel();
          _process(_buffer.isNotEmpty ? _buffer : r.recognizedWords);
        }
      },
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: true,
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        onDevice: false,
        autoPunctuation: true,
        enableHapticFeedback: false,
      ),
    );

    _timeoutTimer = Timer(const Duration(seconds: 12), _onTimeout);
  }

  Future<void> _process(String words) async {
    if (!mounted) return;

    final cmd = words.toLowerCase().trim();
    debugPrint('Heard: $cmd');

    _timeoutTimer?.cancel();

    if (!mounted) return;
    setState(() {
      _recognizedText = words;
      _voiceStatus = _VoiceStatus.processing;
      _statusDetail = '';
      _isListening = false;
    });

    if (widget.singleShot) {
      _speech.stop();
      _setStatus(
        status: _VoiceStatus.captured,
        recognizedText: words,
        detail: '${AppLocalizations.of(context)?.voicecommand_speechCaptured ?? 'Speech captured'}: "$words"',
      );
      await Future.delayed(_statusDisplayDelay);
      if (!mounted) return;
      Navigator.of(context).pop<String>(words);
      return;
    }

    String? successDetail;
    String? destination;
    if (cmd.contains('take me home')) {
      successDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" — ${AppLocalizations.of(context)?.voicecommand_successOpenHome ?? 'opening home'}';
      destination = '/dashboard';
    } else if (cmd.contains('take me to calendar')) {
      successDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" — ${AppLocalizations.of(context)?.voicecommand_successOpenCalendar ?? 'opening calendar'}';
      destination = '/calendar';
    } else if (cmd.contains('take me to my tracker')) {
      successDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" — ${AppLocalizations.of(context)?.voicecommand_successOpenTracker ?? 'opening symptom tracker'}';
      destination = '/symptoms';
    }

    if (successDetail != null && destination != null) {
      _setStatus(
        status: _VoiceStatus.success,
        recognizedText: words,
        detail: successDetail,
      );
      await Future.delayed(_statusDisplayDelay);
      if (!mounted) return;

      context.go(destination);
      _reset();
      return;
    }

    _setStatus(
      status: _VoiceStatus.fallback,
      recognizedText: words,
      detail: '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" — ${AppLocalizations.of(context)?.voicecommand_successOpenTracker ?? 'command not recognized'}',
    );
    _showError(AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized — please try again.', updateStatus: false);
    await Future.delayed(_statusDisplayDelay);
    _reset();
  }

  Future<void> _finishError(String msg) async {
    _showError(msg);
    await Future.delayed(_statusDisplayDelay);
    _reset();
  }

  void _onTimeout() {
    if (!mounted || !_isListening) return;

    final txt = _buffer.trim().isNotEmpty
        ? _buffer
        : _speech.lastRecognizedWords; // fallback just in case

    if (txt.trim().isNotEmpty) {
      _process(txt);
    } else {
      _finishError(AppLocalizations.of(context)?.voicecommand_voiceTimedOut ?? 'Listening timed out.');
    }
  }

  void _showError(String msg, {bool updateStatus = true}) {
    if (!mounted) return;
    if (updateStatus) {
      _setStatus(status: _VoiceStatus.error, detail: msg);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _reset() {
    _timeoutTimer?.cancel();
    _speech.stop();
    _buffer = '';
    if (mounted) {
      setState(() {
        _isListening = false;
        _wakeDetected = false;
        _recognizedText = '';
        _voiceStatus = _VoiceStatus.idle;
        _statusDetail = '';
      });
    }
  }

  void _onMicPressed() {
    if (_isListening) {
      // Stop listening and process what we have
      _timeoutTimer?.cancel();
      _speech.stop();

      final text = _buffer.trim().isNotEmpty
          ? _buffer
          : _speech.lastRecognizedWords;

      if (text.trim().isNotEmpty) {
        _process(text);
      } else {
        _showError(AppLocalizations.of(context)?.voicecommand_noSpeechDetected ?? 'No speech detected.');
        _reset();
      }
    } else {
      setState(() => _wakeDetected = true);
      _startListening();
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _porcupine?.stop();
    _porcupine?.delete();
    _speech.stop();
    super.dispose();
  }

  Widget _buildStatusArea() {
    return Card(
      key: const Key('voice_status_area'),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 96, minWidth: 280),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _phaseLabel(),
              key: const Key('voice_status_phase'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _statusColor(),
              ),
            ),
            if (_recognizedText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.of(context)?.voicecommand_statusAreaHeard ?? 'Heard'}: "$_recognizedText"',
                key: const Key('voice_status_heard'),
                style: const TextStyle(fontSize: 15),
              ),
            ],
            if (_statusDetail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _statusDetail,
                key: const Key('voice_status_detail'),
                style: TextStyle(fontSize: 14, color: _statusColor()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.voicecommand_voiceCommandTitle ?? 'Voice Commands'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            _wakeDetected ? Icons.mic : Icons.mic_none,
            size: 64,
            color: _wakeDetected ? Colors.red : Colors.grey,
          ),
          const SizedBox(height: 12),
          Text(
            !_wakeDetected
                ? (kIsWeb ? AppLocalizations.of(context)?.voicecommand_tapMicToStart ?? 'Tap mic to start' : AppLocalizations.of(context)?.voicecommand_wakeWordToStart ?? 'Say wake word or tap mic')
                : _isListening
                    ? '${AppLocalizations.of(context)?.voicecommand_listeningState ?? 'Listening'}...'
                    : '${AppLocalizations.of(context)?.voicecommand_processingState ?? 'Processing'}...',
            style: const TextStyle(fontSize: 18),
          ),
          _buildStatusArea(),
        ]),
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton(
          onPressed: _onMicPressed,
          child: Icon(_isListening ? Icons.mic_off : Icons.mic),
        ),
      ),
    );
  }
}
