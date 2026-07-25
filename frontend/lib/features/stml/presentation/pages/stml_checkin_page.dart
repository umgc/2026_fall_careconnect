import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/stml_service.dart';

/// STML-3: caregiver check-in preparation view. Consent-gated — the care
/// recipient must have an active caregiver-patient link granting access,
/// or [StmlCheckIn.consentGranted] is false and no records are shown.
class StmlCheckInPage extends StatefulWidget {
  final int patientId;

  const StmlCheckInPage({super.key, required this.patientId});

  @override
  State<StmlCheckInPage> createState() => _StmlCheckInPageState();
}

class _StmlCheckInPageState extends State<StmlCheckInPage> {
  Future<StmlCheckIn>? _checkInFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final caregiverId = context.read<UserProvider>().user?.id;
    if (caregiverId == null) {
      setState(() => _checkInFuture = null);
      return;
    }
    setState(() {
      _checkInFuture = StmlService.getCheckIn(
        patientId: widget.patientId,
        caregiverId: caregiverId,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundSecondary,
      appBar: AppBar(
        title: const Text('Check-in Prep'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
      ),
      body: _checkInFuture == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'You must be signed in as a caregiver to view this.',
                  style: TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: FutureBuilder<StmlCheckIn>(
                future: _checkInFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    final message = snapshot.error is StmlException
                        ? (snapshot.error as StmlException).message
                        : 'Something went wrong. Please try again.';
                    return _ErrorState(message: message, onRetry: _load);
                  }

                  final checkIn = snapshot.data!;
                  if (!checkIn.consentGranted) {
                    return _ConsentDeniedState(disclaimer: checkIn.disclaimer);
                  }

                  if (checkIn.notes.isEmpty && checkIn.pendingItems.isEmpty) {
                    return const _EmptyCheckInState();
                  }

                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (checkIn.pendingItems.isNotEmpty) ...[
                        _SectionHeader(
                          icon: Icons.check_circle_outline,
                          label: 'Pending items',
                        ),
                        for (final item in checkIn.pendingItems)
                          _CheckInItemCard(item: item),
                        const SizedBox(height: 12),
                      ],
                      if (checkIn.notes.isNotEmpty) ...[
                        _SectionHeader(icon: Icons.notes, label: 'Notes'),
                        for (final item in checkIn.notes)
                          _CheckInItemCard(item: item),
                      ],
                      if (checkIn.disclaimer.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          checkIn.disclaimer,
                          style: AppTheme.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CheckInItemCard extends StatelessWidget {
  final StmlCheckInItem item;

  const _CheckInItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.summary, style: const TextStyle(fontSize: 17, height: 1.3)),
          if (item.date.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              item.date,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyCheckInState extends StatelessWidget {
  const _EmptyCheckInState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nothing to prepare for right now.',
                textAlign: TextAlign.center,
                style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentDeniedState extends StatelessWidget {
  final String disclaimer;

  const _ConsentDeniedState({required this.disclaimer});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    disclaimer.isNotEmpty
                        ? disclaimer
                        : "This care recipient hasn't granted check-in access.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
