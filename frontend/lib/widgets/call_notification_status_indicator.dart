import 'package:flutter/material.dart';
import '../services/call_notification_service.dart';

/// Widget that shows the real-time connection status for call notifications
class CallNotificationStatusIndicator extends StatefulWidget {
  final bool isInitialized;

  const CallNotificationStatusIndicator({
    super.key,
    required this.isInitialized,
  });

  @override
  State<CallNotificationStatusIndicator> createState() =>
      _CallNotificationStatusIndicatorState();
}

class _CallNotificationStatusIndicatorState
    extends State<CallNotificationStatusIndicator> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorOnline = theme.colorScheme.secondary;
    final colorConnecting = theme.colorScheme.tertiary;
    final colorDisabled = theme.disabledColor;
    final statusColor = _getStatusColor(
      theme,
      colorOnline,
      colorConnecting,
      colorDisabled,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _getStatusText(),
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(
    ThemeData theme,
    Color colorOnline,
    Color colorConnecting,
    Color colorDisabled,
  ) {
    if (!widget.isInitialized) return colorDisabled;
    return CallNotificationService.isConnected ? colorOnline : colorConnecting;
  }

  String _getStatusText() {
    if (!widget.isInitialized) return 'Initializing...';
    return CallNotificationService.isConnected ? 'Online' : 'Connecting...';
  }
}
