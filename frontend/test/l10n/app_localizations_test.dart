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

  // ─── Full getter coverage for each locale ─────────────────────────────────
  // Exercises every translated getter on every locale subclass so that the
  // per-locale files (app_localizations_am.dart … app_localizations_zh.dart)
  // get line coverage.

  /// Helper: reads all current generated getters from an AppLocalizations
  /// instance. If a generated getter is removed or stale, this test fails at
  /// compile time instead of silently losing coverage.
  List<String> readAllGetters(AppLocalizations loc) {
    return [
      loc.menuTitle,
      loc.yourShortcuts,
      loc.preferences,
      loc.darkMode,
      loc.language,
      loc.logout,
      loc.tools,
      loc.customize,
      loc.search,
      loc.invoiceAssistant,
      loc.evv,
      loc.voiceCommands,
      loc.calendarAssistant,
      loc.medicationManagement,
      loc.socialFeed,
      loc.gamification,
      loc.wearables,
      loc.fileManagement,
      loc.addPatient,
      loc.settings,
      loc.fallDetection,
      loc.informedDelivery,
      loc.smartDevices,
      loc.pleaseLogIn,
      loc.loginRequiredMessage,
      loc.login,
      loc.customizeShortcuts,
      loc.cancel,
      loc.save,
      loc.systemDefault,
      loc.fallbackUser,
      loc.roles_Patient,
      loc.roles_Caregiver,
      loc.roles_Admin,
      loc.dashboard,
      loc.shortcut_dashboard,
      loc.shortcut_invoices,
      loc.shortcut_calendar,
      loc.shortcut_feed,
      loc.shortcut_meds,
      loc.shortcut_evv,
      loc.shortcut_wearables,
      loc.shortcut_files,
      loc.shortcut_gamification,
      loc.navHome,
      loc.navSymptoms,
      loc.navHealth,
      loc.navMessages,
      loc.navMenu,
      loc.navPatientList,
      loc.navAnalytics,
      loc.navMore,
      loc.notetakerAssistant,
      loc.settingsTitle,
      loc.settingsAppearance,
      loc.settingsNotifications,
      loc.settingsLoadingNotificationSettings,
      loc.settingsUnableToLoadNotificationSettings,
      loc.settingsRefresh,
      loc.settingsDarkMode,
      loc.settingsToggleThemeDesc,
      loc.settingsNotifEmergency,
      loc.settingsNotifEmergencyDesc,
      loc.settingsNotifVideoCall,
      loc.settingsNotifVideoCallDesc,
      loc.settingsNotifAudioCall,
      loc.settingsNotifAudioCallDesc,
      loc.settingsNotifSignificantVitals,
      loc.settingsNotifSignificantVitalsDesc,
      loc.settingsNotifSMS,
      loc.settingsNotifSMSDesc,
      loc.settingsNotifGamification,
      loc.settingsNotifGamificationDesc,
      loc.settingsSnackUpdated,
      loc.settingsSnackUpdateFailed,
      loc.settingsCacheCleared,
      loc.settingsAIAssistant,
      loc.settingsAIConfiguration,
      loc.settingsAIConfigurationDesc,
      loc.settingsSubscription,
      loc.settingsManageSubscription,
      loc.settingsManageSubscriptionDesc,
      loc.settingsNotetakerAssistant,
      loc.settingsNotetakerConfiguration,
      loc.settingsNotetakerConfigurationDesc,
      loc.settingsGeneral,
      loc.settingsClearCache,
      loc.settingsClearCacheShortDesc,
      loc.settingsClearCacheDesc,
      loc.settingsSignOut,
      loc.settingsSignOutDesc,
      loc.settingsSignOutConfirmMessage,
      loc.settingsDeleteAccount,
      loc.settingsDeleteAccountShortDesc,
      loc.settingsDeleteAccountDesc,
      loc.settingsDeleteAccountRequested,
      loc.settingsDeleteAccountAction,
      loc.settings_telemetryDefaultDialogTitle,
      loc.settings_telemetryDefaultDialogDescription,
      loc.settings_telemetryDefaultDialogKeepEnabled,
      loc.settings_telemetryDefaultDialogOptOut,
      loc.settings_telemetryOptOutDialogTitle,
      loc.settings_telemetryOptOutDialogDescription,
      loc.settings_telemetryOptInDialogTitle,
      loc.settings_telemetryOptInDialogDescription,
      loc.settings_telemetryOptInDialogEnable,
      loc.settings_privacySectionHeader,
      loc.settings_privacySectionTelemetrySetting,
      loc.settings_privacySectionTelemetrySettingDescription,
      loc.settings_telemetryFailedToUpdate,
      loc.settings_generalSectionOfflinePersistenceSetting,
      loc.settings_generalSectionOfflinePersistenceSettingEnabled,
      loc.settings_generalSectionOfflinePersistenceSettingDisabled,
      loc.welcomeInitializingHealthcare,
      loc.welcomeReadyToConnect,
      loc.welcomeBackendNotHealthyWarning,
      loc.welcomeContinue,
      loc.welcomeComplianceBadgeHipaa,
      loc.welcomeComplianceBadgeWcag,
      loc.welcomeComplianceBadgeSecure,
      loc.welcome_subtitle,
      loc.welcome_description,
      loc.welcome_tagline,
      loc.login_tagline,
      loc.login_signInTitle,
      loc.login_signInSubtitle,
      loc.login_usernameLabel,
      loc.login_usernameHint,
      loc.login_passwordLabel,
      loc.login_passwordHint,
      loc.login_forgotPassword,
      loc.login_signInCta,
      loc.login_noAccountPrompt,
      loc.login_createAccountCta,
      loc.login_badgeSecure,
      loc.login_badgeHipaa,
      loc.login_badgeAccessible,
      loc.login_e2eEncrypted,
      loc.login_wcagAACompliant,
      loc.voicecommand_wakeWordError,
      loc.voicecommand_voiceCommandsUnavailable,
      loc.voicecommand_micPermissionsDenied,
      loc.voicecommand_commandNotRecognized,
      loc.voicecommand_voiceTimedOut,
      loc.voicecommand_noSpeechDetected,
      loc.voicecommand_voiceCommandTitle,
      loc.voicecommand_tapMicToStart,
      loc.voicecommand_wakeWordToStart,
      loc.voicecommand_listeningState,
      loc.voicecommand_processingState,
      loc.voicecommand_phaseLabelReady,
      loc.voicecommand_phaseLabelStatus,
      loc.voicecommand_phaseLabelRecognized,
      loc.voicecommand_phaseLabelCapture,
      loc.voicecommand_phaseLabelNotRecognized,
      loc.voicecommand_phaseLabelError,
      loc.voicecommand_speechCaptured,
      loc.voicecommand_successRecognized,
      loc.voicecommand_successOpen,
      loc.voicecommand_commandLabelHome,
      loc.voicecommand_commandLabelCalendar,
      loc.voicecommand_commandLabelTracker,
      loc.voicecommand_successNotRecognized,
      loc.voicecommand_statusAreaHeard,
      loc.voicecommand_confirmCommand,
      loc.voicecommand_clarifyCommand,
      loc.voicecommand_multipleMatchesCommand,
      loc.voicecommand_selectOneOptionCommand,
      loc.voicecommand_onConfirmedCommand,
      loc.voicecommand_onConfirmedCommandNavigate,
      loc.voicecommand_onClarifyCommand,
      loc.voicecommand_onClarifyCommandConfirm,
      loc.voicecommand_confirmButton,
      loc.voicecommand_cancelButton,
      loc.voicecommand_micDeniedGuidance,
      loc.voicecommand_unavailableGuidance,
      loc.voicecommand_timeoutGuidance,
      loc.voicecommand_noSpeechGuidance,
      loc.voicecommand_intentNotYetSupported,
      loc.mainscreen_voiceCommandsTooltip,
      loc.languagepicker_English,
      loc.languagepicker_Spanish,
      loc.languagepicker_Urdu,
      loc.languagepicker_Arabic,
      loc.languagepicker_French,
      loc.languagepicker_Amharic,
      loc.languagepicker_Nepali,
      loc.languagepicker_Hindi,
      loc.languagepicker_Farsi,
      loc.languagepicker_MandarinChinese,
      loc.languagepicker_Portuguese,
      loc.languagepicker_Bengali,
      loc.languagepicker_Russian,
      loc.languagepicker_Japanese,
      loc.menupage_patientReportItem,
      loc.menupage_medicationTrackerItem,
      loc.menupage_addPatientItem,
      loc.menupage_settingsItem,
      loc.menupage_mailDigestItem,
    ];
  }

  group('All locale getters produce non-empty strings', () {
    const codes = [
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

    for (final code in codes) {
      test('locale "$code" — all getters return non-empty strings', () {
        final loc = lookupAppLocalizations(Locale(code));
        final values = readAllGetters(loc);
        for (int i = 0; i < values.length; i++) {
          expect(values[i], isNotEmpty,
              reason: 'Getter #$i returned empty for locale $code');
        }
      });
    }
  });
}
