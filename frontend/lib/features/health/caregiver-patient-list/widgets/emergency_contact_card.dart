import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Patient Details — Emergency Contact
class EmergencyContactCard extends StatelessWidget {
  final String contactName; // e.g., "Michael Johnson"
  final String relationship; // e.g., "Spouse"
  final String? phone; // optional
  final String? email; // optional (shown under phone if provided)

  /// Optional overrides (if you want to handle actions yourself)
  final VoidCallback? onCall;
  final VoidCallback? onMessage;

  const EmergencyContactCard({
    super.key,
    required this.contactName,
    required this.relationship,
    this.phone,
    this.email,
    this.onCall,
    this.onMessage,
  });

  // -------- Helpers: phone + sms launchers --------
  static String _digitsOnly(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'[^0-9+]'), '');

  static Future<void> _launchTel(BuildContext context, String? rawPhone) async {
    final phone = _digitsOnly(rawPhone);
    if (phone.isEmpty) {
      _toast(context, 'No phone number available');
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _toast(context, 'Calling not supported on this device');
    }
  }

  static Future<void> _launchSms(
    BuildContext context, {
    required String? rawPhone,
    required String message,
  }) async {
    final phone = _digitsOnly(rawPhone);
    if (phone.isEmpty) {
      _toast(context, 'No phone number available');
      return;
    }
    // iOS/Android/Web: url_launcher handles sms: scheme where possible
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: message.isEmpty ? null : {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _toast(context, 'Messaging not supported on this device');
    }
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.10),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Icon(Icons.contact_emergency, color: cs.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Emergency Contact',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Inner compact panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withOpacity(0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT: contact info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Text(
                        contactName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      // Relationship (small, gray)
                      Text(
                        relationship,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurface.withOpacity(0.65),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),

                      // Phone
                      if (_hasValue(phone))
                        Text(
                          phone!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                          ),
                          softWrap: true,
                        ),

                      // Email (optional)
                      if (_hasValue(email)) ...[
                        const SizedBox(height: 4),
                        Text(
                          email!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withOpacity(0.85),
                          ),
                          softWrap: true,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // RIGHT: action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionIconButton.filled(
                      icon: Icons.phone,
                      tooltip: 'Call',
                      onTap: onCall ?? () => _launchTel(context, phone),
                    ),
                    const SizedBox(width: 10),
                    _ActionIconButton.outlined(
                      icon: Icons.chat_bubble_outline,
                      tooltip: 'Message',
                      onTap: onMessage ??
                          () async {
                            // quick compose dialog -> sms:
                            final msg = await _composeMessage(context);
                            if (msg == null) return; // cancelled
                            await _launchSms(
                              context,
                              rawPhone: phone,
                              message: msg,
                            );
                          },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _hasValue(String? s) => s != null && s.trim().isNotEmpty;

  /// Simple message composer dialog (returns text or null if cancelled)
  static Future<String?> _composeMessage(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Type your message…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}

/// Small, theme-aware buttons used on the right side of the card.
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool filled;

  const _ActionIconButton._({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.filled,
  });

  factory _ActionIconButton.filled({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) =>
      _ActionIconButton._(
        icon: icon,
        tooltip: tooltip,
        onTap: onTap,
        filled: true,
      );

  factory _ActionIconButton.outlined({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) =>
      _ActionIconButton._(
        icon: icon,
        tooltip: tooltip,
        onTap: onTap,
        filled: false,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = filled ? cs.primary : cs.surface;
    final fg = filled ? cs.onPrimary : cs.onSurface;
    final border = filled ? Colors.transparent : cs.outline;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 44,
            height: 40,
            child: Center(child: Icon(icon, size: 22, color: fg)),
          ),
        ),
      ),
    );
  }
}
