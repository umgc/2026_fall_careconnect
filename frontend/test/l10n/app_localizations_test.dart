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
      'am', 'ar', 'bn', 'en', 'es', 'fa', 'fr',
      'hi', 'ja', 'ne', 'pt', 'ru', 'ur', 'zh',
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
      'am', 'ar', 'bn', 'en', 'es', 'fa', 'fr',
      'hi', 'ja', 'ne', 'pt', 'ru', 'ur', 'zh',
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

  // ─── supportedLocales list ────────────────────────────────────────────────

  group('AppLocalizations.supportedLocales', () {
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

  /// Helper: reads all getters from an AppLocalizations instance and returns
  /// a list of their values. If any getter throws, the test will fail.
  List<String> readAllGetters(AppLocalizations loc) {
    return [
      loc.systemDefault,
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
      loc.fallbackUser,
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
    ];
  }

  group('All locale getters produce non-empty strings', () {
    const codes = [
      'am', 'ar', 'bn', 'en', 'es', 'fa', 'fr',
      'hi', 'ja', 'ne', 'pt', 'ru', 'ur', 'zh',
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
