import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class VoiceCommandWebSpeechController {
  JSObject? _recognition;
  String _lastRecognizedWords = '';

  String get lastRecognizedWords => _lastRecognizedWords;

  JSFunction? _speechRecognitionCtor() {
    return (globalContext['SpeechRecognition'] ??
        globalContext['webkitSpeechRecognition']) as JSFunction?;
  }

  JSObject? _listEntryAt(JSObject listLike, int index) {
    final direct = listLike['$index'];
    if (direct != null) {
      return direct as JSObject;
    }

    try {
      final viaItem = listLike.callMethod<JSAny?>('item'.toJS, index.toJS);
      if (viaItem != null) {
        return viaItem as JSObject;
      }
    } catch (_) {}

    return null;
  }

  int _toInt(Object? value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }

    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed ?? fallback;
  }

  bool _toBool(Object? value) {
    if (value is bool) {
      return value;
    }

    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1';
  }

  String _resolveLocale(String localeId) {
    final normalized = localeId.trim();
    if (normalized.isEmpty) {
      return 'en-US';
    }

    final languageCode = normalized.split(RegExp('[-_]')).first.toLowerCase();
    if (languageCode == 'en') {
      return 'en-US';
    }

    return normalized;
  }

  Future<bool> initialize() async {
    final ctor = _speechRecognitionCtor();
    if (ctor == null) {
      return false;
    }

    _recognition ??= ctor.callAsConstructor<JSObject>();
    return true;
  }

  Future<bool> listen({
    required String localeId,
    required void Function(String status) onStatus,
    required void Function(String errorCode) onError,
    required void Function(String words, bool finalResult) onResult,
  }) async {
    final recognition = _recognition;
    if (recognition == null) {
      return false;
    }

    _lastRecognizedWords = '';
    final resolvedLocale = _resolveLocale(localeId);

    recognition['continuous'] = true.toJS;
    recognition['interimResults'] = true.toJS;
    recognition['maxAlternatives'] = 1.toJS;
    recognition['lang'] = resolvedLocale.toJS;

    recognition['onstart'] = ((JSAny? _) => onStatus('listening')).toJS;
    recognition['onspeechstart'] = ((JSAny? _) => onStatus('listening')).toJS;
    recognition['onresult'] = ((JSObject event) {
      try {
        final results = event['results'];
        if (results == null) {
          return;
        }
        final resultsObject = results as JSObject;
        final resultIndex = _toInt(event['resultIndex']?.dartify());
        final length = _toInt(resultsObject['length']?.dartify());

        for (var index = resultIndex; index < length; index++) {
          final result = _listEntryAt(resultsObject, index);
          if (result == null) {
            continue;
          }
          final isFinal = _toBool(result['isFinal']?.dartify());
          final alternative = _listEntryAt(result, 0);
          if (alternative == null) {
            continue;
          }
          final transcript =
              alternative['transcript']?.dartify()?.toString() ?? '';

          if (transcript.trim().isEmpty) {
            continue;
          }

          _lastRecognizedWords = transcript;
          onResult(transcript, isFinal);

          if (isFinal) {
            break;
          }
        }
      } catch (_) {
        // Swallow parsing failures and let onend/onerror paths recover.
      }
    }).toJS;
    recognition['onerror'] = ((JSObject event) {
      final errorCode = event['error']?.dartify()?.toString() ?? 'unknown';
      onError(errorCode);
    }).toJS;
    recognition['onend'] = ((JSAny? _) => onStatus('notListening')).toJS;

    try {
      recognition.callMethod<JSAny?>('start'.toJS);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      final recognition = _recognition;
      if (recognition == null) {
        return;
      }
      recognition.callMethod<JSAny?>('stop'.toJS);
    } catch (_) {}
  }

  // Intentionally no availability/install calls: Chrome support for these
  // experimental methods is inconsistent and can cause false negatives.
}
