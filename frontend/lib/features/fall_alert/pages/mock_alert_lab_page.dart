import 'dart:async';

import 'package:flutter/material.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

import '../models/fall_alert.dart';
import '../services/mock_fall_detection_service.dart';
import '../navigation/alert_navigation.dart';

class MockAlertLabPage extends StatefulWidget {
  static const routeName = '/mock-alert-lab';

  const MockAlertLabPage({super.key});

  @override
  State<MockAlertLabPage> createState() => _MockAlertLabPageState();
}

class _MockAlertLabPageState extends State<MockAlertLabPage> {
  final _service = MockFallDetectionService();
  StreamSubscription<FallAlert>? _sub;
  final List<FallAlert> _recent = [];

  bool _running = false;

  @override
  void initState() {
    super.initState();

    _sub = _service.alerts$.listen((a) {
      setState(() {
        _recent.insert(0, a);

        if (_recent.length > 20) {
          _recent.removeLast();
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.fallAlertMockAlerts),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                FilledButton(
                  onPressed: _running ? null : _startPeriodic,
                  child: Text(t.fallAlertStart),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _running ? _stopPeriodic : null,
                  child: Text(t.fallAlertStop),
                ),
                const Spacer(),
                FilledButton.tonal(
                  onPressed: _triggerOnce,
                  child: Text(t.fallAlertTrigger),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _running ? t.fallAlertStatusRunning : t.fallAlertStatusStopped,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _recent.isEmpty
                  ? const _EmptyHint()
                  : ListView.separated(
                      itemCount: _recent.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) =>
                          _AlertTile(alert: _recent[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _startPeriodic() {
    _service.start();
    setState(() => _running = true);
  }

  void _stopPeriodic() {
    _service.stop();
    setState(() => _running = false);
  }

  Future<void> _triggerOnce() async {
    await _service.emitNow();

    if (!mounted) return;

    final t = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t.fallAlertMockAlertEmitted),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Center(
      child: Text(
        t.fallAlertNoAlertsYet,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final FallAlert alert;

  const _AlertTile({
    required this.alert,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final when = alert.detectedAtUtc.toLocal();

    final subtitle = t.fallAlertSourceWithTime(
      alert.source,
      when.toString(),
    );

    return ListTile(
      title: Text(alert.patientName),
      subtitle: Text(subtitle),
      trailing: alert.hasLiveVideo
          ? const Icon(Icons.videocam)
          : const Icon(Icons.watch),
      onTap: () {
        // Navigate directly into the alert details screen,
        // same as tapping a notification.
        AlertNavigation.navigateFromPayload(
          context,
          alert.toPayload(),
        );
      },
    );
  }
}
