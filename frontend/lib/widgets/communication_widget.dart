import 'package:flutter/material.dart';
import '../services/sms_service.dart';
import '../services/messaging_service.dart';
// Use REAL video call widget
import '../config/theme/app_theme.dart';

class CommunicationWidget extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String targetUserId;
  final String targetUserName;
  final String? targetPhoneNumber;

  const CommunicationWidget({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.targetUserId,
    required this.targetUserName,
    this.targetPhoneNumber,
  });

  @override
  State<CommunicationWidget> createState() => _CommunicationWidgetState();
}

class _CommunicationWidgetState extends State<CommunicationWidget> {
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    setState(() => _isInitializing = true);

    // try {
    //   await VideoCallService.initializeService();
    // } catch (e) {
    //   print('Error initializing communication services: $e');
    // }

    setState(() => _isInitializing = false);
  }

  Future<void> _startVideoCall() async {
    try {
      // final callData = await VideoCallService.initiateCall(
      //   callId: callId,
      //   callerId: widget.currentUserId,
      //   recipientId: widget.targetUserId,
      //   isVideoCall: true,
      // );

      // if (callData['success'] && mounted) {
      //   // TODO: open active call screen
      // } else {
      //   _showError('Failed to start video call');
      // }
    } catch (e) {
      _showError('Error starting video call: $e');
    }
  }

  Future<void> _startAudioCall() async {
    try {
      // final callData = await VideoCallService.initiateCall(
      //   callId: callId,
      //   callerId: widget.currentUserId,
      //   recipientId: widget.targetUserId,
      //   isVideoCall: false,
      // );

      // if (callData['success'] && mounted) {
      //   // TODO: open active call screen
      // } else {
      //   _showError('Failed to start audio call');
      // }
    } catch (e) {
      _showError('Error starting audio call: $e');
    }
  }

  Future<void> _sendSMS() async {
    if (widget.targetPhoneNumber == null || widget.targetPhoneNumber!.isEmpty) {
      _showError('Phone number not available');
      return;
    }

    final TextEditingController messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send SMS to ${widget.targetUserName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Phone: ${widget.targetPhoneNumber}'),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              maxLength: 160,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              final success = await SMSService.sendSMS(
                phoneNumber: widget.targetPhoneNumber!,
                message: messageController.text,
              );

              if (success) {
                _showSuccess('SMS sent successfully');
              } else {
                _showError('Failed to send SMS');
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    final TextEditingController messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send Message to ${widget.targetUserName}'),
        content: TextField(
          controller: messageController,
          decoration: const InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();

              final success = await MessagingService.sendMessage(
                recipientId: widget.targetUserId,
                senderId: widget.currentUserId,
                senderName: widget.currentUserName,
                message: messageController.text,
                messageType: 'text',
              );

              if (success) {
                _showSuccess('Message sent successfully');
              } else {
                _showError('Failed to send message');
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.success),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isInitializing) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact ${widget.targetUserName}',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.videocam,
                  label: 'Video Call',
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _startVideoCall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.phone,
                  label: 'Audio Call',
                  color: AppTheme.success,
                  onPressed: _startAudioCall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.sms,
                  label: 'SMS',
                  color: AppTheme.warning,
                  onPressed: widget.targetPhoneNumber != null ? _sendSMS : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.message,
                  label: 'Message',
                  color: AppTheme.info,
                  onPressed: _sendMessage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
