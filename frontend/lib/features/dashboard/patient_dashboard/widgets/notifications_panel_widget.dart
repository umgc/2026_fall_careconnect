import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

enum NotificationKind { urgent, important, reminder }

class NotificationItem {
  final NotificationKind kind;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onTapCTA;

  const NotificationItem({
    required this.kind,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onTapCTA,
  });
}

class NotificationsPanel extends StatefulWidget {
  final List<NotificationItem> notifications;
  final String heading;
  final bool initiallyExpanded;

  const NotificationsPanel({
    super.key,
    required this.notifications,
    this.heading = 'Notifications',
    this.initiallyExpanded = true,
  });

  @override
  State<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends State<NotificationsPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  String _translateDefaultHeader(String header){
    final t = AppLocalizations.of(context)!;
    switch(header){
      case('Notifications'):
        return t.notificationspanelwidget_notifications;
      default:
        return header;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasItems = widget.notifications.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: kElevationToShadow[1],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            title: _translateDefaultHeader(widget.heading),
            expanded: _expanded,
            onToggle: () => setState(() => _expanded = !_expanded),
          ),
          AnimatedCrossFade(
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 200),
            firstChild: hasItems
                ? Column(
                    children: [
                      const SizedBox(height: 8),
                      for (int i = 0;
                          i < widget.notifications.length;
                          i++) ...[
                        _NotificationCard(item: widget.notifications[i]),
                        if (i != widget.notifications.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      t.notificationspanelwidget_noNotifToShow,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;

  const _Header({
    required this.title,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(Icons.notifications_none,
            color: theme.colorScheme.onSurface, size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              expanded ? t.notificationspanelwidget_hideButton : t.notificationspanelwidget_showButton,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        Icon(
          expanded
              ? Icons.keyboard_arrow_up
              : Icons.keyboard_arrow_down,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationItem item;

  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (bg, border, iconColor) = switch (item.kind) {
      NotificationKind.urgent => (
          theme.colorScheme.error.withOpacity(0.10),
          theme.colorScheme.error.withOpacity(0.45),
          theme.colorScheme.error),
      NotificationKind.important => (
          theme.colorScheme.tertiary.withOpacity(0.08),
          theme.colorScheme.tertiary.withOpacity(0.45),
          theme.colorScheme.tertiary),
      NotificationKind.reminder => (
          const Color(0xFFFFF6E0),
          const Color(0xFFFFD78C),
          const Color(0xFFB78100)),
    };

    final bool showCTA =
        (item.ctaLabel != null && item.ctaLabel!.trim().isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: iconColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700),
                ),
                if (item.subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withOpacity(0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showCTA)
            ElevatedButton(
              onPressed: item.onTapCTA,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 12),
                shape: const StadiumBorder(),
                backgroundColor: theme.colorScheme.errorContainer
                    .withOpacity(0.90),
                foregroundColor:
                    theme.colorScheme.onErrorContainer,
              ),
              child: Text(
                item.ctaLabel!,
                style:
                    const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
