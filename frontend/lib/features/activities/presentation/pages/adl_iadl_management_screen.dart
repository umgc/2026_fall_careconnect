import 'package:flutter/material.dart';
import 'package:care_connect_app/features/activities/presentation/pages/client_category_activities_screen.dart';
import 'package:care_connect_app/features/activities/presentation/pages/activity_log_history_screen.dart';

/// Hub screen for ADL & IADL management. Shown from the patient details Health tab.
/// Two entries: ADL Activities and IADL Activities, each opening the category-specific screen.
class AdlIadlManagementScreen extends StatelessWidget {
  final int clientId;
  final String clientName;

  const AdlIadlManagementScreen({
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
            const Text('ADL & IADL Management'),
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
            icon: Icons.bathtub,
            title: 'ADL Activities',
            subtitle: 'Log and manage Activities of Daily Living',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ClientCategoryActivitiesScreen(
                    clientId: clientId,
                    clientName: clientName,
                    category: 'ADL',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildEntryCard(
            context,
            icon: Icons.soup_kitchen,
            title: 'IADL Activities',
            subtitle: 'Log and manage Instrumental Activities of Daily Living',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ClientCategoryActivitiesScreen(
                    clientId: clientId,
                    clientName: clientName,
                    category: 'IADL',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildEntryCard(
            context,
            icon: Icons.history,
            title: 'Activity log history',
            subtitle: 'View logged activities for this client',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ActivityLogHistoryScreen(
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
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 28, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
