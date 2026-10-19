import 'package:flutter/material.dart';

/// Row data. You can pass either (score5 + emoji) OR (score10) and it maps.
class MoodHistoryEntry {
  final DateTime date;
  final String label; // "Poor" | "Fair" | "Good" | "Excellent"
  final int? score5; // 1..5
  final int? score10; // 0..10 (auto-mapped to 1..5)
  final String? emoji; // emoji for score5 path
  final String? note;

  const MoodHistoryEntry({
    required this.date,
    required this.label,
    this.score5,
    this.score10,
    this.emoji,
    this.note,
  });
}

/// Patient Details → Mood tab: titled section + list + empty state.
/// Visuals are tuned to the mockup: light rounded list items,
/// "Score: x/5" + single blue progress bar, emoji chip, subtle date label.
class MoodHistorySection extends StatelessWidget {
  final List<MoodHistoryEntry> entries;
  final String title; // default: 'Mood History'

  const MoodHistorySection({
    super.key,
    required this.entries,
    this.title = 'Mood History',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardBg = theme.colorScheme.surface;
    final border = theme.colorScheme.outlineVariant.withValues(alpha: 0.35);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header (heart icon + title)
          Row(
            children: [
              Icon(Icons.favorite_border,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (entries.isEmpty)
            const _EmptyState(message: 'No mood history yet')
          else
            Column(
              children: List.generate(entries.length, (i) {
                final e = entries[i];

                // Prefer explicit 1..5 + emoji; otherwise map from 0..10.
                if (e.score5 != null && e.emoji != null) {
                  return _MoodRow(
                    date: e.date,
                    label: e.label,
                    score5: e.score5!.clamp(1, 5),
                    emoji: e.emoji!,
                    note: e.note,
                  );
                } else if (e.score10 != null) {
                  return _MoodRow.fromScore10(
                    date: e.date,
                    label: e.label,
                    score10: e.score10!.clamp(0, 10),
                    note: e.note,
                  );
                }

                // Fallback if data incomplete
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Missing score for ${e.label} on ${_fmtDate(e.date)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime d) {
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
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.sentiment_neutral,
              size: 28, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------- Inline row (tuned to match the mockup) ----------
class _MoodRow extends StatelessWidget {
  final DateTime date;
  final String label;
  final int score5; // 1..5
  final String emoji;
  final String? note;

  const _MoodRow({
    required this.date,
    required this.label,
    required this.score5,
    required this.emoji,
    this.note,
  });

  factory _MoodRow.fromScore10({
    required DateTime date,
    required String label,
    required int score10, // 0..10
    String? note,
  }) {
    // Map 0..10 → 1..5 buckets (0-1→1, 2-3→2, 4-5→3, 6-7→4, 8-10→5)
    final s10 = score10.clamp(0, 10);
    final mapped = (s10 <= 1)
        ? 1
        : (s10 <= 3)
            ? 2
            : (s10 <= 5)
                ? 3
                : (s10 <= 7)
                    ? 4
                    : 5;

    return _MoodRow(
      date: date,
      label: label,
      score5: mapped,
      emoji: _emojiForLabel(label),
      note: note,
    );
  }

  static String _emojiForLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('poor') || l.contains('sad') || l.contains('bad'))
      return '😟';
    if (l.contains('fair') || l.contains('ok')) return '😐';
    if (l.contains('good')) return '🙂';
    if (l.contains('excellent') || l.contains('great')) return '😄';
    return '😐';
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Dec',
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
      'Nov'
    ]; // keeps Dec visible in your sample order
    return '${months[(d.month % 12)]} ${d.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Row container matches the mockup’s “soft card” look
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date (left, subtle)
          SizedBox(
            width: 56,
            child: Text(
              _fmtDate(date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),

          // Emoji circular chip
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),

          // Main content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Label (“Poor/Fair/Good”) on top
                Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),

                // “Score: x/5” + single rounded progress bar (blue)
                Row(
                  children: [
                    Text(
                      'Score: $score5/5',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _ProgressLine(value: score5 / 5)),
                  ],
                ),

                // Optional note (muted)
                if (note != null && note!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    note!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Single blue rounded progress bar; width reflects score/5.
class _ProgressLine extends StatelessWidget {
  final double value; // 0..1
  const _ProgressLine({required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.primary.withValues(alpha: 0.15);
    final fg = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final fill = (w * value).clamp(0.0, w);
        return Container(
          height: 8,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: fill,
              height: 8,
              decoration: BoxDecoration(
                color: fg,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );
      },
    );
  }
}
