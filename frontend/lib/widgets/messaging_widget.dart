import 'package:flutter/material.dart';
import '../services/messaging_service.dart';
import '../config/theme/app_theme.dart';

class MessagingWidget extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final String recipientId;
  final String recipientName;

  const MessagingWidget({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.recipientId,
    required this.recipientName,
  });

  @override
  State<MessagingWidget> createState() => _MessagingWidgetState();
}

class _MessagingWidgetState extends State<MessagingWidget> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  int _charCount = 0;

  static const int _maxChars = 2000;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _messageController.addListener(() {
      setState(() => _charCount = _messageController.text.length);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    try {
      final messages = await MessagingService.getConversation(
        userId1: widget.currentUserId,
        userId2: widget.recipientId,
      );

      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      print('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending || _charCount > _maxChars) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final bool success = await MessagingService.sendMessage(
        recipientId: widget.recipientId,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        message: message,
        messageType: 'text',
      );

      if (success) {
        // Add message to local list immediately for better UX
        setState(() {
          _messages.add({
            'senderId': widget.currentUserId,
            'message': message,
            'messageType': 'text',
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'sent',
          });
        });

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to send message')));
      }
    } catch (e) {
      print('Error sending message: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Error sending message')));
    } finally {
      setState(() => _isSending = false);
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isMyMessage = message['senderId'] == widget.currentUserId;
    final timestamp = DateTime.parse(message['timestamp']);

    return Align(
      alignment: isMyMessage ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Column(
          crossAxisAlignment:
              isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: isMyMessage
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: !isMyMessage
                    ? Border.all(color: Theme.of(context).dividerColor)
                    : null,
              ),
              child: Text(
                message['message'],
                style: AppTheme.bodyMedium.copyWith(
                  color: isMyMessage
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatTimestamp(timestamp),
              style: AppTheme.bodySmall.copyWith(
                color: Theme.of(context).hintColor,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
    );

    if (messageDate == today) {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else {
      return '${timestamp.day}/${timestamp.month} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withOpacity(0.2),
              child: Text(
                widget.recipientName.isNotEmpty
                    ? widget.recipientName[0].toUpperCase()
                    : '?',
                style: AppTheme.bodyMedium.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.recipientName,
                    style: AppTheme.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Online', // You can implement real presence detection
                    style: AppTheme.bodySmall.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () {
              // Trigger video call
              Navigator.of(context).pop('video_call');
            },
          ),
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () {
              // Trigger audio call
              Navigator.of(context).pop('audio_call');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Theme.of(context).hintColor,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Start a conversation',
                              style: AppTheme.bodyLarge.copyWith(
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return _buildMessageBubble(_messages[index]);
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ),
                        maxLength: _maxChars,
                        buildCounter: (_,
                                {required currentLength,
                                required isFocused,
                                maxLength}) =>
                            null,
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FloatingActionButton.small(
                      onPressed: (_isSending || _charCount > _maxChars)
                          ? null
                          : _sendMessage,
                      backgroundColor: _charCount > _maxChars
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      child: _isSending
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.send,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                    ),
                  ],
                ),
                if (_charCount >= 1800)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 4),
                    child: Text(
                      '$_charCount / $_maxChars',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _charCount >= _maxChars
                            ? Theme.of(context).colorScheme.error
                            : _charCount >= 1900
                                ? Colors.orange
                                : Theme.of(context).hintColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
