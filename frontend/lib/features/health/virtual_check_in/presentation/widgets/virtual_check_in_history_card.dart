import 'package:flutter/material.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in.dart';

/// "Virtual Check-In History"
class VirtualCheckInHistoryCard extends StatelessWidget {
  final List<VirtualCheckIn> entries;
  final VoidCallback? onConfigure;
  final void Function(VirtualCheckIn entry)? onEntryTap;
  final bool showConfigure;

  const VirtualCheckInHistoryCard({
    super.key,
    required this.entries,
    this.onConfigure,
    this.onEntryTap,
    this.showConfigure = false, // patients default to false
  }) : assert(!showConfigure || onConfigure != null,
            'showConfigure=true requires onConfigure');

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
            color: theme.shadowColor.withValues(alpha: 0.10),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Icon(Icons.computer, color: cs.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Virtual Check-In History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (showConfigure)
                OutlinedButton.icon(
                  onPressed: onConfigure,
                  icon: const Icon(Icons.settings, size: 18),
                  label: const Text('Configure Patient Check-in'),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Either empty state or the list
          entries.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _VirtualCheckInTile(
                    entry: entries[i],
                    onTap: onEntryTap,
                  ),
                ),
        ],
      ),
    );
  }
}

class _VirtualCheckInTile extends StatelessWidget {
  final VirtualCheckIn entry;
  final void Function(VirtualCheckIn entry)? onTap;
  const _VirtualCheckInTile({required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final border = cs.outlineVariant.withValues(alpha: .35);

    final (badgeLabel, badgeBg, badgeFg) = _badgeFor(entry.type, cs);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap == null ? null : () => onTap!(entry),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // First row: badge + clinician • clock + date/time
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      color: badgeFg,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: .2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.clinicianName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.schedule, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  _formatFullDateTime(entry.startedAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Facts grid: Duration | Status | Mood | Next Check-In
            _FactsGrid(entry: entry),

            const SizedBox(height: 12),

            // Session Summary
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session Summary',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(entry.summary, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Keep these helpers INSIDE this class to allow `static`
  static (String, Color, Color) _badgeFor(CheckInType t, ColorScheme cs) {
    switch (t) {
      case CheckInType.urgent:
        return ('urgent', const Color(0xFFDB2B2B), cs.onError);
      case CheckInType.followUp:
        return ('follow-up', const Color(0xFFF0A000), Colors.white);
      case CheckInType.routine:
        return ('routine', const Color(0xFF1E3A8A), Colors.white);
    }
  }

  static String _formatFullDateTime(DateTime d) {
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
      'Dec'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} • $h:$mm $amPm';
  }
}

class _FactsGrid extends StatelessWidget {
  final VirtualCheckIn entry;
  const _FactsGrid({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget cell(String label, Widget value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurface.withValues(alpha: .7),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            value,
          ],
        );

    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 440; // phone: two columns
      final children = <Widget>[
        cell(
            'Duration',
            Text('${entry.durationMinutes} minutes',
                style: theme.textTheme.bodyMedium)),
        cell(
          'Status',
          Row(
            children: [
              Icon(
                _statusIcon(entry.status),
                size: 16,
                color: _statusColor(entry.status, cs),
              ),
              const SizedBox(width: 6),
              Text(_statusLabel(entry.status),
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        cell('Mood', Text(entry.moodLabel, style: theme.textTheme.bodyMedium)),
        cell(
            'Next Check-In',
            Text(_formatDateOnly(entry.nextCheckIn),
                style: theme.textTheme.bodyMedium)),
      ];

      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: children.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: narrow ? 2 : 4,
          mainAxisExtent: 58,
          crossAxisSpacing: 16,
          mainAxisSpacing: 8,
        ),
        itemBuilder: (_, i) => children[i],
      );
    });
  }

  static String _formatDateOnly(DateTime d) {
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
      'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _statusLabel(CheckInStatus s) {
    switch (s) {
      case CheckInStatus.draft:
        return 'Draft';
      case CheckInStatus.submitted:
        return 'Submitted';
      case CheckInStatus.reviewed:
        return 'Reviewed';
      case CheckInStatus.completed:
        return 'Completed';
      case CheckInStatus.missed:
        return 'Missed';
      case CheckInStatus.cancelled:
        return 'Cancelled';
    }
  }

  static IconData _statusIcon(CheckInStatus s) {
    switch (s) {
      case CheckInStatus.draft:
        return Icons.edit_note;
      case CheckInStatus.submitted:
        return Icons.upload_file;
      case CheckInStatus.reviewed:
        return Icons.fact_check;
      case CheckInStatus.completed:
        return Icons.check_circle;
      case CheckInStatus.cancelled:
        return Icons.cancel;
      case CheckInStatus.missed:
        return Icons.error_outline;
    }
  }

  static Color _statusColor(CheckInStatus s, ColorScheme cs) {
    switch (s) {
      case CheckInStatus.draft:
        return cs.primary;
      case CheckInStatus.submitted:
        return Colors.orange.shade700;
      case CheckInStatus.reviewed:
      case CheckInStatus.completed:
        return Colors.green.shade600;
      case CheckInStatus.cancelled:
      case CheckInStatus.missed:
        return cs.error;
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.video_call, size: 28, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'No virtual check-ins yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
