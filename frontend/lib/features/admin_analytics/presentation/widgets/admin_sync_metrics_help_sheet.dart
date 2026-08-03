import 'package:flutter/material.dart';

class AdminSyncMetricsHelpSheet {
  const AdminSyncMetricsHelpSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('About sync events', style: theme.textTheme.titleLarge),
                const SizedBox(height: 16),
                _Section(
                  title: 'What are sync events?',
                  body:
                      'Sync events are anonymous telemetry emitted when the app '
                      'flushes offline-queued writes after reconnecting. '
                      'Started counts come from sync_started; completed and failed '
                      'event counts come from sync_completed and sync_failed. '
                      'Attempted, succeeded, and failed totals are summed from '
                      'sync_completed payloads.',
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Why might everything be zero?',
                  body:
                      'Zeros usually mean no offline sync activity occurred in the '
                      'selected date range. Common reasons include users staying '
                      'online the whole time, offline persistence being disabled, '
                      'or no writes being queued while offline.',
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'How to trigger sync events',
                  body:
                      '1. Enable offline mode in Settings (if available).\n'
                      '2. Go offline (airplane mode or disable network).\n'
                      '3. Make a change that queues a write (for example, update a record).\n'
                      '4. Come back online — the app auto-syncs and emits telemetry.',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(body, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
