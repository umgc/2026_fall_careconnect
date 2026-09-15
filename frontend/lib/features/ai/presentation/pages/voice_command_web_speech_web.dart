// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_util' as js_util;

class VoiceCommandWebSpeechController {
  JSObject? _recognition;
  String _lastRecognizedWords = '';

  String get lastRecognizedWords => _lastRecognizedWords;

  Object? _speechRecognitionCtor() {
    return js_util.getProperty(html.window, 'SpeechRecognition') ??
        js_util.getProperty(html.window, 'webkitSpeechRecognition');
  }

  Object? _listEntryAt(Object listLike, int index) {
    final direct = js_util.getProperty(listLike, '$index');
    if (direct != null) {
      return direct as Object;
    }

    try {
      final viaItem = js_util.callMethod(listLike, 'item', [index]);
      if (viaItem != null) {
        return viaItem as Object;
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

    _recognition ??= js_util.callConstructor(ctor, []);
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

    js_util.setProperty(recognition, 'continuous', true);
    js_util.setProperty(recognition, 'interimResults', true);
    js_util.setProperty(recognition, 'maxAlternatives', 1);
    js_util.setProperty(recognition, 'lang', resolvedLocale);

    js_util.setProperty(
      recognition,
      'onstart',
      ((JSAny? _) => onStatus('listening')).toJS,
    );
    js_util.setProperty(
      recognition,
      'onspeechstart',
      ((JSAny? _) => onStatus('listening')).toJS,
    );
    js_util.setProperty(
      recognition,
      'onresult',
      ((JSAny? event) {
        try {
          final eventObject = event as Object;
          final results = js_util.getProperty(eventObject, 'results');
          if (results is! Object) {
            return;
          }
          final resultIndex = _toInt(
            js_util.getProperty(eventObject, 'resultIndex'),
          );
          final length = _toInt(js_util.getProperty(results, 'length'));

          for (var index = resultIndex; index < length; index++) {
            final result = _listEntryAt(results, index);
            if (result == null) {
              continue;
            }
            final isFinal = _toBool(js_util.getProperty(result, 'isFinal'));
            final alternative = _listEntryAt(result, 0);
            if (alternative == null) {
              continue;
            }
            final transcript =
                js_util.getProperty(alternative, 'transcript')?.toString() ?? '';

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
      }).toJS,
    );
    js_util.setProperty(
      recognition,
      'onerror',
      ((JSAny? event) {
        final eventObject = event as Object;
        final errorCode =
            js_util.getProperty(eventObject, 'error')?.toString() ?? 'unknown';
        onError(errorCode);
      }).toJS,
    );
    js_util.setProperty(
      recognition,
      'onend',
      ((JSAny? _) => onStatus('notListening')).toJS,
    );

    try {
      js_util.callMethod(recognition, 'start', []);
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
      js_util.callMethod(recognition, 'stop', []);
    } catch (_) {}
  }

  // Intentionally no availability/install calls: Chrome support for these
  // experimental methods is inconsistent and can cause false negatives.
}