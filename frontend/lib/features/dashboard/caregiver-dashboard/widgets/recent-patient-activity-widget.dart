import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class RecentPatientActivity extends StatelessWidget {
  const RecentPatientActivity({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final activities = [
      {
        'patient': 'Sarah Johnson',
        'action': 'completed check-in',
        'time': '2 hours ago',
        'detail': 'Mood: Good (8/10)',
        'emoji': '😊',
      },
      {
        'patient': 'Robert Chen',
        'action': 'reported symptoms',
        'time': '4 hours ago',
        'detail': 'Mild headache',
        'emoji': '😐',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_heart_outlined,
                color: Colors.teal[600],
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                t.recentptactivity_recentPtActivityTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.teal[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...activities.map((activity) => _ActivityItem(
            patient: activity['patient']!,
            action: activity['action']!,
            time: activity['time']!,
            detail: activity['detail']!,
            emoji: activity['emoji']!,
          )),
        ],
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final String patient;
  final String action;
  final String time;
  final String detail;
  final String emoji;

  const _ActivityItem({
    required this.patient,
    required this.action,
    required this.time,
    required this.detail,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.teal[600],
                    ),
                    children: [
                      TextSpan(
                        text: patient,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      TextSpan(text: ' $action'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$time - $detail',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            emoji,
            style: const TextStyle(fontSize: 24),
          ),
        ],
      ),
    );
  }
}
