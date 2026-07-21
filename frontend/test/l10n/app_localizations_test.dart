// Tests for AppLocalizations delegate and lookupAppLocalizations
// (lib/l10n/app_localizations.dart).
//
// Coverage strategy:
//   The testable surface of app_localizations.dart consists of:
//     - lookupAppLocalizations(Locale) — switch over 14 language codes,
//       throws FlutterError for unsupported locales.
//     - _AppLocalizationsDelegate.isSupported(Locale) — checks 14 codes.
//     - _AppLocalizationsDelegate.shouldReload — always returns false.
//
//   The abstract getter declarations and of(BuildContext) require a live
//   widget tree and are excluded from unit testing.
//
//   Branches tested:
//     lookupAppLocalizations — every supported language code returns a
//                              non-null AppLocalizations instance whose
//                              localeName matches the language code.
//     lookupAppLocalizations — unsupported locale throws FlutterError.
//     isSupported            — all 14 supported codes → true.
//     isSupported            — unsupported code ('xx') → false.
//     shouldReload           — always returns false.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Convenience: the delegate exposed via AppLocalizations.delegate.
  const delegate = AppLocalizations.delegate;

  // ─── lookupAppLocalizations ───────────────────────────────────────────────

  group('lookupAppLocalizations', () {
    // All 14 supported language codes.
    const supported = [
      'am',
      'ar',
      'bn',
      'en',
      'es',
      'fa',
      'fr',
      'hi',
      'ja',
      'ne',
      'pt',
      'ru',
      'ur',
      'zh',
    ];

    for (final code in supported) {
      test('returns AppLocalizations for locale "$code"', () {
        // Verifies that the switch statement handles every supported locale
        // and returns a concrete (non-null) AppLocalizations instance.
        final loc = lookupAppLocalizations(Locale(code));
        expect(loc, isA<AppLocalizations>());
        // localeName is canonicalised; at minimum it starts with the code.
        expect(loc.localeName, startsWith(code));
      });
    }

    test('throws FlutterError for an unsupported locale', () {
      // Verifies the fallthrough branch at the end of the switch.
      expect(
        () => lookupAppLocalizations(const Locale('xx')),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  // ─── delegate.isSupported ─────────────────────────────────────────────────

  group('AppLocalizations.delegate.isSupported', () {
    const supported = [
      'am',
      'ar',
      'bn',
      'en',
      'es',
      'fa',
      'fr',
      'hi',
      'ja',
      'ne',
      'pt',
      'ru',
      'ur',
      'zh',
    ];

    for (final code in supported) {
      test('returns true for "$code"', () {
        // Verifies every supported language code is accepted.
        expect(delegate.isSupported(Locale(code)), isTrue);
      });
    }

    test('returns false for unsupported code "xx"', () {
      // Verifies that an unknown code is rejected.
      expect(delegate.isSupported(const Locale('xx')), isFalse);
    });

    test('returns false for another unsupported code "de"', () {
      // Edge case: German is not in the supported list.
      expect(delegate.isSupported(const Locale('de')), isFalse);
    });
  });

  // ─── delegate.shouldReload ────────────────────────────────────────────────

  group('AppLocalizations.delegate.shouldReload', () {
    test('always returns false', () {
      // Verifies the no-reload policy: passing the same delegate instance.
      expect(delegate.shouldReload(delegate), isFalse);
    });
  });

  void expectGeneratedLabel(String name, String value) {
    expect(value.trim(), isNotEmpty, reason: '$name must stay non-blank');
  }

  void expectGeneratedLabels(Map<String, String> labels) {
    for (final entry in labels.entries) {
      expectGeneratedLabel(entry.key, entry.value);
    }
  }

  // ─── supportedLocales list ────────────────────────────────────────────────

  group('AppLocalizations.supportedLocales', () {
    test('TC-S4-REG-L10N-001 English and Spanish expose localized shell labels',
        () {
      final english = lookupAppLocalizations(const Locale('en'));
      final spanish = lookupAppLocalizations(const Locale('es'));

      expect(english.menuTitle, 'Menu');
      expect(english.voiceCommands, 'Voice Commands');
      expect(spanish.menuTitle, 'Menú');
      expect(spanish.voiceCommands, 'Comandos de Voz');
      expect(spanish.menuTitle, isNot(english.menuTitle));
    });

    test(
        'TC-S4-REG-L10N-003 English and Spanish expose Team C voice and language labels',
        () {
      // Regression guard for Team C critical generated getters used by the
      // voice-command flow and language picker.
      final english = lookupAppLocalizations(const Locale('en'));
      final spanish = lookupAppLocalizations(const Locale('es'));

      expectGeneratedLabels({
        'en.voiceCommands': english.voiceCommands,
        'en.voicecommand_voiceCommandTitle':
            english.voicecommand_voiceCommandTitle,
        'en.voicecommand_tapMicToStart': english.voicecommand_tapMicToStart,
        'en.voicecommand_wakeWordToStart': english.voicecommand_wakeWordToStart,
        'en.voicecommand_commandNotRecognized':
            english.voicecommand_commandNotRecognized,
        'en.voicecommand_successNotRecognized':
            english.voicecommand_successNotRecognized,
        'en.voicecommand_confirmCommand': english.voicecommand_confirmCommand,
        'en.voicecommand_clarifyCommand': english.voicecommand_clarifyCommand,
        'en.voicecommand_multipleMatchesCommand':
            english.voicecommand_multipleMatchesCommand,
        'en.voicecommand_selectOneOptionCommand':
            english.voicecommand_selectOneOptionCommand,
        'en.voicecommand_confirmButton': english.voicecommand_confirmButton,
        'en.voicecommand_cancelButton': english.voicecommand_cancelButton,
        'en.voicecommand_micDeniedGuidance':
            english.voicecommand_micDeniedGuidance,
        'en.voicecommand_unavailableGuidance':
            english.voicecommand_unavailableGuidance,
        'en.voicecommand_timeoutGuidance': english.voicecommand_timeoutGuidance,
        'en.voicecommand_noSpeechGuidance':
            english.voicecommand_noSpeechGuidance,
        'en.voicecommand_intentNotYetSupported':
            english.voicecommand_intentNotYetSupported,
        'en.mainscreen_voiceCommandsTooltip':
            english.mainscreen_voiceCommandsTooltip,
        'en.languagepicker_English': english.languagepicker_English,
        'en.languagepicker_Spanish': english.languagepicker_Spanish,
        'es.voiceCommands': spanish.voiceCommands,
        'es.voicecommand_voiceCommandTitle':
            spanish.voicecommand_voiceCommandTitle,
        'es.voicecommand_tapMicToStart': spanish.voicecommand_tapMicToStart,
        'es.voicecommand_wakeWordToStart': spanish.voicecommand_wakeWordToStart,
        'es.voicecommand_commandNotRecognized':
            spanish.voicecommand_commandNotRecognized,
        'es.voicecommand_successNotRecognized':
            spanish.voicecommand_successNotRecognized,
        'es.voicecommand_confirmCommand': spanish.voicecommand_confirmCommand,
        'es.voicecommand_clarifyCommand': spanish.voicecommand_clarifyCommand,
        'es.voicecommand_multipleMatchesCommand':
            spanish.voicecommand_multipleMatchesCommand,
        'es.voicecommand_selectOneOptionCommand':
            spanish.voicecommand_selectOneOptionCommand,
        'es.voicecommand_confirmButton': spanish.voicecommand_confirmButton,
        'es.voicecommand_cancelButton': spanish.voicecommand_cancelButton,
        'es.voicecommand_micDeniedGuidance':
            spanish.voicecommand_micDeniedGuidance,
        'es.voicecommand_unavailableGuidance':
            spanish.voicecommand_unavailableGuidance,
        'es.voicecommand_timeoutGuidance': spanish.voicecommand_timeoutGuidance,
        'es.voicecommand_noSpeechGuidance':
            spanish.voicecommand_noSpeechGuidance,
        'es.voicecommand_intentNotYetSupported':
            spanish.voicecommand_intentNotYetSupported,
        'es.mainscreen_voiceCommandsTooltip':
            spanish.mainscreen_voiceCommandsTooltip,
        'es.languagepicker_English': spanish.languagepicker_English,
        'es.languagepicker_Spanish': spanish.languagepicker_Spanish,
      });

      expect(english.voicecommand_confirmButton, 'Confirm');
      expect(english.voicecommand_cancelButton, 'Cancel');
      expect(english.languagepicker_Spanish, 'Español (Spanish)');
      expect(spanish.voicecommand_confirmButton, 'Confirmar');
      expect(spanish.voicecommand_cancelButton, 'Cancelar');
      expect(spanish.languagepicker_Spanish, 'Español');
    });

    test('contains exactly 14 locales', () {
      // Verifies the static list length matches the documented locale count.
      expect(AppLocalizations.supportedLocales.length, 14);
    });

    test('contains the English locale', () {
      // Spot-check: English must be in the supported list.
      expect(
        AppLocalizations.supportedLocales.any((l) => l.languageCode == 'en'),
        isTrue,
      );
    });
  });
}
