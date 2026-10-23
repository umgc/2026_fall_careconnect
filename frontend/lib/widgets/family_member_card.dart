import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/theme/app_theme.dart';

class FamilyMemberCard extends StatelessWidget {
  final String firstName;
  final String lastName;
  final String relationship;
  final String phone;
  final String email;
  final String lastInteraction;

  const FamilyMemberCard({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.relationship,
    required this.phone,
    required this.email,
    required this.lastInteraction,
  });

  String get fullName => '$firstName $lastName'.trim();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colorScheme.primary),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withOpacity(0.1),
          child: Text(
            firstName.isNotEmpty ? firstName[0].toUpperCase() : 'F',
            style: TextStyle(
              color: colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fullName,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(relationship, style: textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                // Phone button
                IconButton(
                  icon: const Icon(Icons.phone,
                      color: AppTheme.success, size: 20),
                  onPressed: () async {
                    final uri = Uri(scheme: 'tel', path: phone);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  tooltip: 'Call $firstName',
                ),
                // SMS button
                IconButton(
                  icon:
                      const Icon(Icons.message, color: AppTheme.info, size: 20),
                  onPressed: () async {
                    final uri = Uri(scheme: 'sms', path: phone);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  tooltip: 'Send SMS to $firstName',
                ),
                // Email button (show only if email is provided)
                if (email.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.email,
                        color: AppTheme.warning, size: 20),
                    onPressed: () async {
                      final uri = Uri(
                        scheme: 'mailto',
                        path: email,
                        queryParameters: {
                          'subject': 'CareConnect Family Update',
                          'body': 'Hello $firstName,\n\n',
                        },
                      );
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    tooltip: 'Email $firstName',
                  ),
              ],
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (email.isNotEmpty)
              Text('Email: $email', style: textTheme.bodySmall),
            Text(
              'Last Interaction: $lastInteraction',
              style: textTheme.bodySmall,
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) async {
            switch (value) {
              case 'call':
                final uri = Uri(scheme: 'tel', path: phone);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
                break;
              case 'sms':
                final uri = Uri(scheme: 'sms', path: phone);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
                break;
              case 'email':
                if (email.isNotEmpty) {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: email,
                    queryParameters: {
                      'subject': 'CareConnect Family Update',
                      'body': 'Hello $firstName,\n\n',
                    },
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                }
                break;
              case 'edit':
                // TODO: Implement edit functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Edit feature coming soon')),
                );
                break;
              case 'delete':
                // TODO: Implement delete functionality
                _showDeleteConfirmation(context);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'call',
              child: Row(
                children: [
                  Icon(Icons.phone, color: AppTheme.success),
                  SizedBox(width: 8),
                  Text('Call'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'sms',
              child: Row(
                children: [
                  Icon(Icons.message, color: AppTheme.info),
                  SizedBox(width: 8),
                  Text('Send SMS'),
                ],
              ),
            ),
            if (email.isNotEmpty)
              const PopupMenuItem(
                value: 'email',
                child: Row(
                  children: [
                    Icon(Icons.email, color: AppTheme.warning),
                    SizedBox(width: 8),
                    Text('Send Email'),
                  ],
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: colorScheme.secondary),
                  const SizedBox(width: 8),
                  const Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: AppTheme.error),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Delete Family Member',
            style: theme.textTheme.titleLarge,
          ),
          content: Text(
            'Are you sure you want to remove $fullName from your family members?',
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: Implement delete functionality
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$fullName removed successfully')),
                );
              },
              style: TextButton.styleFrom(foregroundColor: AppTheme.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}
