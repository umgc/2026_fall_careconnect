import 'package:flutter/material.dart';
import 'package:care_connect_app/features/dashboards/behavioral_trend_screen.dart';
import 'package:care_connect_app/features/dashboards/competency_trend_screen.dart';
import 'package:care_connect_app/features/dashboards/participation_screen.dart';

/// Hub for client dashboards (Progress/Reports). Opened from In-home → "Dashboards".
class DashboardsScreen extends StatelessWidget {
  final int clientId;
  final String clientName;

  const DashboardsScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Dashboards'),
            Text(
              clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildEntryCard(
            context,
            icon: Icons.show_chart,
            title: 'Competency Trends',
            subtitle: 'Average competency score over time by activity',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => CompetencyTrendScreen(
                    clientId: clientId,
                    clientName: clientName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildEntryCard(
            context,
            icon: Icons.psychology_outlined,
            title: 'Behavioral Frequency',
            subtitle:
                'Incident count by week and most frequent behavior keywords',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => BehavioralTrendScreen(
                    clientId: clientId,
                    clientName: clientName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildEntryCard(
            context,
            icon: Icons.assignment_outlined,
            title: 'Participation',
            subtitle: 'Activity log counts and last logged by ADL / IADL',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ParticipationScreen(
                    clientId: clientId,
                    clientName: clientName,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
