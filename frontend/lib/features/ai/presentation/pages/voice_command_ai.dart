import 'dart:async';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/voice_intent_registry.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:go_router/go_router.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

enum _VoiceStatus { idle, listening, processing, success, captured, fallback, error, confirming, clarifying }

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

  String? _pendingDestination;
  String? _pendingDetail;
  String? _pendingIntent;
  List<_CommandMatch> _ambiguousMatches = [];

  static const _commandTable = [
    // Core navigation
    _CommandMatch(phrase: 'take me home', intent: 'navigate', entity: 'home'),
    _CommandMatch(phrase: 'take me to calendar', intent: 'navigate', entity: 'calendar'),
    _CommandMatch(phrase: 'take me to my tracker', intent: 'navigate', entity: 'symptoms'),
    _CommandMatch(phrase: 'open messages', intent: 'navigate', entity: 'messages'),
    _CommandMatch(phrase: 'take me to messages', intent: 'navigate', entity: 'messages'),
    _CommandMatch(phrase: 'open profile', intent: 'navigate', entity: 'profile'),
    _CommandMatch(phrase: 'open settings', intent: 'navigate', entity: 'settings'),
    _CommandMatch(phrase: 'open menu', intent: 'navigate', entity: 'menu'),
    // Health
    _CommandMatch(phrase: 'open medication tracker', intent: 'navigate', entity: 'medication'),
    _CommandMatch(phrase: 'take me to medications', intent: 'navigate', entity: 'medications'),
    _CommandMatch(phrase: 'open virtual check in', intent: 'navigate', entity: 'virtual checkin'),
    _CommandMatch(phrase: 'start check in', intent: 'navigate', entity: 'virtual checkin'),
    // Integrations
    _CommandMatch(phrase: 'open wearables', intent: 'navigate', entity: 'wearables'),
    _CommandMatch(phrase: 'open smart devices', intent: 'navigate', entity: 'smart devices'),
    _CommandMatch(phrase: 'open home monitoring', intent: 'navigate', entity: 'home monitoring'),
    // Social
    _CommandMatch(phrase: 'open social feed', intent: 'navigate', entity: 'social feed'),
    // Caregiver
    _CommandMatch(phrase: 'open patient list', intent: 'navigate', entity: 'patient list'),
    _CommandMatch(phrase: 'show my patients', intent: 'navigate', entity: 'patients'),
    _CommandMatch(phrase: 'open evv', intent: 'navigate', entity: 'evv'),
    _CommandMatch(phrase: 'open notetaker', intent: 'navigate', entity: 'notetaker'),
    _CommandMatch(phrase: 'open invoice assistant', intent: 'navigate', entity: 'invoice assistant'),
    // Files & documents
    _CommandMatch(phrase: 'open file management', intent: 'navigate', entity: 'file management'),
    _CommandMatch(phrase: 'open my files', intent: 'navigate', entity: 'files'),
    _CommandMatch(phrase: 'open informed delivery', intent: 'navigate', entity: 'informed delivery'),
    _CommandMatch(phrase: 'check my mail', intent: 'navigate', entity: 'mail'),
    // Other features
    _CommandMatch(phrase: 'open gamification', intent: 'navigate', entity: 'gamification'),
    _CommandMatch(phrase: 'show achievements', intent: 'navigate', entity: 'achievements'),
    _CommandMatch(phrase: 'open search', intent: 'navigate', entity: 'search'),
    _CommandMatch(phrase: 'open subscription', intent: 'navigate', entity: 'subscription'),
    _CommandMatch(phrase: 'open ai configuration', intent: 'navigate', entity: 'ai configuration'),
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    registerDefaultVoiceIntents();
  }

  Duration get _statusDisplayDelay =>
      kDebugMode ? const Duration(seconds: 5) : const Duration(milliseconds: 300);

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
      case _VoiceStatus.confirming:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_confirmCommand ?? 'Confirm command'}';
      case _VoiceStatus.clarifying:
        return '${AppLocalizations.of(context)?.voicecommand_phaseLabelStatus ?? 'Status'}: ${AppLocalizations.of(context)?.voicecommand_clarifyCommand ?? 'Clarify command'}';
    }
  }

  String _commandLabelToDisplayText(String commandLabel){
    switch (commandLabel){
      case 'Home':
        return AppLocalizations.of(context)?.voicecommand_commandLabelHome ?? 'Home';
      case 'Calendar':
        return AppLocalizations.of(context)?.voicecommand_commandLabelCalendar ?? 'Calendar';
      case 'Symptom Tracker':
        return AppLocalizations.of(context)?.voicecommand_commandLabelTracker ?? 'Symptom Tracker';
      default:
        return commandLabel;
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
      case _VoiceStatus.confirming:
        return Colors.amber.shade800;
      case _VoiceStatus.clarifying:
        return Colors.purple.shade700;
    }
  }

  Future<void> _startListening() async {
    if (!mounted || _isListening) return;
    if (_voiceStatus == _VoiceStatus.processing ||
        _voiceStatus == _VoiceStatus.confirming ||
        _voiceStatus == _VoiceStatus.clarifying) {
      return;
    }

    bool available;
    try {
      available = await _speech.initialize(
        onError: (error) => debugPrint('Speech error: $error'),
        onStatus: (status) => debugPrint('Speech status: $status'),
      );
    } catch (e) {
      debugPrint('Speech init exception: $e');
      if (!mounted) return;
      _setStatus(
        status: _VoiceStatus.error,
        detail: AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
            'Voice not supported on this device. Use manual navigation.',
      );
      _showError(
        AppLocalizations.of(context)?.voicecommand_voiceCommandsUnavailable ??
            'Speech recognition not available',
        updateStatus: false,
      );
      _resetAfterDelay();
      return;
    }

    if (!mounted || !available) {
      if (!mounted) return;
      _setStatus(
        status: _VoiceStatus.error,
        detail: AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
            'Voice not supported on this device. Use manual navigation.',
      );
      _showError(
        AppLocalizations.of(context)?.voicecommand_voiceCommandsUnavailable ??
            'Speech recognition not available',
        updateStatus: false,
      );
      _resetAfterDelay();
      return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!mounted || !hasPermission) {
      if (!mounted) return;
      _setStatus(
        status: _VoiceStatus.error,
        detail: AppLocalizations.of(context)?.voicecommand_micDeniedGuidance ??
            'Enable microphone in device settings or use manual navigation.',
      );
      _showError(
        AppLocalizations.of(context)?.voicecommand_micPermissionsDenied ??
            'Microphone permission denied',
        updateStatus: false,
      );
      _resetAfterDelay();
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _voiceStatus = _VoiceStatus.listening;
      _recognizedText = '';
      _statusDetail = '';
    });

    try {
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
    } catch (e) {
      debugPrint('Speech listen exception: $e');
      if (!mounted) return;
      _setStatus(
        status: _VoiceStatus.error,
        detail: AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
            'Voice not supported on this device. Use manual navigation.',
      );
      _showError(
        AppLocalizations.of(context)?.voicecommand_voiceCommandsUnavailable ??
            'Speech recognition not available',
        updateStatus: false,
      );
      _reset();
      return;
    }

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

    try {
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

      // Try AI intent extraction first
      final aiResult = await VoiceIntentService.extractIntent(
        utterance: words,
        locale: Localizations.localeOf(context).languageCode,
        screenId: '/voice',
      );

      if (aiResult != null && aiResult.intent != 'unknown') {
        _speech.stop();
        _handleAIResult(aiResult, words);
        return;
      }

      // Fall through to keyword matching
      final exactMatches = _commandTable.where((c) => cmd.contains(c.phrase)).toList();

      if (exactMatches.length == 1) {
        _speech.stop();
        final match = exactMatches.first;
        final destination = VoiceIntentRegistry().resolveDestination(match.entity);
        if (destination != null) {
          setState(() {
            _pendingDestination = destination.route;
            _pendingIntent = match.intent;
            _pendingDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successOpen ?? 'open'} ${_commandLabelToDisplayText(destination.displayLabel)}?';
            _voiceStatus = _VoiceStatus.confirming;
            _statusDetail = _pendingDetail!;
          });
          return;
        }
      }

      if (exactMatches.length > 1) {
        _speech.stop();
        setState(() {
          _ambiguousMatches = exactMatches;
          _voiceStatus = _VoiceStatus.clarifying;
          _statusDetail = '${AppLocalizations.of(context)?.voicecommand_multipleMatchesCommand ?? 'Multiple matches'} \u2014 ${AppLocalizations.of(context)?.voicecommand_selectOneOptionCommand ?? 'please choose one'}';
        });
        return;
      }

      final partialMatches = _commandTable
          .where((c) => c.phrase.startsWith(cmd) && cmd.length >= 4)
          .toList();

      if (partialMatches.length > 1) {
        _speech.stop();
        setState(() {
          _ambiguousMatches = partialMatches;
          _voiceStatus = _VoiceStatus.clarifying;
          _statusDetail = '${AppLocalizations.of(context)?.voicecommand_multipleMatchesCommand ?? 'Multiple matches'} \u2014 ${AppLocalizations.of(context)?.voicecommand_selectOneOptionCommand ?? 'please choose one'}';
        });
        return;
      }

      if (partialMatches.length == 1) {
        _speech.stop();
        final match = partialMatches.first;
        final destination = VoiceIntentRegistry().resolveDestination(match.entity);
        if (destination != null) {
          setState(() {
            _pendingDestination = destination.route;
            _pendingIntent = match.intent;
            _pendingDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successOpen ?? 'open'} ${_commandLabelToDisplayText(destination.displayLabel)}?';
            _voiceStatus = _VoiceStatus.confirming;
            _statusDetail = _pendingDetail!;
          });
          return;
        }
      }

      _setStatus(
        status: _VoiceStatus.fallback,
        recognizedText: words,
        detail: '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successNotRecognized ?? 'command not recognized'}',
      );
      _showError(AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized \u2014 please try again.', updateStatus: false);
      await Future.delayed(_statusDisplayDelay);
      _reset();
    } catch (e) {
      debugPrint('Process exception: $e');
      if (!mounted) return;
      _setStatus(
        status: _VoiceStatus.error,
        detail: AppLocalizations.of(context)?.voicecommand_commandNotRecognized ??
            'Command not recognized \u2014 please try again.',
      );
      _reset();
    }
  }

  void _handleAIResult(VoiceIntentResult result, String words) {
    if (!mounted) return;

    final registry = VoiceIntentRegistry();
    final intentDef = registry.resolveIntent(result.intent);

    if (intentDef == null) {
      _setStatus(
        status: _VoiceStatus.fallback,
        recognizedText: words,
        detail: '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successNotRecognized ?? 'command not recognized'}',
      );
      _showError(AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized \u2014 please try again.', updateStatus: false);
      _resetAfterDelay();
      return;
    }

    if (result.intent == 'navigate') {
      final destination = result.destination != null
          ? registry.resolveDestinationByRoute(result.destination!)
          : null;
      final entityDest = result.entities['destination'] != null
          ? registry.resolveDestination(result.entities['destination']!)
          : null;
      final resolved = destination ?? entityDest;

      if (resolved != null) {
        setState(() {
          _pendingDestination = resolved.route;
          _pendingIntent = result.intent;
          _pendingDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successOpen ?? 'open'} ${result.displayLabel ?? resolved.displayLabel}?';
          _voiceStatus = _VoiceStatus.confirming;
          _statusDetail = _pendingDetail!;
        });
      } else if (result.destination != null) {
        setState(() {
          _pendingDestination = result.destination;
          _pendingIntent = result.intent;
          _pendingDetail = '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successOpen ?? 'open'} ${result.displayLabel ?? 'page'}?';
          _voiceStatus = _VoiceStatus.confirming;
          _statusDetail = _pendingDetail!;
        });
      } else {
        _setStatus(
          status: _VoiceStatus.fallback,
          recognizedText: words,
          detail: '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successNotRecognized ?? 'command not recognized'}',
        );
        _showError(AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized \u2014 please try again.', updateStatus: false);
        _resetAfterDelay();
      }
    } else if (intentDef.requiresConfirmation) {
      setState(() {
        _pendingDestination = null;
        _pendingIntent = result.intent;
        _pendingDetail = '${result.displayLabel ?? intentDef.displayLabel} \u2014 ${AppLocalizations.of(context)?.voicecommand_onClarifyCommandConfirm ?? 'confirm'}?';
        _voiceStatus = _VoiceStatus.confirming;
        _statusDetail = _pendingDetail!;
      });
    } else {
      _setStatus(
        status: _VoiceStatus.fallback,
        recognizedText: words,
        detail: '${AppLocalizations.of(context)?.voicecommand_successRecognized ?? 'Recognized'}: "$words" \u2014 ${AppLocalizations.of(context)?.voicecommand_successNotRecognized ?? 'command not recognized'}',
      );
      _showError(AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized \u2014 please try again.', updateStatus: false);
      _resetAfterDelay();
    }
  }

  Future<void> _resetAfterDelay() async {
    await Future.delayed(_statusDisplayDelay);
    _reset();
  }

  void _onTimeout() {
    if (!mounted || !_isListening) return;

    final txt = _buffer.trim().isNotEmpty
        ? _buffer
        : _speech.lastRecognizedWords;

    if (txt.trim().isNotEmpty) {
      _process(txt);
    } else {
      _setStatus(
        status: _VoiceStatus.error,
        detail: AppLocalizations.of(context)?.voicecommand_timeoutGuidance ??
            'Tap the microphone to try again.',
      );
      _showError(
        AppLocalizations.of(context)?.voicecommand_voiceTimedOut ??
            'Listening timed out.',
        updateStatus: false,
      );
      _resetAfterDelay();
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
        _pendingDestination = null;
        _pendingDetail = null;
        _ambiguousMatches = [];
      });
    }
  }

  void _onConfirm() {
    if (!mounted) return;

    final intent = _pendingIntent ?? 'navigate';
    final intentDef = VoiceIntentRegistry().resolveIntent(intent);

    if (_pendingDestination != null) {
      final destination = _pendingDestination!;
      _setStatus(
        status: _VoiceStatus.success,
        detail: '${AppLocalizations.of(context)?.voicecommand_onConfirmedCommand ?? 'Confirmed'} \u2014 ${AppLocalizations.of(context)?.voicecommand_onConfirmedCommandNavigate ?? 'navigating'}',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      context.go(destination);
      _reset();
    } else if (intentDef != null && intentDef.handler != null) {
      _setStatus(
        status: _VoiceStatus.success,
        detail: '${AppLocalizations.of(context)?.voicecommand_onConfirmedCommand ?? 'Confirmed'} \u2014 ${intentDef.displayLabel}',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _resetAfterDelay();
    } else {
      _setStatus(
        status: _VoiceStatus.success,
        detail: AppLocalizations.of(context)?.voicecommand_intentNotYetSupported ?? 'This action is not yet available. Use manual navigation.',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _resetAfterDelay();
    }
  }

  void _onCancelConfirmation() {
    _pendingDestination = null;
    _pendingDetail = null;
    _pendingIntent = null;
    _ambiguousMatches = [];
    _reset();
  }

  void _onClarifyChoice(_CommandMatch choice) {
    if (!mounted) return;
    final destination = VoiceIntentRegistry().resolveDestination(choice.entity);
    setState(() {
      _ambiguousMatches = [];
      _pendingDestination = destination?.route;
      _pendingIntent = choice.intent;
      _pendingDetail = '${AppLocalizations.of(context)?.voicecommand_onClarifyCommand ?? 'Selected'}: ${_commandLabelToDisplayText(destination?.displayLabel ?? choice.entity)} — ${AppLocalizations.of(context)?.voicecommand_onClarifyCommandConfirm ?? 'confirm'}?';
      _voiceStatus = _VoiceStatus.confirming;
      _statusDetail = _pendingDetail!;
    });
  }

  void _onMicPressed() {
    if (_voiceStatus == _VoiceStatus.processing ||
        _voiceStatus == _VoiceStatus.confirming ||
        _voiceStatus == _VoiceStatus.clarifying) {
      return;
    }

    if (_isListening) {
      _timeoutTimer?.cancel();
      _speech.stop();

      final text = _buffer.trim().isNotEmpty
          ? _buffer
          : _speech.lastRecognizedWords;

      if (text.trim().isNotEmpty) {
        _process(text);
      } else {
        _setStatus(
          status: _VoiceStatus.error,
          detail: AppLocalizations.of(context)?.voicecommand_noSpeechGuidance ??
              'No speech heard. Tap the microphone to try again.',
        );
        _showError(
          AppLocalizations.of(context)?.voicecommand_noSpeechDetected ??
              'No speech detected.',
          updateStatus: false,
        );
        _resetAfterDelay();
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
          if (_voiceStatus == _VoiceStatus.confirming)
            _buildConfirmActions(),
          if (_voiceStatus == _VoiceStatus.clarifying)
            _buildClarifyActions(),
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

  Widget _buildConfirmActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton.icon(
            key: const Key('voice_confirm_btn'),
            onPressed: _onConfirm,
            icon: const Icon(Icons.check),
            label: Text(AppLocalizations.of(context)?.voicecommand_confirmButton ?? 'Confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            key: const Key('voice_cancel_btn'),
            onPressed: _onCancelConfirmation,
            icon: const Icon(Icons.close),
            label: Text(AppLocalizations.of(context)?.voicecommand_cancelButton ?? 'Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildClarifyActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _ambiguousMatches.map((match) {
              final destination = VoiceIntentRegistry().resolveDestination(match.entity);
              return ActionChip(
                key: Key('voice_clarify_${destination?.route ?? match.entity}'),
                avatar: const Icon(Icons.arrow_forward, size: 18),
                label: Text(_commandLabelToDisplayText(destination?.displayLabel ?? match.entity)),
                onPressed: () => _onClarifyChoice(match),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('voice_clarify_cancel_btn'),
            onPressed: _onCancelConfirmation,
            icon: const Icon(Icons.close),
            label: Text(AppLocalizations.of(context)?.voicecommand_cancelButton ?? 'Cancel'),
          ),
        ],
      ),
    );
  }
}

class _CommandMatch {
  final String phrase;
  final String intent;
  final String entity;

  const _CommandMatch({
    required this.phrase,
    required this.intent,
    required this.entity,
  });
}
