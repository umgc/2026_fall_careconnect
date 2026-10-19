import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/role_validator.dart';
import '../config/theme/app_theme.dart';

/// Dialog shown when user attempts to login with the wrong role
class RoleMismatchDialog extends StatelessWidget {
  final String actualRole;
  final String expectedRole;
  final String correctLoginRoute;
  final String message;

  const RoleMismatchDialog({
    super.key,
    required this.actualRole,
    required this.expectedRole,
    required this.correctLoginRoute,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final actualRoleDisplay = RoleValidator.getRoleDisplayName(actualRole);
    final expectedRoleDisplay = RoleValidator.getRoleDisplayName(expectedRole);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          SizedBox(width: 8),
          Text('Wrong Login Page'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Account Information',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Your account type: $actualRoleDisplay',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  'Current login page: $expectedRoleDisplay Login',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.6),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            // Navigate to the correct login page
            context.go(correctLoginRoute);
          },
          icon: const Icon(Icons.login),
          label: Text('Go to $actualRoleDisplay Login'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: AppTheme.textLight,
          ),
        ),
      ],
    );
  }

  /// Show the role mismatch dialog
  static Future<void> show({
    required BuildContext context,
    required String actualRole,
    required String expectedRole,
    required String correctLoginRoute,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => RoleMismatchDialog(
        actualRole: actualRole,
        expectedRole: expectedRole,
        correctLoginRoute: correctLoginRoute,
        message: message,
      ),
    );
  }
}
