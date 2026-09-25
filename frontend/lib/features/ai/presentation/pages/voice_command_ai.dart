import 'dart:async';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/services/voice_intent_registry.dart';
import 'package:care_connect_app/services/voice_intent_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'voice_command_web_speech.dart';

enum _VoiceStatus {
  idle,
  listening,
  processing,
  success,
  captured,
  fallback,
  error,
  confirming,
  clarifying
}

enum VoiceCommandPresentation { page, flyout }

class VoiceCommandAI extends StatefulWidget {
  final bool singleShot;
  final VoiceCommandPresentation presentationMode;
  final void Function(String destination)? onNavigateRequested;
  final void Function()? onCloseRequested;

  const VoiceCommandAI({
    super.key,
    this.singleShot = false,
    this.presentationMode = VoiceCommandPresentation.page,
    this.onNavigateRequested,
    this.onCloseRequested,
  });

  @override
  State<VoiceCommandAI> createState() => _VoiceCommandAIState();
}

class _VoiceCommandAIState extends State<VoiceCommandAI> {
  PorcupineManager? _porcupine;
  late stt.SpeechToText _speech;
  final VoiceCommandWebSpeechController _webSpeech =
      VoiceCommandWebSpeechController();

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
    _CommandMatch(phrase: 'open calendar', intent: 'navigate', entity: 'calendar'),
    _CommandMatch(phrase: 'take me to my tracker', intent: 'navigate', entity: 'symptoms'),
    _CommandMatch(phrase: 'open symptoms', intent: 'navigate', entity: 'symptoms'),
    _CommandMatch(phrase: 'open messages', intent: 'navigate', entity: 'messages'),
    _CommandMatch(phrase: 'take me to messages', intent: 'navigate', entity: 'messages'),
    _CommandMatch(phrase: 'open profile', intent: 'navigate', entity: 'profile'),
    _CommandMatch(phrase: 'open settings', intent: 'navigate', entity: 'settings'),
    _CommandMatch(phrase: 'open menu', intent: 'navigate', entity: 'menu'),
    // Health
    _CommandMatch(phrase: 'open medication tracker', intent: 'navigate', entity: 'medication'),
    _CommandMatch(phrase: 'take me to medications', intent: 'navigate', entity: 'medications'),
    _CommandMatch(phrase: 'open medications', intent: 'navigate', entity: 'medications'),
    _CommandMatch(phrase: 'open my medications', intent: 'navigate', entity: 'medications'),
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
    //emergency
    _CommandMatch(phrase: 'emergency', intent: 'sos', entity: 'emergency'),
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    registerDefaultVoiceIntents();
  }

  Duration get _statusDisplayDelay => kDebugMode
      ? const Duration(seconds: 5)
      : const Duration(milliseconds: 300);

  bool get _isFlyout =>
      widget.presentationMode == VoiceCommandPresentation.flyout;

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
      debugPrint(
          'Porcupine wake word detection disabled on web - use mic button instead');
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final wakeWordErrorLabel =
        AppLocalizations.of(context)?.voicecommand_wakeWordError ??
            'Wake word init error';

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
        SnackBar(content: Text('$wakeWordErrorLabel: ${e.message}')),
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

  Future<void> _stopListeningBackend() async {
    // Speech backend differs by platform: web uses browser speech APIs,
    // native uses speech_to_text. Centralizing stop avoids split cleanup logic.
    if (kIsWeb) {
      await _webSpeech.stop();
      return;
    }

    _speech.stop();
  }

  String _lastRecognizedWordsBackend() {
    return kIsWeb
        ? _webSpeech.lastRecognizedWords
        : _speech.lastRecognizedWords;
  }

  String _voiceUnavailableMessage() {
    return AppLocalizations.of(context)
            ?.voicecommand_voiceCommandsUnavailable ??
        'Speech recognition not available';
  }

  String _noSpeechMessage() {
    return AppLocalizations.of(context)?.voicecommand_noSpeechDetected ??
        'No speech detected.';
  }

  String _noSpeechGuidance() {
    return AppLocalizations.of(context)?.voicecommand_noSpeechGuidance ??
        'No speech heard. Tap the microphone to try again.';
  }

  String _webSpeechErrorMessage(String errorCode) {
    switch (errorCode) {
      case 'network':
        return 'Speech recognition network error. Try again in Chrome.';
      case 'not-allowed':
      case 'service-not-allowed':
        return AppLocalizations.of(context)
                ?.voicecommand_micPermissionsDenied ??
            'Microphone permission denied';
      case 'audio-capture':
        return 'No microphone was found for speech recognition.';
      case 'no-speech':
        return _noSpeechMessage();
      case 'aborted':
        return 'Speech recognition was interrupted. Try again.';
      default:
        return 'Speech recognition failed in Chrome ($errorCode).';
    }
  }

  String _webSpeechGuidance(String errorCode) {
    switch (errorCode) {
      case 'not-allowed':
      case 'service-not-allowed':
        return AppLocalizations.of(context)?.voicecommand_micDeniedGuidance ??
            'Enable microphone in device settings or use manual navigation.';
      case 'no-speech':
        return _noSpeechGuidance();
      case 'audio-capture':
        return 'Connect or enable a microphone, then try again.';
      default:
        return AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
            'Voice not supported on this device. Use manual navigation.';
    }
  }

  void _closeRequested() {
    // Delegate close behavior to parent when hosted as an overlay/flyout.
    // Falls back to local pop for standalone page mode.
    final handler = widget.onCloseRequested;
    if (handler != null) {
      handler();
      return;
    }

    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _navigateTo(String destination) {
    // Navigation can be owned by the host container (for overlays) to ensure
    // dialogs close before route changes; fallback keeps page mode working.
    final handler = widget.onNavigateRequested;
    if (handler != null) {
      handler(destination);
      return;
    }

    if (!mounted) return;
    context.go(destination);
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

  String _commandLabelToDisplayText(String commandLabel) {
    switch (commandLabel) {
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

  String _commandPhraseToTranslatedString(String commandPhrase) {
    switch (commandPhrase) {
      case 'take me home':
        return AppLocalizations.of(context)?.voicecommand_commandPhraseHome ?? 'take me home';
      case 'take me to calendar':
        return AppLocalizations.of(context)?.voicecommand_commandPhraseCalendar ?? 'take me to calendar';
      case 'take me to my tracker':
        return AppLocalizations.of(context)?.voicecommand_commandPhraseTracker ?? 'take me to my tracker';
      default:
        return commandPhrase;
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

    if (kIsWeb) {
      // Porcupine wake word is not available on web, so web uses explicit
      // mic-triggered browser recognition with equivalent status handling.
      bool available = await _webSpeech.initialize();
      if (!mounted || !available) {
        if (!mounted) return;
        _setStatus(
          status: _VoiceStatus.error,
          detail:
              AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
                  'Voice not supported on this device. Use manual navigation.',
        );
        _showError(_voiceUnavailableMessage(), updateStatus: false);
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

      final localeTag = Localizations.localeOf(context).toLanguageTag();
      try {
        final started = await _webSpeech.listen(
          localeId: localeTag,
          onStatus: (status) {
            debugPrint('Speech status: $status');
            if (!mounted || !_isListening) return;

            if (status == 'listening') {
              if (_voiceStatus != _VoiceStatus.listening) {
                setState(() {
                  _voiceStatus = _VoiceStatus.listening;
                  _statusDetail = '';
                });
              }
              return;
            }

            if (status == 'notListening') {
              Future<void>.delayed(const Duration(milliseconds: 250), () {
                if (!mounted || !_isListening) return;

                final heardText = _buffer.trim().isNotEmpty
                    ? _buffer
                    : _lastRecognizedWordsBackend();

                if (heardText.trim().isNotEmpty) {
                  _process(heardText);
                } else {
                  _setStatus(
                    status: _VoiceStatus.error,
                    detail: _noSpeechGuidance(),
                  );
                  _showError(_noSpeechMessage(), updateStatus: false);
                  _resetAfterDelay();
                }
              });
            }
          },
          onError: (errorCode) {
            debugPrint('Speech error: $errorCode');
            if (!mounted) return;

            _setStatus(
              status: _VoiceStatus.error,
              detail: _webSpeechGuidance(errorCode),
            );
            final message = _webSpeechErrorMessage(errorCode);
            _showError(message, updateStatus: false);
            _resetAfterDelay();
          },
          onResult: (words, finalResult) {
            if (!mounted || words.trim().isEmpty) return;
            _buffer = words;
            setState(() {
              _recognizedText = words;
              _voiceStatus = _VoiceStatus.listening;
            });
            if (finalResult) {
              _timeoutTimer?.cancel();
              _process(_buffer.isNotEmpty ? _buffer : words);
            }
          },
        );

        if (!mounted || !started) {
          if (!mounted) return;
          _setStatus(
            status: _VoiceStatus.error,
            detail:
                'Speech recognition could not start in Chrome. Check microphone access and try again.',
          );
          _showError(
            'Speech recognition could not start in Chrome.',
            updateStatus: false,
          );
          _resetAfterDelay();
          return;
        }
      } catch (e) {
        debugPrint('Web speech listen exception: $e');
        if (!mounted) return;
        _setStatus(
          status: _VoiceStatus.error,
          detail:
              'Speech recognition failed to start in Chrome. Check microphone access and try again.',
        );
        _showError(
          'Speech recognition failed to start in Chrome.',
          updateStatus: false,
        );
        _resetAfterDelay();
        return;
      }

      _timeoutTimer = Timer(const Duration(seconds: 12), _onTimeout);
      return;
    }

    bool available;
    try {
      available = await _speech.initialize(
        onError: (error) {
          debugPrint('Speech error: $error');
          if (!mounted) return;
          _setStatus(
            status: _VoiceStatus.error,
            detail: AppLocalizations.of(context)
                    ?.voicecommand_unavailableGuidance ??
                'Voice not supported on this device. Use manual navigation.',
          );
          _showError(_voiceUnavailableMessage(), updateStatus: false);
          _resetAfterDelay();
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (!mounted || !_isListening) return;

          if (status == 'listening') {
            if (_voiceStatus != _VoiceStatus.listening) {
              setState(() {
                _voiceStatus = _VoiceStatus.listening;
                _statusDetail = '';
              });
            }
            return;
          }

          if (status == 'done' || status == 'notListening') {
            Future<void>.delayed(const Duration(milliseconds: 250), () {
              if (!mounted || !_isListening) return;

              final heardText = _buffer.trim().isNotEmpty
                  ? _buffer
                  : _lastRecognizedWordsBackend();

              if (heardText.trim().isNotEmpty) {
                _process(heardText);
              } else {
                _setStatus(
                  status: _VoiceStatus.error,
                  detail: _noSpeechGuidance(),
                );
                _showError(_noSpeechMessage(), updateStatus: false);
                _resetAfterDelay();
              }
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Speech init exception: $e');
      if (!mounted) return;
      _setStatus(
        status: _VoiceStatus.error,
        detail:
            AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
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
        detail:
            AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
                'Voice not supported on this device. Use manual navigation.',
      );
      _showError(_voiceUnavailableMessage(), updateStatus: false);
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
        localeId: Localizations.localeOf(context).languageCode,
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
          listenMode: stt.ListenMode.confirmation,
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
        detail:
            AppLocalizations.of(context)?.voicecommand_unavailableGuidance ??
                'Voice not supported on this device. Use manual navigation.',
      );
      _showError(_voiceUnavailableMessage(), updateStatus: false);
      _reset();
      return;
    }

    _timeoutTimer = Timer(const Duration(seconds: 12), _onTimeout);
  }

  Future<void> _process(String words) async {
    if (!mounted) return;

   // print to screen what you heard for debugging purposes 
    final cmd = words.toLowerCase().trim();
    debugPrint('Heard: $cmd');
  // end debug print

  //Use voice to confirm or cancel the action if we are in the confirming popup/state
  if (_voiceStatus == _VoiceStatus.confirming) {
      if (cmd.contains('confirm') || cmd == 'yes' || cmd == 'proceed') {
        unawaited(_stopListeningBackend());
        await _onConfirm();
        return;
      } else if (cmd.contains('cancel') || cmd == 'no' || cmd == 'stop') {
        unawaited(_stopListeningBackend());
        _setStatus(
          status: _VoiceStatus.idle,
          detail: 'Action cancelled.',
        );
        _pendingDestination = null;
        _pendingDetail = null;
        _pendingIntent = null;
        _ambiguousMatches = [];
        _resetAfterDelay();
        return;
      }
    }

    //end voice confirm/cancel logic

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
        unawaited(_stopListeningBackend());
        _setStatus(
          status: _VoiceStatus.captured,
          recognizedText: words,
          detail:
              '${AppLocalizations.of(context)?.voicecommand_speechCaptured ?? 'Speech captured'}: "$words"',
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
        unawaited(_stopListeningBackend());
        _handleAIResult(aiResult, words);
        return;
      }

      // Fall through to keyword matching
      final exactMatches = _commandTable
          .where(
              (c) => cmd.contains(_commandPhraseToTranslatedString(c.phrase)))
          .toList();

      if (exactMatches.length == 1) {
        //if there is an exact match, turn off mic
        unawaited(_stopListeningBackend());

        final match = exactMatches.first;
        final registry = VoiceIntentRegistry(); //added variable for method
        final intentDef = registry.resolveIntent(match.intent);

        //added support for intents that don't have a destination, like SOS
        // Navigation commands
        if (match.intent == 'navigate') {
          final destination = registry.resolveDestination(match.entity);
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

        //other commands that dont need a destination, like SOS
        else if (intentDef != null) {
          setState(() {
            _pendingDestination = null; // NOT navigating to a screen, keep null
            _pendingIntent = match.intent; 
            _pendingDetail = '${intentDef.displayLabel} \u2014 confirm?';
            _voiceStatus = _VoiceStatus.confirming;
            _statusDetail = _pendingDetail!;
          });
          // call _startConfirmationListening to listen for verbal confirmation or cancellation 
          // of the command with a handler 
          _startConfirmationListening();
          return;
        }
      }

      if (exactMatches.length > 1) {
        unawaited(_stopListeningBackend());
        setState(() {
          _ambiguousMatches = exactMatches;
          _voiceStatus = _VoiceStatus.clarifying;
          _statusDetail =
              '${AppLocalizations.of(context)?.voicecommand_multipleMatchesCommand ?? 'Multiple matches'} \u2014 ${AppLocalizations.of(context)?.voicecommand_selectOneOptionCommand ?? 'please choose one'}';
        });
        return;
      }

      final partialMatches = _commandTable
          .where((c) =>
              _commandPhraseToTranslatedString(c.phrase).startsWith(cmd) &&
              cmd.length >= 4)
          .toList();

      if (partialMatches.length > 1) {
        unawaited(_stopListeningBackend());
        setState(() {
          _ambiguousMatches = partialMatches;
          _voiceStatus = _VoiceStatus.clarifying;
          _statusDetail =
              '${AppLocalizations.of(context)?.voicecommand_multipleMatchesCommand ?? 'Multiple matches'} \u2014 ${AppLocalizations.of(context)?.voicecommand_selectOneOptionCommand ?? 'please choose one'}';
        });
        return;
      }

      if (partialMatches.length == 1) {
        unawaited(_stopListeningBackend());
        final match = partialMatches.first;
        final registry = VoiceIntentRegistry(); //added variable for method
        final intentDef = registry.resolveIntent(match.intent);
        if (match.intent == 'navigate') {
          final destination = registry.resolveDestination(match.entity);
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

        //other commands that dont need a destination, like SOS
        else if (intentDef != null) {
          setState(() {
            _pendingDestination = null; // NOT navigating to a screen, keep null
            _pendingIntent = match.intent; 
            _pendingDetail = '${intentDef.displayLabel} \u2014 confirm?';
            _voiceStatus = _VoiceStatus.confirming;
            _statusDetail = _pendingDetail!;
          });
          
          // call _startConfirmationListening to listen for verbal confirmation or cancellation
          _startConfirmationListening();
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
        detail: AppLocalizations.of(context)?.voicecommand_commandNotRecognized ?? 'Command not recognized \u2014 please try again.',
      );
      _reset();
    }
  }

// Re-open listening specifically for first block verbal confirmation or cancellation
  void _startConfirmationListening() async {
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted || _voiceStatus != _VoiceStatus.confirming) return;

    final localeTag = Localizations.localeOf(context).toLanguageTag();

    void onHeard(String raw) async {
      final heard = raw.toLowerCase().trim();
      debugPrint('Gate 1 Confirmation Heard: $heard');

      if (heard.contains('confirm') || heard == 'yes' || heard == 'proceed') {
        await _stopListeningBackend();
        await _onConfirm();
      } else if (heard.contains('cancel') || heard == 'no' || heard == 'stop') {
        await _stopListeningBackend();
        _setStatus(
          status: _VoiceStatus.idle,
          detail: 'Action cancelled.',
        );
        _pendingDestination = null;
        _pendingDetail = null;
        _pendingIntent = null;
        _ambiguousMatches = [];
        _resetAfterDelay();
      }
    }

    if (kIsWeb) {
      await _webSpeech.listen(
        localeId: localeTag,
        onStatus: (status) => debugPrint('Web Confirmation Status: $status'),
        onError: (err) => debugPrint('Web Confirmation Error: $err'),
        onResult: (words, finalResult) {
          if (words.trim().isNotEmpty) {
            onHeard(words);
          }
        },
      );
    } else {
      await _speech.listen(
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        onResult: (result) {
          if (result.recognizedWords.isNotEmpty) {
            onHeard(result.recognizedWords);
          }
        },
      );
    }
  }
  //end _startConfirmationListening

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

    final txt = _buffer.trim().isNotEmpty ? _buffer : _lastRecognizedWordsBackend();

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
    unawaited(_stopListeningBackend());
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

  Future<void> _onConfirm() async {
    if (!mounted) return;

    final intent = _pendingIntent ?? 'navigate';
    final intentDef = VoiceIntentRegistry().resolveIntent(intent);

// Check if the intent is high-risk and requires explicit confirmation via voice 
// or touch input before proceeding
// If the user cancels or dismisses the dialog, abort the action 
// and reset the state

if (intentDef?.riskLevel == IntentRiskLevel.high) {
      final titleLabel = intentDef?.displayLabel ?? 'High-Risk Action';
      final localeTag = Localizations.localeOf(context).toLanguageTag();

      final bool? userConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          // Listen for confirmation vocal keywords on both Web and Mobile
          Future.delayed(const Duration(milliseconds: 350), () async {
            void handleGate2Voice(String spoken) {
              final clean = spoken.toLowerCase().trim();
              debugPrint('Gate 2 Heard: $clean');

              if (clean.contains('confirm') || clean == 'yes' || clean == 'proceed') {
                _stopListeningBackend();
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop(true);
                }
              } else if (clean.contains('cancel') || clean == 'no' || clean == 'stop') {
                _stopListeningBackend();
                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.of(dialogContext).pop(false);
                }
              }
            }

            if (kIsWeb) {
              await _webSpeech.listen(
                localeId: localeTag,
                onStatus: (s) => debugPrint('Gate 2 Web Status: $s'),
                onError: (e) => debugPrint('Gate 2 Web Error: $e'),
                onResult: (words, _) {
                  if (words.trim().isNotEmpty) handleGate2Voice(words);
                },
              );
            } else {
              if (!_speech.isListening) {
                await _speech.listen(
                  listenFor: const Duration(seconds: 12),
                  pauseFor: const Duration(seconds: 2),
                  onResult: (r) {
                    if (r.recognizedWords.isNotEmpty) handleGate2Voice(r.recognizedWords);
                  },
                );
              }
            }
          });

          return AlertDialog(
            title: Text('Confirm $titleLabel'),
            content: Text(
              'Are you sure you want to trigger "$titleLabel"? '
              'Say "confirm" or "cancel", or tap a button below.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _stopListeningBackend();
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  _stopListeningBackend();
                  Navigator.of(dialogContext).pop(true);
                },
                child: Text('Confirm $titleLabel'),
              ),
            ],
          );
        },
      );

      // Stop listening to the backend after the dialog is closed
      unawaited(_stopListeningBackend());

    // If widget unmounted while waiting for user interaction, stop
    if (!mounted) return;

    // Abort if cancelled or dismissed
    if (userConfirmed != true) {
      _setStatus(
        status: _VoiceStatus.idle,
        detail: '$titleLabel cancelled.',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _resetAfterDelay();
      return; // Stops execution: handler will NOT run
    }
  }

  //end High risk popup confirmation logic with voice listening

  if (!mounted) return;

    if (_pendingDestination != null) {
      final destination = _pendingDestination!;
      _setStatus(
        status: _VoiceStatus.success,
        detail:
            '${AppLocalizations.of(context)?.voicecommand_onConfirmedCommand ?? 'Confirmed'} \u2014 ${AppLocalizations.of(context)?.voicecommand_onConfirmedCommandNavigate ?? 'navigating'}',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _reset();
      _navigateTo(destination);
    } else if (intentDef != null && intentDef.handler != null) { 
      //if the intent is defined and has a handler, call the handler
      await intentDef.handler!({}); // Calls the handler for the intent
      
      _setStatus(
        status: _VoiceStatus.success,
        detail:
            '${AppLocalizations.of(context)?.voicecommand_onConfirmedCommand ?? 'Confirmed'} \u2014 ${intentDef.displayLabel}',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _resetAfterDelay();
    } else if (intent == 'schedule') {
      // Map schedule intent to the existing calendar surface (no telephony/scheduling API yet).
      _setStatus(
        status: _VoiceStatus.success,
        detail:
            '${AppLocalizations.of(context)?.voicecommand_onConfirmedCommand ?? 'Confirmed'} \u2014 ${AppLocalizations.of(context)?.voicecommand_onConfirmedCommandNavigate ?? 'navigating'}',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _reset();
      _navigateTo('/calendar');
    } else {
      _setStatus(
        status: _VoiceStatus.success,
        detail:
            AppLocalizations.of(context)?.voicecommand_intentNotYetSupported ??
                'This action is not yet available. Use manual navigation.',
      );
      _pendingDestination = null;
      _pendingDetail = null;
      _pendingIntent = null;
      _ambiguousMatches = [];
      _resetAfterDelay();
    }
  }

  KeyEventResult _handleFlyoutKey(FocusNode node, KeyEvent event) {
    // Keyboard support is intentionally scoped to flyout usability and should
    // remain minimal to avoid stealing global app shortcuts.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _closeRequested();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      FocusScope.of(context).nextFocus();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      FocusScope.of(context).previousFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
      _pendingDetail =
          '${AppLocalizations.of(context)?.voicecommand_onClarifyCommand ?? 'Selected'}: ${_commandLabelToDisplayText(destination?.displayLabel ?? choice.entity)} — ${AppLocalizations.of(context)?.voicecommand_onClarifyCommandConfirm ?? 'confirm'}?';
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
      unawaited(_stopListeningBackend());

      final text =
          _buffer.trim().isNotEmpty ? _buffer : _lastRecognizedWordsBackend();

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
    unawaited(_stopListeningBackend());
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

  Widget _buildVoiceScaffold({required bool showCloseAction}) {
    final title = AppLocalizations.of(context)?.voicecommand_voiceCommandTitle ?? 'Voice Commands';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.blue.shade900,
        actions: [
          if (showCloseAction)
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: _closeRequested,
              icon: const Icon(Icons.close),
            ),
        ],
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
                ? (kIsWeb
                    ? AppLocalizations.of(context)
                            ?.voicecommand_tapMicToStart ??
                        'Tap mic to start'
                    : AppLocalizations.of(context)
                            ?.voicecommand_wakeWordToStart ??
                        'Say wake word or tap mic')
                : _isListening
                    ? '${AppLocalizations.of(context)?.voicecommand_listeningState ?? 'Listening'}...'
                    : '${AppLocalizations.of(context)?.voicecommand_processingState ?? 'Processing'}...',
            style: const TextStyle(fontSize: 18),
          ),
          _buildStatusArea(),
          if (_voiceStatus == _VoiceStatus.confirming) _buildConfirmActions(),
          if (_voiceStatus == _VoiceStatus.clarifying) _buildClarifyActions(),
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

  Widget _buildFlyoutSurface() {
    final media = MediaQuery.of(context);
    final maxWidth = media.size.width < 720 ? media.size.width - 24 : 560.0;

    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextFocusIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight): const NextFocusIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const PreviousFocusIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft):
            const PreviousFocusIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _closeRequested();
              return null;
            },
          ),
          NextFocusIntent: CallbackAction<NextFocusIntent>(
            onInvoke: (_) {
              FocusScope.of(context).nextFocus();
              return null;
            },
          ),
          PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
            onInvoke: (_) {
              FocusScope.of(context).previousFocus();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          onKeyEvent: _handleFlyoutKey,
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: maxWidth,
              height: media.size.height,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 24,
                    offset: Offset(-4, 0),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _buildVoiceScaffold(showCloseAction: true),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isFlyout) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: _buildFlyoutSurface(),
      );
    }

    return _buildVoiceScaffold(showCloseAction: false);
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
            label: Text(
                AppLocalizations.of(context)?.voicecommand_cancelButton ??
                    'Cancel'),
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
              final destination =
                  VoiceIntentRegistry().resolveDestination(match.entity);
              return ActionChip(
                key: Key('voice_clarify_${destination?.route ?? match.entity}'),
                avatar: const Icon(Icons.arrow_forward, size: 18),
                label: Text(_commandLabelToDisplayText(
                    destination?.displayLabel ?? match.entity)),
                onPressed: () => _onClarifyChoice(match),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('voice_clarify_cancel_btn'),
            onPressed: _onCancelConfirmation,
            icon: const Icon(Icons.close),
            label: Text(
                AppLocalizations.of(context)?.voicecommand_cancelButton ??
                    'Cancel'),
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
