import 'package:care_connect_app/features/health/caregiver-patient-list/models/patient-info.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Widget that displays patient information in a card format.
///
/// This card shows essential patient information including:
/// - Patient name and urgency status
/// - Last update timestamp and status message
/// - Next check-in date
/// - Current mood with emoji indicator
/// - Notification and message badges
///
/// The card has visual indicators for urgent cases with red border and badge.
class PatientCard extends StatelessWidget {
  /// The patient data to display
  final Patient patient;

  /// Optional callback function when the card is tapped
  final VoidCallback? onTap;

  /// Optional callback function when the message icon is tapped
  final VoidCallback? onMessageTap;

  /// Optional callback to open Care Circle invite QR for this patient link.
  final VoidCallback? onInviteTap;

  /// Creates a PatientCard widget.
  ///
  /// Parameters:
  /// * [patient] - The patient data to display in the card
  /// * [onTap] - Optional callback function executed when card is tapped
  const PatientCard({
    super.key,
    required this.patient,
    this.onTap,
    this.onMessageTap,
    this.onInviteTap,
  });

  /// Builds the patient card widget.
  ///
  /// Creates a Material Card with InkWell for tap feedback. The card includes:
  /// - A colored left border (red for urgent, black for normal)
  /// - Patient name with optional "URGENT" badge
  /// - Last updated date and status message
  /// - Next check-in date
  /// - Mood indicator with emoji
  /// - Notification and message count badges
  ///
  /// Parameters:
  /// * [context] - The build context
  ///
  /// Returns:
  /// * Widget - A styled card containing all patient information
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MM/dd/yyyy');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: InkWell(
        onTap: null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border(
              left: BorderSide(
                color: patient.isUrgent ? Colors.red : Colors.black,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        patient.fullName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (patient.isUrgent)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'URGENT',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Last Updated: ${dateFormat.format(patient.lastUpdated)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  patient.statusMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: patient.isUrgent
                        ? Colors.red
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Next Check-In: ${dateFormat.format(patient.nextCheckIn)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      'Mood: ',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      patient.moodEmoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      patient.mood,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    _buildIconWithBadge(
                      Icons.notifications_outlined,
                      patient.isUrgent ? 1 : 0,
                      theme,
                    ),
                    const SizedBox(width: 16),
                    InkWell(
                      onTap: onMessageTap,
                      borderRadius: BorderRadius.circular(16),
                      child: _buildIconWithBadge(
                        Icons.message_outlined,
                        patient.messageCount,
                        theme,
                      ),
                    ),
                  ],
                ),

                // "View Details" button
                const SizedBox(height: 12),
                const Divider(height: 1),

                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: onTap,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const SizedBox.shrink(),
                        label: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('View Details'),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                      if (onInviteTap != null) ...[
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: onInviteTap,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 40),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.qr_code_2, size: 18),
                          label: const Text('Invite'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds an icon with an optional notification badge.
  ///
  /// Creates a stack with an icon and a red circular badge showing the count.
  /// The badge is only displayed when the count is greater than 0.
  ///
  /// Parameters:
  /// * [icon] - The icon to display
  /// * [count] - The number to show in the badge (badge hidden if 0)
  /// * [theme] - The app theme data for consistent styling
  ///
  /// Returns:
  /// * Widget - A stack containing the icon and optional badge
  Widget _buildIconWithBadge(IconData icon, int count, ThemeData theme) {
    return Stack(
      children: [
        Icon(
          icon,
          color: theme.colorScheme.onSurfaceVariant,
          size: 32,
        ),
        if (count > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(
                minWidth: 12,
                minHeight: 12,
              ),
              child: Text(
                count.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
