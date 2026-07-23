import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/user_provider.dart';
import '../widgets/theme_toggle_switch.dart';
import '../models/notification_settings.dart';
import '../services/notification_settings_service.dart';
import '../providers/locale_provider.dart';
import '../widgets/language/language_picker.dart';
import '../utils/responsive_utils.dart';

import '../features/telemetry/telemetry.dart';
import '../features/telemetry/telemetry_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  NotificationSettings? _notificationSettings;
  bool _loadingSettings = true;
  // BNS 7 Obesrvability
  bool _telemetryEnabled = true;
  bool _loadingTelemetry = true;
  bool _telemetryDialogShownThisSession = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
    _loadTelemetrySettings();
  }

  Widget _buildLanguageCard(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final localeProvider = context.watch<LocaleProvider>();

    final currentLabel = localeProvider.locale == null
        ? t.systemDefault
        : LanguagePicker.labelFor(localeProvider.locale!, t);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.language,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        title: Text(
          t.language,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          currentLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
        onTap: () {
          Telemetry.event('button_tap', {
            'screen': 'settings',
            'target': 'language_picker',
          });
          LanguagePicker.show(context);
        },
      ),
    );
  }

  Future<void> _loadNotificationSettings() async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.user;

    if (user != null) {
      final settings =
      await NotificationSettingsService.getNotificationSettings(user.id);
      if (!mounted) return;
      setState(() {
        _notificationSettings = settings;
        _loadingSettings = false;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _loadingSettings = false;
      });
    }
  }

  Future<void> _loadTelemetrySettings() async {
    final optedOut = await TelemetrySettings.isOptedOut();

    if (!mounted) return;

    setState(() {
      _telemetryEnabled = !optedOut;
      _loadingTelemetry = false;
    });

    await _maybeShowTelemetryDefaultOnDialog();

    if (!mounted) return;
    await Telemetry.event('screen_view', {'screen': 'settings'});
  }

  Future<void> _maybeShowTelemetryDefaultOnDialog() async {
    if (!mounted) return;
    if (_telemetryDialogShownThisSession) return;
    if (!_telemetryEnabled) return;

    final seen = await TelemetrySettings.hasSeenDialog();
    if (!mounted) return;
    if (seen) return;

    setState(() => _telemetryDialogShownThisSession = true);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(AppLocalizations.of(ctx)?.settings_telemetryDefaultDialogTitle ?? 'Telemetry is enabled'),
          content: Text(
            AppLocalizations.of(ctx)?.settings_telemetryDefaultDialogDescription ?? 'CareConnect collects anonymous diagnostics and performance metrics by default to help improve reliability.\nYou can opt out at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(AppLocalizations.of(ctx)?.settings_telemetryDefaultDialogOptOut ?? 'Opt out'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(AppLocalizations.of(ctx)?.settings_telemetryDefaultDialogKeepEnabled ?? 'Keep enabled'),
            ),
          ],
        );
      },
    );

    await TelemetrySettings.setHasSeenDialog(true);

    if (result == false) {
      await TelemetrySettings.setOptedOut(true);

      if (!mounted) return;
      setState(() => _telemetryEnabled = false);
    } else if (result == true) {
      await TelemetrySettings.setOptedOut(false);

      if (!mounted) return;
      setState(() => _telemetryEnabled = true);
    }
  }

  Future<void> _updateNotificationSetting(String setting, bool value) async {
    if (_notificationSettings == null) return;

    NotificationSettings updatedSettings;
    switch (setting) {
      case 'gamification':
        updatedSettings = _notificationSettings!.copyWith(gamification: value);
        break;
      case 'emergency':
        updatedSettings = _notificationSettings!.copyWith(emergency: value);
        break;
      case 'videoCall':
        updatedSettings = _notificationSettings!.copyWith(videoCall: value);
        break;
      case 'audioCall':
        updatedSettings = _notificationSettings!.copyWith(audioCall: value);
        break;
      case 'sms':
        updatedSettings = _notificationSettings!.copyWith(sms: value);
        break;
      case 'significantVitals':
        updatedSettings = _notificationSettings!.copyWith(
          significantVitals: value,
        );
        break;
      default:
        return;
    }

    final saved = await NotificationSettingsService.saveNotificationSettings(
      updatedSettings,
    );
    if (!mounted) return;

    if (saved != null) {
      setState(() {
        _notificationSettings = saved;
      });

      await Telemetry.event('button_tap', {
        'screen': 'settings',
        'target': 'notification_toggle',
        'setting': setting,
        'enabled': value,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ ${AppLocalizations.of(context)!.settingsSnackUpdated}',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '❌ ${AppLocalizations.of(context)!.settingsSnackUpdateFailed}',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<bool> _confirmOptOut() async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)?.settings_telemetryOptOutDialogTitle ?? 'Opt out of telemetry?'),
        content: Text(
          AppLocalizations.of(ctx)?.settings_telemetryOptOutDialogDescription ?? 'If you opt out, CareConnect will stop collecting anonymous diagnostics and performance metrics.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx)?.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx)?.settings_telemetryDefaultDialogOptOut ?? 'Opt out'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Future<bool> _confirmOptIn() async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)?.settings_telemetryOptInDialogTitle ?? 'Enable telemetry?'),
        content: Text(
          AppLocalizations.of(ctx)?.settings_telemetryOptInDialogDescription ?? 'This will allow CareConnect to collect anonymous diagnostics and performance metrics to improve reliability.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppLocalizations.of(ctx)?.cancel ?? 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppLocalizations.of(ctx)?.settings_telemetryOptInDialogEnable ?? 'Enable'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required VoidCallback onTap,
        Color? textColor,
        Color? iconColor,
      }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildNotificationToggleCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required bool value,
        required Function(bool) onChanged,
        Color? iconColor,
      }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildToggleCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required bool value,
        required ValueChanged<bool> onChanged,
        Color? iconColor,
        bool loading = false,
      }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: iconColor ?? Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: loading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
            : Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildThemeCard(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.brightness_6,
          color: Theme.of(context).colorScheme.primary,
          size: 24,
        ),
        title: Text(
          t.darkMode,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          t.settingsToggleThemeDesc,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const ThemeToggleSwitch(showIcon: false, showLabel: false),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settingsClearCache),
        content: Text(t.settingsClearCacheDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ ${t.settingsCacheCleared}'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
              );
            },
            child: Text(t.settingsClearCache),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.settingsSignOut),
        content: Text(t.settingsSignOutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(
              t.settingsSignOut,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t.settingsDeleteAccount,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        content: Text(t.settingsDeleteAccountDesc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(t.settingsDeleteAccountRequested),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(
              t.settingsDeleteAccountAction,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.user;

    final shouldHideSubscription =
        user != null &&
            (user.role.toLowerCase() == 'patient' ||
                user.role.toLowerCase() == 'family member');

    return Scaffold(
      appBar: AppBar(
        title: Text(t.settings), // use existing "Settings" key
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        // Center and cap the content width so cards don't stretch edge-to-edge
        // on tablet / mobile-landscape widths; keep a comfortable margin on
        // narrow (mobile-portrait) screens.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.isMobile ? 16.0 : 24.0,
              ),
              child: ListView(
                children: [
                  const SizedBox(height: 16),
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          child:
                          (user != null &&
                              user.name != null &&
                              user.name!.isNotEmpty)
                              ? Text(
                            user.name![0].toUpperCase(),
                            style: TextStyle(
                              fontSize: 32,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                              : Icon(
                            Icons.person,
                            size: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (user != null &&
                              user.name != null &&
                              user.name!.isNotEmpty)
                              ? user.name!
                              : t.fallbackUser,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          (user != null && user.email.isNotEmpty)
                              ? user.email
                              : '',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),

                  // Appearance
                  _buildSectionHeader(context, t.settingsAppearance),
                  _buildThemeCard(context),
                  _buildLanguageCard(context),
                  const SizedBox(height: 24),

                  // Notifications
                  _buildSectionHeader(context, t.settingsNotifications),
                  if (_loadingSettings)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        title: Text(t.settingsLoadingNotificationSettings),
                      ),
                    )
                  else if (_notificationSettings != null) ...[
                    _buildNotificationToggleCard(
                      context,
                      icon: Icons.emergency,
                      title: t.settingsNotifEmergency,
                      subtitle: t.settingsNotifEmergencyDesc,
                      value: _notificationSettings!.emergency,
                      onChanged: (value) =>
                          _updateNotificationSetting('emergency', value),
                      iconColor: Theme.of(context).colorScheme.error,
                    ),
                    _buildNotificationToggleCard(
                      context,
                      icon: Icons.video_call,
                      title: t.settingsNotifVideoCall,
                      subtitle: t.settingsNotifVideoCallDesc,
                      value: _notificationSettings!.videoCall,
                      onChanged: (value) =>
                          _updateNotificationSetting('videoCall', value),
                    ),
                    _buildNotificationToggleCard(
                      context,
                      icon: Icons.call,
                      title: t.settingsNotifAudioCall,
                      subtitle: t.settingsNotifAudioCallDesc,
                      value: _notificationSettings!.audioCall,
                      onChanged: (value) =>
                          _updateNotificationSetting('audioCall', value),
                    ),
                    _buildNotificationToggleCard(
                      context,
                      icon: Icons.favorite,
                      title: t.settingsNotifSignificantVitals,
                      subtitle: t.settingsNotifSignificantVitalsDesc,
                      value: _notificationSettings!.significantVitals,
                      onChanged: (value) => _updateNotificationSetting(
                        'significantVitals',
                        value,
                      ),
                    ),
                    _buildNotificationToggleCard(
                      context,
                      icon: Icons.sms,
                      title: t.settingsNotifSMS,
                      subtitle: t.settingsNotifSMSDesc,
                      value: _notificationSettings!.sms,
                      onChanged: (value) =>
                          _updateNotificationSetting('sms', value),
                    ),
                    _buildNotificationToggleCard(
                      context,
                      icon: Icons.stars,
                      title: t.settingsNotifGamification,
                      subtitle: t.settingsNotifGamificationDesc,
                      value: _notificationSettings!.gamification,
                      onChanged: (value) =>
                          _updateNotificationSetting('gamification', value),
                    ),
                  ] else
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(t.settingsUnableToLoadNotificationSettings),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _loadNotificationSettings,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Privacy
                  _buildSectionHeader(context, t.settings_privacySectionHeader),
                  _buildToggleCard(
                    context,
                    icon: Icons.privacy_tip,
                    title: t.settings_privacySectionTelemetrySetting,
                    subtitle: t.settings_privacySectionTelemetrySettingDescription,
                    value: _telemetryEnabled,
                    loading: _loadingTelemetry,
                    onChanged: (enabled) async {
                      if (_loadingTelemetry) return;

                      final messenger = ScaffoldMessenger.of(context);
                      final errorColor = Theme.of(context).colorScheme.error;

                      final allowed = enabled
                          ? await _confirmOptIn()
                          : await _confirmOptOut();
                      if (!allowed) return;

                      setState(() => _loadingTelemetry = true);

                      try {
                        await TelemetrySettings.setOptedOut(!enabled);

                        if (!mounted) return;
                        setState(() {
                          _telemetryEnabled = enabled;
                          _loadingTelemetry = false;
                        });

                        if (_telemetryEnabled) {
                          await Telemetry.event('privacy_telemetry_toggle', {
                            'enabled': enabled,
                          });
                        }
                      } catch (_) {
                        if (!mounted) return;
                        setState(() => _loadingTelemetry = false);

                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(t.settings_telemetryFailedToUpdate),
                            backgroundColor: errorColor,
                          ),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  // Subscription (hide for patient/family member)
                  if (!shouldHideSubscription) ...[
                    _buildSectionHeader(context, t.settingsSubscription),
                    _buildSettingsCard(
                      context,
                      icon: Icons.subscriptions,
                      title: t.settingsManageSubscription,
                      subtitle: t.settingsManageSubscriptionDesc,
                      onTap: () {
                        Telemetry.event('button_tap', {
                          'screen': 'settings',
                          'target': 'manage_subscription',
                          'route': '/select-package',
                        });
                        context.push('/select-package');
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Notetaker
                  _buildSectionHeader(context, t.settingsNotetakerAssistant),
                  _buildSettingsCard(
                    context,
                    icon: Icons.edit_note,
                    title: t.settingsNotetakerConfiguration,
                    subtitle: t.settingsNotetakerConfigurationDesc,
                    onTap: () {
                      Telemetry.event('button_tap', {
                        'screen': 'settings',
                        'target': 'notetaker_configuration',
                        'route': '/notetaker-configuration',
                      });
                      context.push('/notetaker-configuration');
                    },
                  ),
                  const SizedBox(height: 24),

                  // General
                  _buildSectionHeader(context, t.settingsGeneral),

                  // User-Controlled Persistence Toggle (BNS 5)
                  _buildToggleCard(
                    context,
                    icon: Icons.cloud_off,
                    title: t.settings_generalSectionOfflinePersistenceSetting,
                    subtitle: userProvider.offlineModeEnabled
                        ? t.settings_generalSectionOfflinePersistenceSettingEnabled
                        : t.settings_generalSectionOfflinePersistenceSettingDisabled,
                    value: userProvider.offlineModeEnabled,
                    onChanged: (enabled) async {
                      userProvider.setOfflineMode(enabled);
                      // BNS 7: Privacy-Preserving Observability and Telemetry.
                      if (_telemetryEnabled) {
                        await Telemetry.event('offline_toggled', {
                          'enabled': enabled,
                        });
                      }
                    },
                  ),

                  _buildSettingsCard(
                    context,
                    icon: Icons.cleaning_services,
                    title: t.settingsClearCache,
                    subtitle: t.settingsClearCacheShortDesc,
                    onTap: () {
                      Telemetry.event('button_tap', {
                        'screen': 'settings',
                        'target': 'clear_cache',
                      });
                      _showClearCacheDialog(context);
                    },
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.logout,
                    title: t.settingsSignOut,
                    subtitle: t.settingsSignOutDesc,
                    onTap: () {
                      Telemetry.event('button_tap', {
                        'screen': 'settings',
                        'target': 'sign_out',
                      });
                      _showSignOutDialog(context);
                    },
                    textColor: Theme.of(context).colorScheme.error,
                    iconColor: Theme.of(context).colorScheme.error,
                  ),
                  _buildSettingsCard(
                    context,
                    icon: Icons.delete_forever,
                    title: t.settingsDeleteAccount,
                    subtitle: t.settingsDeleteAccountShortDesc,
                    onTap: () {
                      Telemetry.event('button_tap', {
                        'screen': 'settings',
                        'target': 'delete_account',
                      });
                      _showDeleteAccountDialog(context);
                    },
                    textColor: Theme.of(context).colorScheme.error,
                    iconColor: Theme.of(context).colorScheme.error,
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
