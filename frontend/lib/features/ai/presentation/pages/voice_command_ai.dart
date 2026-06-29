import 'dart:async';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
    setState(() => _isListening = true);

      _speech.listen(
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 2),
        onResult: (r) {
          if (r.recognizedWords.isNotEmpty) {
            _buffer = r.recognizedWords;
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

  void _process(String words) {
    if (!mounted) return;

    final cmd = words.toLowerCase().trim();
    debugPrint('Heard: $cmd');

    if (widget.singleShot) {
      _reset();
      if (mounted) {
        Navigator.of(context).pop<String>(words);
      }
      return;
    }

    if (cmd.contains('take me home')) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    } else if (cmd.contains('take me to calendar')) {
      if (mounted) {
        Navigator.pushNamed(context, '/telehealth');
      }
    } else if (cmd.contains('take me to my tracker')) {
      if (mounted) {
        Navigator.pushNamed(context, '/symptomTracker');
      }
    } else {
      _showError(AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized — please try again.');
    }
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
      _showError(AppLocalizations.of(context)?.voicecommand_voiceTimedOut ?? 'Listening timed out.');
      _reset();
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
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
