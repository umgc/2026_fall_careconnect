import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Patient-facing fall prompt screen
/// - Shows "I'm Okay" and "Call for Help"
/// - Starts a countdown and auto-calls emergency if there is no response
/// - Designed to be accessible and readable
class PatientFallPromptPage extends StatefulWidget {
  static const routeName = '/patient-fall-prompt';

  /// Seconds to wait before auto calling emergency services
  final int autoCallSeconds;

  /// Phone number to dial for emergency services. Make region aware later.
  final String emergencyNumber;

  /// Optional contact name and phone shown as a secondary option in the sheet
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  /// Optional callback after the patient confirms they are okay
  final Future<void> Function()? onAcknowledgeOk;

  /// Optional callback when the app initiates the emergency call
  final Future<void> Function()? onEscalate;

  const PatientFallPromptPage({
    super.key,
    this.autoCallSeconds = 30,
    this.emergencyNumber = '911',
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.onAcknowledgeOk,
    this.onEscalate,
  });

  @override
  State<PatientFallPromptPage> createState() => _PatientFallPromptPageState();
}

class _PatientFallPromptPageState extends State<PatientFallPromptPage> {
  late int _remaining;
  Timer? _timer;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.autoCallSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        await _autoCallEmergency();
        return;
      }
      setState(() => _remaining--);
    });
  }

  Future<void> _acknowledgeOk() async {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    if (widget.onAcknowledgeOk != null) {
      try {
        await widget.onAcknowledgeOk!();
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.of(context).maybePop();
    _toast('Glad you are okay. We will dismiss this alert.');
  }

  Future<void> _callEmergencyDirect() async {
    if (_completed) return;
    _completed = true;
    _timer?.cancel();
    if (widget.onEscalate != null) {
      try {
        await widget.onEscalate!();
      } catch (_) {}
    }
    final uri = Uri(scheme: 'tel', path: widget.emergencyNumber);
    if (!await launchUrl(uri)) {
      _toast('Could not start the call.');
      _completed = false; // allow retry
      _startTimer();
    }
  }

  Future<void> _autoCallEmergency() async {
    if (!mounted || _completed) return;
    _completed = true;
    if (widget.onEscalate != null) {
      try {
        await widget.onEscalate!();
      } catch (_) {}
    }
    final uri = Uri(scheme: 'tel', path: widget.emergencyNumber);
    if (!await launchUrl(uri) && mounted) {
      _toast('Auto call failed to start.');
    }
  }

  Future<void> _openEmergencySheet() async {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    await showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final canCallContact = (widget.emergencyContactPhone ?? '').isNotEmpty;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Emergency actions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: const Text('Choose how you want to escalate'),
                ),
                const SizedBox(height: 8),
                _EmergencyTile(
                  icon: Icons.local_phone_rounded,
                  label: 'Call ${widget.emergencyNumber}',
                  subtitle: 'Connect to local emergency services',
                  onTap: () {
                    Navigator.pop(context);
                    _callEmergencyDirect();
                  },
                ),
                const SizedBox(height: 8),
                _EmergencyTile(
                  icon: Icons.contact_phone_rounded,
                  label:
                      'Call ${widget.emergencyContactName ?? 'Emergency Contact'}',
                  subtitle: widget.emergencyContactPhone ?? 'No phone on file',
                  enabled: canCallContact,
                  onTap: () async {
                    Navigator.pop(context);
                    final phone = widget.emergencyContactPhone!;
                    final uri = Uri(scheme: 'tel', path: phone);
                    if (!await launchUrl(uri)) {
                      _toast('Could not start the call.');
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? cs.surface,
        foregroundColor: theme.appBarTheme.foregroundColor ?? cs.onSurface,
        title: const Text('Fall Detected'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: theme.dividerColor.withOpacity(0.12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: cs.error, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Are You Okay?',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              )),
                          const SizedBox(height: 6),
                          Text(
                            'It looks like you may have fallen. Do you need help?',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // "I'm Okay"
              _ActionButton(
                icon: Icons.check_circle_outline,
                label: "I'm Okay",
                onPressed: _acknowledgeOk,
                background: cs.surface,
                border: theme.dividerColor.withOpacity(0.24),
                textColor: cs.onSurface,
              ),
              const SizedBox(height: 12),

              // Call for help
              _ActionButton(
                icon: Icons.emergency_share_rounded,
                label: 'Call for Help',
                onPressed: _openEmergencySheet,
                background: cs.error,
                textColor: cs.onError,
              ),

              const Spacer(),

              // Countdown banner
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'If you do not respond within ${widget.autoCallSeconds} seconds, '
                        'emergency services will be contacted automatically.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Auto-calling in $_remaining seconds...',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Reused helper from your caregiver page
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
      height: 52,
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
                      color: effectiveText, fontWeight: FontWeight.w700)),
            ),
            if (trailing != null) Icon(trailing, color: effectiveText),
          ],
        ),
      ),
    );
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
