import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Patient Details — Contact Information
/// Pure presentational widget. Pass only what you have; rows hide if null/empty.
class ContactInfoCard extends StatelessWidget {
  final String? phone; // e.g., "(555) 123-4567"
  final String? email; // e.g., "patient@example.com"
  final DateTime? dateOfBirth; // optional
  final String? addressLine1; // "123 Main St"
  final String? addressLine2; // "Apt 4B"
  final String? city; // "Springfield"
  final String? state; // "IL"
  final String? postalCode; // "62701"

  /// Optional overrides (we’ll also provide safe defaults)
  final VoidCallback? onCallPhone;
  final VoidCallback? onSendEmail;

  const ContactInfoCard({
    super.key,
    this.phone,
    this.email,
    this.dateOfBirth,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.postalCode,
    this.onCallPhone,
    this.onSendEmail,
  });

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
          Row(
            children: [
              Icon(Icons.info_outline, color: cs.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'Contact Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // PHONE (left icon is interactive)
          if (_hasValue(phone))
            _row(
              context,
              icon: Icons.phone,
              label: 'Phone',
              value: phone!,
              onIconTap: _callPhone, // use default launcher (can be overridden)
            ),

          // EMAIL (left icon is interactive)
          if (_hasValue(email))
            _row(
              context,
              icon: Icons.email_outlined,
              label: 'Email',
              value: email!,
              onIconTap: _sendEmail,
            ),

          if (dateOfBirth != null)
            _row(
              context,
              icon: Icons.cake_outlined,
              label: 'Date of Birth',
              value: _fmtDate(dateOfBirth!),
            ),

          // ADDRESS (left icon is interactive)
          if (_hasAnyAddress)
            _row(
              context,
              icon: Icons.home_outlined,
              label: 'Address',
              value: _addressString(),
              isMultiline: true,
              onIconTap: _openMaps,
              iconTooltip: 'Open in Google Maps',
              hoverBump: true,
            ),
        ],
      ),
    );
  }

  /// ---- Row builder (no right-side buttons; left icon is clickable) ----
  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onIconTap,
    String? iconTooltip,
    bool isMultiline = false,
    bool hoverBump = false,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final iconWidget = _InteractiveIcon(
      icon: icon,
      color: cs.onSurface.withOpacity(0.60),
      tooltip: iconTooltip ??
          (onIconTap == null ? null : (label == 'Phone' ? 'Call' : label)),
      onTap: onIconTap,
      hoverBump: hoverBump,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment:
            isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          iconWidget,
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }

  // ---------- Launchers (defaults) ----------
  void _callPhone() async {
    if (!_hasValue(phone)) return;
    final tel = 'tel:${_digitsOnly(phone!)}';
    final uri = Uri.parse(tel);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _sendEmail() async {
    if (!_hasValue(email)) return;

    // Prefer Outlook Web if available; otherwise mailto:
    final outlook = Uri.parse(
      'https://outlook.office.com/mail/deeplink/compose'
      '?to=${Uri.encodeComponent(email!)}',
    );
    final mailto = Uri(
      scheme: 'mailto',
      path: email!,
      // You can prefill subject/body here if desired.
      query: '',
    );

    if (await canLaunchUrl(outlook)) {
      await launchUrl(outlook, webOnlyWindowName: '_blank');
      return;
    }
    if (await canLaunchUrl(mailto)) {
      await launchUrl(mailto, mode: LaunchMode.platformDefault);
    }
  }

  void _openMaps() async {
    final q = Uri.encodeComponent(_addressString().replaceAll('\n', ', '));
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, webOnlyWindowName: '_blank');
    }
  }

  // ---------- helpers ----------
  bool _hasValue(String? s) => s != null && s.trim().isNotEmpty;

  bool get _hasAnyAddress =>
      _hasValue(addressLine1) ||
      _hasValue(addressLine2) ||
      _hasValue(city) ||
      _hasValue(state) ||
      _hasValue(postalCode);

  String _addressString() {
    final lines = <String>[];
    final l1 = addressLine1?.trim();
    final l2 = addressLine2?.trim();
    final cityStr = city?.trim();
    final stateStr = state?.trim();
    final zipStr = postalCode?.trim();

    if (_hasValue(l1)) lines.add(l1!);
    if (_hasValue(l2)) lines.add(l2!);

    final last = [
      if (_hasValue(cityStr)) cityStr,
      if (_hasValue(stateStr)) stateStr,
      if (_hasValue(zipStr)) zipStr,
    ]
        .whereType<String>()
        .join(', ')
        .replaceAll(', ,', ',')
        .replaceAll(' ,', ',');
    if (_hasValue(last)) lines.add(last);

    return lines.join('\n');
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _digitsOnly(String s) => s.replaceAll(RegExp(r'[^0-9+]'), '');
}

/// Small clickable icon with hover affordance for the left column.
class _InteractiveIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool hoverBump;

  const _InteractiveIcon({
    required this.icon,
    required this.color,
    this.tooltip,
    this.onTap,
    this.hoverBump = false,
  });

  @override
  State<_InteractiveIcon> createState() => _InteractiveIconState();
}

class _InteractiveIconState extends State<_InteractiveIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      widget.icon,
      color: widget.onTap == null
          ? widget.color
          : (_hover ? widget.color.withOpacity(0.85) : widget.color),
      size: 28,
    );

    final core = InkWell(
      onTap: widget.onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.all(4),
        transform: widget.hoverBump && _hover
            ? (Matrix4.identity()..translate(0.0, -1.0, 0.0))
            : Matrix4.identity(),
        child: icon,
      ),
    );

    final withHover = MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: core,
    );

    return widget.tooltip == null
        ? withHover
        : Tooltip(message: widget.tooltip!, child: withHover);
  }
}
