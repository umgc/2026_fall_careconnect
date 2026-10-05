import 'package:care_connect_app/features/fall_alert/pages/skeleton_playback_widget.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fall_alert.dart';

class AlertDetailsPage extends StatelessWidget {
  static const routeName = '/alert-details';

  final FallAlert alert;

  const AlertDetailsPage({
    super.key,
    required this.alert,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = AppLocalizations.of(context)!;

    final now = DateTime.now().toUtc();
    final timeAgo = _formatTimeAgo(
      now.difference(alert.detectedAtUtc),
      t,
    );
    final bool hasPlayback = alert.playbackData != null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? cs.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? cs.onSurface,
        title: Text(t.fallAlertTitle),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: cs.error,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t.fallAlertPatientMayNeedHelp,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Patient card
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: cs.secondaryContainer,
                    child: Text(
                      _initials(alert.patientName),
                      style: theme.textTheme.titleMedium!.copyWith(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.patientName,
                          style: theme.textTheme.titleMedium!.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.videocam_outlined,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                t.fallAlertCamera,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 16,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                timeAgo,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _openPatientDetails(context),
                    icon: const Icon(
                      Icons.person_outline,
                      size: 18,
                    ),
                    label: Text(t.fallAlertViewDetails),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (now.difference(alert.detectedAtUtc) >
                const Duration(minutes: 2))
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  t.fallAlertNoResponseFromPatient,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: cs.onError,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            if (now.difference(alert.detectedAtUtc) >
                const Duration(minutes: 2))
              const SizedBox(height: 16),

            if (hasPlayback) ...[
              _SectionTitle(t.fallAlertPlayback),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.10),
                    ),
                  ),
                  child: SkeletonPlaybackWidget(
                    sampleResponse: alert.playbackData!,
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ] else ...[
              _ActionButton(
                icon: Icons.videocam_off,
                label: t.fallAlertPlaybackUnavailable,
                onPressed: null,
                background: Colors.transparent,
                border: cs.primary,
                textColor: cs.primary,
              ),
              const SizedBox(height: 10),
            ],

            _ActionButton(
              icon: Icons.call,
              label: t.fallAlertCallPatient,
              onPressed: () => _callPatient(context),
              background: cs.primary,
              textColor: cs.onPrimary,
            ),
            const SizedBox(height: 10),

            _ActionButton(
              icon: Icons.message_outlined,
              label: t.fallAlertSendMessage,
              onPressed: () => _messagePatient(context),
              background: cs.surface,
              border: theme.dividerColor.withValues(alpha: 0.24),
              textColor: cs.onSurface,
            ),
            const SizedBox(height: 10),

            _ActionButton(
              icon: Icons.emergency_share_rounded,
              label: t.fallAlertContactEmergencyServices,
              onPressed: () => _alertEmergency(context),
              background: cs.error,
              textColor: cs.onError,
            ),
            const SizedBox(height: 18),

            // Details
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.10),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionTitle(t.fallAlertDetails),
                  _MetaRow(
                    t.fallAlertDetectedAt,
                    alert.detectedAtUtc.toLocal().toString(),
                  ),
                  _MetaRow(
                    t.fallAlertSource,
                    alert.source,
                  ),
                  _MetaRow(
                    t.fallAlertPatientPhone,
                    alert.patientPhone ?? t.fallAlertNotAvailable,
                  ),
                  _MetaRow(
                    t.fallAlertPlayback,
                    hasPlayback
                        ? t.fallAlertAvailable
                        : t.fallAlertNotAvailable,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _callPatient(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final phone = alert.patientPhone;

    if (phone == null || phone.isEmpty) {
      _toast(context, t.fallAlertNoPhoneNumberAvailable);
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: phone,
    );

    final launched = await launchUrl(uri);

    if (!context.mounted) return;

    if (!launched) {
      _toast(
        context,
        t.fallAlertCallFailedToStart,
      );
    }
  }

  Future<void> _messagePatient(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final phone = alert.patientPhone;
    final message = t.fallAlertSmsMessage;

    if (phone == null || phone.isEmpty) {
      _toast(context, t.fallAlertNoPhoneNumberAvailable);
      return;
    }

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {
        'body': message,
      },
    );

    final launched = await launchUrl(uri);

    if (!context.mounted) return;

    if (!launched) {
      _toast(
        context,
        t.fallAlertMessageFailedToStart,
      );
    }
  }

  Future<void> _openPatientDetails(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    final id = alert.patientId;

    if (id.isEmpty) {
      _toast(
        context,
        t.fallAlertPatientIdNotAvailable,
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PatientDetailsPage(
          patientId: id,
        ),
        settings: const RouteSettings(
          name: '/patient-details',
        ),
      ),
    );
  }

  Future<void> _alertEmergency(BuildContext context) async {
    final t = AppLocalizations.of(context)!;
    const emergencyNumber = '911';

    final contactName =
        alert.emergencyContactName ?? t.fallAlertEmergencyContact;

    final contactPhone = alert.emergencyContactPhone;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    t.fallAlertEmergencyActions,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    t.fallAlertChooseHowToEscalate,
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                _EmergencyTile(
                  icon: Icons.local_phone_rounded,
                  label: t.fallAlertCall911,
                  subtitle: t.fallAlertConnectLocalEmergencyServices,
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    final uri = Uri(
                      scheme: 'tel',
                      path: emergencyNumber,
                    );

                    final launched = await launchUrl(uri);

                    if (!context.mounted) return;

                    if (!launched) {
                      _toast(
                        context,
                        t.fallAlertCouldNotStartCall911,
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
                _EmergencyTile(
                  icon: Icons.contact_phone_rounded,
                  label: t.fallAlertCallContact(contactName),
                  subtitle: contactPhone ?? t.fallAlertNoPhoneOnFile,
                  enabled: contactPhone != null && contactPhone.isNotEmpty,
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    final uri = Uri(
                      scheme: 'tel',
                      path: contactPhone,
                    );

                    final launched = await launchUrl(uri);

                    if (!context.mounted) return;

                    if (!launched) {
                      _toast(
                        context,
                        t.fallAlertCouldNotStartCallContact(
                          contactName,
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Divider(
                  color: Colors.white12,
                ),
                const SizedBox(height: 8),
                Text(
                  t.fallAlertEmergencyInstruction,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toast(
    BuildContext context,
    String msg,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
      ),
    );
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }

    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  static String _formatTimeAgo(
    Duration d,
    AppLocalizations t,
  ) {
    if (d.inSeconds < 60) {
      return t.fallAlertSecondsAgo(d.inSeconds);
    }

    if (d.inMinutes < 60) {
      return t.fallAlertMinutesAgo(d.inMinutes);
    }

    if (d.inHours < 24) {
      return t.fallAlertHoursAgo(d.inHours);
    }

    return t.fallAlertDaysAgo(d.inDays);
  }
}

class _EmergencyTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool enabled;

  const _EmergencyTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      enabled: enabled,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tileColor: cs.surface,
      leading: CircleAvatar(
        backgroundColor:
            enabled ? cs.secondaryContainer : cs.surfaceContainerHighest,
        child: Icon(
          icon,
          color: cs.onSecondaryContainer,
        ),
      ),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      onTap: enabled ? onTap : null,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color? border;
  final Color? textColor;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.background,
    this.border,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveText = textColor ?? Colors.white;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: background,
          foregroundColor: effectiveText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: border != null ? BorderSide(color: border!) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: effectiveText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: effectiveText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(
    this.label,
    this.value,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
