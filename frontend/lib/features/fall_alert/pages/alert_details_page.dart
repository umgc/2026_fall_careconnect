import 'package:care_connect_app/features/fall_alert/pages/skeleton_playback_widget.dart';
import 'package:care_connect_app/features/health/caregiver-patient-list/page/patient_details_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/fall_alert.dart';

class AlertDetailsPage extends StatelessWidget {
  static const routeName = '/alert-details';
  final FallAlert alert;

  const AlertDetailsPage({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final now = DateTime.now().toUtc();
    final timeAgo = _formatTimeAgo(now.difference(alert.detectedAtUtc));
    final bool hasPlayback = alert.playbackData != null;

    return Scaffold(
      // was const Color(0xFF0F172A)
      backgroundColor: cs.surface,
      appBar: AppBar(
        // was const Color(0xFF111827)
        backgroundColor: theme.appBarTheme.backgroundColor ?? cs.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? cs.onSurface,
        title: const Text('Fall Alert'),
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
                border: Border.all(color: theme.dividerColor.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: cs.error, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Patient may need help.',
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
                border: Border.all(color: theme.dividerColor.withOpacity(0.10)),
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
                        Text(alert.patientName,
                            style: theme.textTheme.titleMedium!
                                .copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.videocam_outlined,
                                size: 16, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'camera',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 16, color: cs.onSurfaceVariant),
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
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('View Details'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (now.difference(alert.detectedAtUtc) >
                const Duration(minutes: 2))
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('No response from patient',
                    style: theme.textTheme.bodyMedium!.copyWith(
                        color: cs.onError, fontWeight: FontWeight.w600)),
              ),
            if (now.difference(alert.detectedAtUtc) >
                const Duration(minutes: 2))
              const SizedBox(height: 16),

            if (hasPlayback) ...[
              const _SectionTitle('Fall Playback'),
              const SizedBox(height: 8),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: theme.dividerColor.withOpacity(0.10)),
                  ),
                  child: SkeletonPlaybackWidget(
                      sampleResponse: alert.playbackData!),
                ),
              ),
              const SizedBox(height: 18),
            ] else ...[
              _ActionButton(
                icon: Icons.videocam_off,
                label: 'Playback Unavailable',
                onPressed: null,
                background: Colors.transparent,
                border: cs.primary,
                textColor: cs.primary,
              ),
              const SizedBox(height: 10),
            ],

            _ActionButton(
              icon: Icons.call,
              label: 'Call Patient',
              onPressed: () => _callPatient(context),
              background: cs.primary,
              textColor: cs.onPrimary,
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.message_outlined,
              label: 'Send Message',
              onPressed: () => _messagePatient(context),
              background: cs.surface,
              border: theme.dividerColor.withOpacity(0.24),
              textColor: cs.onSurface,
            ),
            const SizedBox(height: 10),
            _ActionButton(
              icon: Icons.emergency_share_rounded,
              label: 'Contact Emergency Services',
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
                border: Border.all(color: theme.dividerColor.withOpacity(0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Details'),
                  _MetaRow(
                      'Detected at', alert.detectedAtUtc.toLocal().toString()),
                  _MetaRow('Source', alert.source),
                  _MetaRow(
                      'Patient phone', alert.patientPhone ?? 'Not available'),
                  _MetaRow(
                      'Playback', hasPlayback ? 'Available' : 'Not available'),
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
    final phone = alert.patientPhone;
    if (phone == null || phone.isEmpty) {
      _toast(context, 'No phone number available');
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      _toast(context, 'Call failed to start');
    }
  }

  Future<void> _messagePatient(BuildContext context) async {
    final phone = alert.patientPhone;
    final message =
        'I got an alert that you may have fallen. Are you okay? Please reply or call me if you need help.';
    if (phone == null || phone.isEmpty) {
      _toast(context, 'No phone number available');
      return;
    }
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    if (!await launchUrl(uri)) {
      _toast(context, 'Message failed to start');
    }
  }

  Future<void> _openPatientDetails(BuildContext context) async {
    final id = alert.patientId;
    if (id.isEmpty) {
      _toast(context, 'Patient ID not available');
      return;
    }

    // A caregiver gets the caregiver page, Medicare tab included, as from the
    // patient list (DEF-MCR-33). No signed-in user: the patient view.
    var isCaregiver = false;
    try {
      isCaregiver =
          Provider.of<UserProvider>(context, listen: false).isCaregiver;
    } on ProviderNotFoundException {
      isCaregiver = false;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PatientDetailsPage(patientId: id, isCaregiver: isCaregiver),
        settings: const RouteSettings(name: '/patient-details'),
      ),
    );
  }

  Future<void> _alertEmergency(BuildContext context) async {
    final emergencyNumber = '911'; // consider making this region-aware
    final contactName = alert.emergencyContactName ?? 'Emergency Contact';
    final contactPhone = alert.emergencyContactPhone;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Emergency actions',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Choose how you want to escalate',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 4),
                _EmergencyTile(
                  icon: Icons.local_phone_rounded,
                  label: 'Call 911',
                  subtitle: 'Connect to local emergency services',
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri(scheme: 'tel', path: emergencyNumber);
                    if (!await launchUrl(uri)) {
                      _toast(context, 'Could not start call to 911');
                    }
                  },
                ),
                const SizedBox(height: 8),
                _EmergencyTile(
                  icon: Icons.contact_phone_rounded,
                  label: 'Call $contactName',
                  subtitle: contactPhone ?? 'No phone on file',
                  enabled: contactPhone != null && contactPhone.isNotEmpty,
                  onTap: () async {
                    Navigator.pop(context);
                    final uri = Uri(scheme: 'tel', path: contactPhone);
                    if (!await launchUrl(uri)) {
                      _toast(context, 'Could not start call to $contactName');
                    }
                  },
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                const Text(
                  'If you cannot reach the patient, contact emergency services immediately.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --- Helpers (Unchanged) ---

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }

  static String _formatTimeAgo(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// --- All helper widgets below are unchanged ---

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: cs.surface,
      leading: CircleAvatar(
        backgroundColor:
            enabled ? cs.secondaryContainer : cs.surfaceContainerHighest,
        child: Icon(icon, color: cs.onSecondaryContainer),
      ),
      title: Text(label,
          style: Theme.of(context)
              .textTheme
              .bodyLarge!
              .copyWith(fontWeight: FontWeight.w600)),
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
  final IconData? trailing = null;

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
            Icon(icon, color: effectiveText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: effectiveText, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) Icon(trailing, color: effectiveText),
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
  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
