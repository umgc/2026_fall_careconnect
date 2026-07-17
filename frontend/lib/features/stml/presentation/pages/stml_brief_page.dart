import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../config/theme/app_theme.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/stml_service.dart';

/// STML-2 / STML-5: the Daily Memory Brief — a self-contained, first-time-
/// clarity surface shown on app open with recent, prioritized information
/// (recent conversations, upcoming appointments, pending action items).
/// Large high-contrast text (18pt+), no hidden or gesture-only navigation.
class StmlBriefPage extends StatefulWidget {
  const StmlBriefPage({super.key});

  @override
  State<StmlBriefPage> createState() => _StmlBriefPageState();
}

class _StmlBriefPageState extends State<StmlBriefPage> {
  Future<StmlBrief>? _briefFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final patientId = context.read<UserProvider>().user?.patientId;
    if (patientId == null) {
      setState(() => _briefFuture = null);
      return;
    }
    setState(() {
      _briefFuture = StmlService.getDailyBrief(patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundSecondary,
      appBar: AppBar(
        title: const Text('Your Daily Brief'),
        backgroundColor: AppTheme.primary,
        foregroundColor: AppTheme.textLight,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Ask what we discussed',
            onPressed: () => context.push('/stml/recall'),
          ),
        ],
      ),
      body: _briefFuture == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No patient is selected for this account.',
                  style: TextStyle(fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _load(),
              child: FutureBuilder<StmlBrief>(
                future: _briefFuture,
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
                  final brief = snapshot.data!;
                  if (brief.cards.isEmpty) {
                    return const _EmptyBriefState();
                  }
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final card in brief.cards)
                        _BriefCard(card: card),
                      if (brief.disclaimer.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          brief.disclaimer,
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

class _EmptyBriefState extends StatelessWidget {
  const _EmptyBriefState();

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
                  Icon(Icons.wb_sunny_outlined, size: 48, color: AppTheme.textSecondary),
                  const SizedBox(height: 16),
                  Text(
                    "Nothing new right now. Check back after your next call, "
                    "visit, or appointment.",
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
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

class _BriefCard extends StatelessWidget {
  final StmlCard card;

  const _BriefCard({required this.card});

  ({IconData icon, Color color}) get _visual {
    switch (card.type.toUpperCase()) {
      case 'APPOINTMENT':
        return (icon: Icons.event, color: AppTheme.primary);
      case 'ACTION_ITEM':
        return (icon: Icons.check_circle_outline, color: AppTheme.warning);
      case 'MEDICATION':
        return (icon: Icons.medication_outlined, color: AppTheme.error);
      case 'RECALL':
      default:
        return (icon: Icons.chat_bubble_outline, color: AppTheme.accent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visual = _visual;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(visual.icon, color: visual.color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.headline,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                if (card.detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    card.detail,
                    style: const TextStyle(fontSize: 18, height: 1.3),
                  ),
                ],
                if (card.timestamp != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    DateFormat.yMMMd().add_jm().format(card.timestamp!),
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
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
