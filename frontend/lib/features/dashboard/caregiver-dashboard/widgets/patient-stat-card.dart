import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Widget that displays patient statistics in responsive card layout.
///
/// This widget shows key metrics for caregivers including missed check-ins
/// and active patients count. The layout adapts to screen size, displaying
/// cards in a column on small screens and in a row on larger screens.
class PatientStatisticsCards extends StatelessWidget {
  /// Creates a PatientStatisticsCards widget.
  const PatientStatisticsCards({super.key});

  /// Builds the responsive statistics card layout.
  ///
  /// Uses LayoutBuilder to determine screen size and adjusts the layout
  /// accordingly. On screens smaller than 600px, cards are arranged vertically.
  /// On larger screens, cards are arranged horizontally.
  ///
  /// Parameters:
  /// * [context] - The build context
  ///
  /// Returns:
  /// * Widget - A responsive layout containing statistics cards
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 600;

        if (isSmallScreen) {
          return Column(
            children: [
              _StatCard(
                icon: Icons.people_outline,
                iconColor: Colors.blue,
                title: t.ptstatcard_missedCheckInHeader,
                value: '24',
                valueColor: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              _StatCard(
                icon: Icons.monitor_heart_outlined,
                iconColor: Colors.green,
                title: t.ptstatcard_activePtsHeader,
                value: '32',
                valueColor: Colors.green,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.people_outline,
                iconColor: Colors.blue,
                title: t.ptstatcard_missedCheckIn,
                value: '24',
                valueColor: Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _StatCard(
                icon: Icons.monitor_heart_outlined,
                iconColor: Colors.green,
                title: t.ptstatcard_activePts,
                value: '32',
                valueColor: Colors.green,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Private widget that displays an individual statistic card.
///
/// This widget renders a single statistic with an icon, title, and value
/// in a visually appealing card format with rounded corners and shadow.
class _StatCard extends StatelessWidget {
  /// The icon to display at the top of the card
  final IconData icon;

  /// The color for the icon and its background
  final Color iconColor;

  /// The title text displayed below the icon
  final String title;

  /// The statistical value to be prominently displayed
  final String value;

  /// The color for the value and title text
  final Color valueColor;

  /// Creates a _StatCard widget.
  ///
  /// Parameters:
  /// * [icon] - The icon to display at the top of the card
  /// * [iconColor] - The color for the icon and its background
  /// * [title] - The title text displayed below the icon
  /// * [value] - The statistical value to be prominently displayed
  /// * [valueColor] - The color for the value and title text
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.valueColor,
  });

  /// Builds the statistic card widget.
  ///
  /// Creates a container with rounded corners, shadow, and padding that
  /// displays the icon, title, and value in a centered column layout.
  /// The card has a minimum height of 120px and uses theme colors.
  ///
  /// Parameters:
  /// * [context] - The build context
  ///
  /// Returns:
  /// * Widget - A decorated container with the statistic information
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: valueColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
