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
      loc.roles_Patient,
      loc.roles_Caregiver,
      loc.roles_Admin,
      loc.menupage_patientReportItem,
      loc.menupage_medicationTrackerItem,
      loc.menupage_addPatientItem,
      loc.menupage_settingsItem,
      loc.menupage_mailDigestItem,
      loc.ptfiles_allFilesItem,
      loc.ptfiles_quickUploadItem,
      loc.ptfiles_filtersCate,
      loc.ptfiles_medNotesItem,
      loc.ptfiles_MedRecordItem,
      loc.ptfiles_prescripItem,
      loc.ptfiles_labResItem,
      loc.ptfiles_insuranceItem,
      loc.ptfiles_reprotItem,
      loc.ptfiles_otherDocItem,
      loc.ptfiles_uploadPtFiles,
      loc.ptfiles_uploadFileDescr,
      loc.ptfiles_noFilesUploaded,
      loc.ptfiles_noFilesIn,
      loc.ptfiles_category,
      loc.ptfiles_quickUploadDescrip,
      loc.ptfiles_uploadFilesButton,
      loc.ptfiles_previewButton,
      loc.ptfiles_downloadButton,
      loc.ptfiles_deleteButton,
      loc.ptfiles_failedToLoadImage,
      loc.ptfiles_documentPreview,
      loc.ptfiles_file,
      loc.ptfiles_size,
      loc.ptfiles_descrip,
      loc.ptfiles_downloadViewButton,
      loc.ptfiles_fileDownloadSuccess,
      loc.ptfiles_fileDownloadFailed,
      loc.ptfiles_fileDownloadError,
      loc.ptfiles_deleteFile,
      loc.ptfiles_deleteFileDialog,
      loc.ptfiles_fileDeleteSuccess,
      loc.ptfiles_fileDeleteFailed,
      loc.ptfiles_fileDeleteError,
      loc.ptfiles_today,
      loc.ptfiles_yesterday,
      loc.ptfiles_daysAgo,
      loc.subscriptionplans_basicDescription,
      loc.subscriptionplans_standardDescription,
      loc.subscriptionplans_premiumDescription,
      loc.subscriptionplans_yearly,
      loc.subscriptionplans_monthly,
      loc.subscriptionmodels_yearly,
      loc.subscriptionmodels_monthly,
      loc.subscriptionmodels_cancelOnPeriod,
      loc.subscriptionmodels_active,
      loc.subscriptionmodels_trial,
      loc.subscriptionmodels_cancelled,
      loc.subscriptionmodels_unpaid,
      loc.subscriptionmodels_monthInterval,
      loc.subscriptionmodels_yearInterval,
      loc.nativebilling_purchaseFailed,
      loc.nativebilling_purchaseError,
      loc.nativebilling_completeYourPurchase,
      loc.nativebilling_retry,
      loc.nativebilling_viaAppStore,
      loc.nativebilling_viaGooglePlay,
      loc.nativebilling_processingWeb,
      loc.nativebilling_processingAppStore,
      loc.nativebilling_processingGooglePlay,
      loc.nativebilling_subscribeNow,
      loc.nativebilling_orderSummary,
      loc.nativebilling_taxes,
      loc.nativebilling_total,
      loc.submangement_coreMonitorFeature,
      loc.submangement_emailSupportFeature,
      loc.submangement_unlimitedPtFeature,
      loc.submangement_premMonitorFeature,
      loc.submangement_advAnlFeature,
      loc.submangement_prioritySupportFeature,
      loc.submangement_aiInsightsFeature,
      loc.submangement_tenPtFeature,
      loc.submangement_advMonitorFeature,
      loc.submangement_fullAnlFeature,
      loc.submangement_prioEmailFeature,
      loc.submangement_threePtFeature,
      loc.submangement_basicAnlFeature,
      loc.submangement_failToLoadSub,
      loc.submangement_pleaseTryAgain,
      loc.submangement_errorLoadingSub,
      loc.submangement_confirmPlanChange,
      loc.submangement_changeSubPlan,
      loc.submangement_currentPlan,
      loc.submangement_newPlan,
      loc.submangement_whatHappensNext,
      loc.submangement_failedToCancel,
      loc.submangement_whatNextDescr1,
      loc.submangement_whatNextDescr2,
      loc.submangement_whatNextDescr3,
      loc.submangement_whatNextDescr4,
      loc.submangement_cancelCaps,
      loc.submangement_confirmCaps,
      loc.submangement_confirmFreePlan,
      loc.submangement_selectedFreePlan,
      loc.submangement_cancelSub,
      loc.submangement_warningHeader,
      loc.submangement_warningDescr1,
      loc.submangement_warningDescr2,
      loc.submangement_warningDescr3,
      loc.submangement_warningDescr4,
      loc.submangement_noKeepPlan,
      loc.submangement_yesCancel,
      loc.submangement_finalConfirmation,
      loc.submangement_finalWarning,
      loc.submangement_noGoBack,
      loc.submangement_yesFinal,
      loc.submangement_subCanceledSuccess,
      loc.submangement_subCanceledFailed,
      loc.submangement_subManagement,
      loc.submangement_errorLoadingSubMang,
      loc.submangement_unknownErrorOccur,
      loc.submangement_tryAgain,
      loc.submangement_currentSub,
      loc.submangement_noActiveSub,
      loc.submangement_chooseAPlan,
      loc.submangement_amountPaid,
      loc.submangement_nextBilling,
      loc.submangement_currentPeriod,
      loc.submangement_subWillBeCancelled,
      loc.submangement_availablePlan,
      loc.submangement_noSubPlan,
      loc.submangement_checkBackLater,
      loc.submangement_currentActivePlan,
      loc.submangement_switchToNewPlan,
      loc.submangement_activePlan,
      loc.submangement_inactivePlan,
      loc.submangement_standardPlan,
      loc.submangement_premiumPlan,
      loc.cancelpay_paymentCancel,
      loc.cancelpay_regNotComplete,
      loc.cancelpay_paymentCanceled,
      loc.cancelpay_tryPayAgain,
      loc.cancelpay_returnDash,
      loc.cancelpay_skipGoLogin,
      loc.cancelpay_goHome,
      loc.paysuccess_redirectIn,
      loc.paysuccess_seconds,
      loc.paysuccess_regComplete,
      loc.paysuccess_paymentSuccess,
      loc.paysuccess_thankForPayment,
      loc.paysuccess_sessionId,
      loc.paysuccess_continueLogin,
      loc.paysuccess_returnSubManage,
      loc.paysuccess_continueDash,
      loc.paysuccess_redirectingAuto,
      loc.paysuccess_welcomeTo,
      loc.paysuccess_accountCreated,
      loc.subselection_choosePlan,
      loc.subselection_selectPlan,
      loc.subselection_choosePlanDescr,
      loc.subselection_free,
      loc.subselection_freePlan1,
      loc.subselection_freePlan2,
      loc.subselection_freePlan3,
      loc.subselection_standard,
      loc.subselection_standardPlan1,
      loc.subselection_standardPlan2,
      loc.subselection_standardPlan3,
      loc.subselection_standardPlan4,
      loc.subselection_premium,
      loc.subselection_premiumPlan1,
      loc.subselection_premiumPlan2,
      loc.subselection_premiumPlan3,
      loc.subselection_premiumPlan4,
      loc.subselection_premiumPlan5,
      loc.subselection_continueToPayment,
      loc.subselection_confirmFree,
      loc.subselection_selectedFree,
      loc.subselection_continueToPayment,
      loc.subselection_mostPopular,
      loc.webpay_paymentFailed,
      loc.webpay_transaction,
      loc.webpay_errorLoadingQuote,
      loc.webpay_noQuote,
      loc.webpay_selectPaymentMethod,
      loc.webpay_payApple,
      loc.webpay_payGoogle,
      loc.webpay_taxState,
      loc.webpay_currency,
      loc.billservice_inAppUnavailable,
      loc.billservice_productNotFound,
      loc.billservice_noOfferToken,
      loc.billservice_verifyFailed,
      loc.billservice_paymentProcessFailed,
      loc.filemanage_errorLoadingFiles,
      loc.filemanage_myFiles,
      loc.filemanage_upload,
      loc.filemanage_hiringForms,
      loc.filemanage_searchFiles,
      loc.filemanage_searchByDescr,
      loc.filemanage_filterByCat,
      loc.filemanage_allCats,
      loc.filemanage_medReport,
      loc.filemanage_labResult,
      loc.filemanage_prescription,
      loc.filemanage_clinicNotes,
      loc.filemanage_profilePic,
      loc.filemanage_emgContact,
      loc.filemanage_insurDocument,
      loc.filemanage_aiChatFile,
      loc.filemanage_genDocument,
      loc.filemanage_hlthDataImport,
      loc.filemanage_backupFile,
      loc.filemanage_refreshFiles,
      loc.filemanage_noFilesMatchFilter,
      loc.filemanage_tryAdjustingCriteria,
      loc.filemanage_uploadFirstFile,
      loc.filemanage_downloadFeatureComingSoon,
      loc.filemanage_deleteFeatureComingSoon,
      loc.filemanage_fileUpload,
      loc.filemanage_fileUploadDescr,
      loc.filemanage_fileAnalytics,
      loc.filemanage_totalFiles,
      loc.filemanage_totalSize,
      loc.filemanage_filtersByCat,
      loc.filemanage_downloading,
      loc.filemanage_fileSavedTo,
      loc.filemanage_couldNotAccessStorage,
      loc.filemanage_downloadFailed,
      loc.filemanage_previewFunction,
      loc.filemanage_category,
      loc.filemanage_type,
      loc.filemanage_close,
      loc.filemanage_cannotBeUndone,
      loc.filemanage_deleted,
      loc.filemanage_failedToDelete,
      loc.ptfiles_structEntry,
      loc.filemanage_docComplianceDash,
      loc.filemanage_empApplication,
      loc.filemanage_onboardForm,
      loc.filemanage_backgroundCheck,
      loc.filemanage_cert,
      loc.filemanage_ref,
      loc.filemanage_empContract,
      loc.filemanage_taxForm,
      loc.filemanage_workAuth,
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
