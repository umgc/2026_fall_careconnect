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
      loc.resetpassword_failedSendReset,
      loc.resetpassword_resetPasswordTitle,
      loc.resetpassword_resetInstructions,
      loc.resetpassword_emailTitle,
      loc.resetpassword_missingEmail,
      loc.resetpassword_invalidEmail,
      loc.resetpassword_sendLinkButton,
      loc.authservice_oauthError,
      loc.authservice_jwtTokenMissing,
      loc.authservice_userDataMissing,
      loc.authservice_oauthTimedOut,
      loc.authservice_loginFailedError,
      loc.authservice_emailRegistrationSuccess,
      loc.authservice_emailRegistrationFailed,
      loc.authservice_dataSerialError,
      loc.authservice_caregiverRegistrationSuccessMessage,
      loc.authservice_caregiverRegistrationFailedMessage,
      loc.authservice_emailVerifiedSuccess,
      loc.authservice_emailVerifiedFailed,
      loc.authservice_passwordResetLinkSent,
      loc.authservice_passwordResetLinkFailed,
      loc.authservice_networkError,
      loc.authservice_passwordResetSuccess,
      loc.authservice_passwordResetFailed,
      loc.authservice_passwordResetLinkExpired,
      loc.authservice_passwordResetTokenInvalid,
      loc.authservice_failedToProcessOAuthCall,
      loc.authservice_socketTimeout,
      loc.authservice_authCodeGeneratedSuccess,
      loc.authservice_authInvalidToken,
      loc.authservice_authFailedToGenCode,
      loc.authservice_alexaUnlinkedSuccess,
      loc.authservice_alexaUnlinkedFailed,
      loc.authservice_unexpectedError,
      loc.alexalogin_checkForAlexaOAuthParams,
      loc.alexalogin_currentURI,
      loc.alexalogin_queryParams,
      loc.alexalogin_receivedParamsFromRoute,
      loc.alexalogin_state,
      loc.alexalogin_noAlexaParams,
      loc.alexalogin_alexaOAuthFlowDetected,
      loc.alexalogin_redirectURI,
      loc.alexalogin_standardLoginFlow,
      loc.alexalogin_errorCheckingOAuthParams,
      loc.alexalogin_startLoginFlow,
      loc.alexalogin_missingEmailPassword,
      loc.alexalogin_validationFailEmptyField,
      loc.alexalogin_stepAuthBackend,
      loc.alexalogin_loginSuccessful,
      loc.alexalogin_jwtToken,
      loc.alexalogin_handlingAlexaOAuth,
      loc.alexalogin_loginFailedTryAgain,
      loc.alexalogin_exceptionDuringLogin,
      loc.alexalogin_response,
      loc.alexalogin_authCodeGenerated,
      loc.alexalogin_redirectingToAlexa,
      loc.alexalogin_redirectURL,
      loc.alexalogin_launchingAlexaRedirect,
      loc.alexalogin_failedToGenerateCode,
      loc.alexalogin_exceptionDuringAlexaOAuth,
      loc.alexalogin_failedToLinkAlexaAccount,
      loc.alexalogin_welcomeBack,
      loc.alexalogin_signInToManage,
      loc.alexalogin_emailAddress,
      loc.alexalogin_enterEmailAddress,
      loc.alexalogin_debugLog,
      loc.signup_patient,
      loc.signup_caregiver,
      loc.signup_patientDescription,
      loc.signup_caregiverDescription,
      loc.signup_patientSubtitle,
      loc.signup_caregiverSubtitle,
      loc.signup_accountRoleQuestion,
      loc.signup_accountRoleHint,
      loc.signup_accountRole,
      loc.signup_accountPersonalInfo,
      loc.signup_accountEnterDetails,
      loc.signup_accountFirstName,
      loc.signup_accountFirstNameMissing,
      loc.signup_accountLastName,
      loc.signup_accountLastNameMissing,
      loc.signup_accountDOB,
      loc.signup_accountDOBMissing,
      loc.signup_accountGender,
      loc.signup_accountDOBMissing,
      loc.signup_accountMale,
      loc.signup_accountFemale,
      loc.signup_accountOther,
      loc.signup_accountNoSay,
      loc.signup_accountGenderMissing,
      loc.signup_accountCaregiverType,
      loc.signup_accountProfessional,
      loc.signup_accountFamilyMemb,
      loc.signup_accountFriend,
      loc.signup_accountCaregiverTypeMissing,
      loc.signup_accountContactInfo,
      loc.signup_accountContactInstruction,
      loc.signup_accountEmailRequired,
      loc.signup_accountEmailInvalid,
      loc.signup_accountPhone,
      loc.signup_accountPhoneMissing,
      loc.signup_accountAddress,
      loc.signup_accountAddressLine1,
      loc.signup_accountAddressLine1Hint,
      loc.signup_accountAddressLine1Required,
      loc.signup_accountAddressLine2,
      loc.signup_accountCity,
      loc.signup_accountCityRequired,
      loc.signup_accountState,
      loc.signup_accountStateRequired,
      loc.signup_accountZIP,
      loc.signup_accountZIPRequired,
      loc.signup_accountProfessionalInfo,
      loc.signup_accountLicenseNumber,
      loc.signup_accountLicenseNumberRequired,
      loc.signup_accountIssueState,
      loc.signup_accountIssueStateRequired,
      loc.signup_accountYearXp,
      loc.signup_accountYearXpRequired,
      loc.signup_accountInvalidNumber,
      loc.signup_accountSecuritySetup,
      loc.signup_accountSecuritySetupInstruction,
      loc.signup_accountPasswordRequired,
      loc.signup_accountPasswordShort,
      loc.signup_accountConfirmPassword,
      loc.signup_accountConfirmPasswordRequired,
      loc.signup_accountConfirmPasswordMismatch,
      loc.signup_accountPasReqs,
      loc.signup_accountPasReqs1,
      loc.signup_accountPasReqs2,
      loc.signup_accountPasReqs3,
      loc.signup_accountReviewTitle,
      loc.signup_accountReviewInstruction,
      loc.signup_accountTypeSection,
      loc.signup_accountNameSection,
      loc.signup_accountAgreeTOS,
      loc.signup_accountDateSelect,
      loc.signup_accountSelect,
      loc.signup_accountCreateTitle,
      loc.signup_accountCreateSubtitle,
      loc.signup_accountCompletionPerct,
      loc.signup_accountStep,
      loc.signup_previousButton,
      loc.signup_backLoginButton,
      loc.signup_signUpButton,
      loc.signup_nextButton,
      loc.oauthcallback_initilizeAuth,
      loc.oauthcallback_missingAuthData,
      loc.oauthcallback_savingAuthData,
      loc.oauthcallback_completeSignIn,
      loc.oauthcallback_unknownUserRole,
      loc.oauthcallback_failedToProcessAuth,
      loc.oauthcallback_oauthFailed,
      loc.oauthcallback_accessDenied,
      loc.oauthcallback_invalidRequest,
      loc.oauthcallback_serverError,
      loc.oauthcallback_authError,
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
