import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:uuid/uuid.dart';
import '../../../../widgets/ai_chat_improved.dart';

class ChatPage extends StatefulWidget {
  final String contactName;
  final String contactRole;

  const ChatPage({
    super.key,
    required this.contactName,
    required this.contactRole,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _chatController;
  final String _currentUserId = '82091008-a484-4a89-ae75-a22bf8d6f3ac';
  final String _doctorId = 'doctor-id';

  // User map for resolving users by ID
  late final User _currentUser;
  late final User _doctorUser;

  @override
  void initState() {
    super.initState();
    _initializeUsers();
    _chatController = InMemoryChatController();
    _loadMessages();
  }

  void _initializeUsers() {
    _currentUser = User(
      id: _currentUserId,
      name: 'You',
    );

    _doctorUser = User(
      id: _doctorId,
      name: widget.contactName,
    );
  }

  void _loadMessages() {
    final textMessage = TextMessage(
      authorId: _doctorUser.id,
      createdAt: DateTime.now(),
      id: const Uuid().v4(),
      text: 'How are you feeling today? Any new symptoms to report?',
    );

    final userReply = TextMessage(
      authorId: _currentUser.id,
      createdAt: DateTime.now(),
      id: const Uuid().v4(),
      text:
          'I\'m feeling much better, thank you! The medication is working well.',
    );

    _chatController.insertMessage(textMessage);
    _chatController.insertMessage(userReply);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Chat(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        currentUserId: _currentUserId,
        resolveUser: (userId) async {
          if (userId == _currentUserId) {
            return _currentUser;
          } else {
            return _doctorUser;
          }
        },
        chatController: _chatController,
        onMessageSend: _handleSendPressed,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0.5,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: Theme.of(context).primaryColor),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.blue,
            radius: 20,
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.contactName,
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  widget.contactRole,
                  style: TextStyle(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.phone, color: Colors.black),
          onPressed: () {
            // TODO: Implement audio call functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Audio call not implemented yet')),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.videocam, color: Colors.black),
          onPressed: () {
            // TODO: Implement video call functionality
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video call not implemented yet')),
            );
          },
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.black),
          onSelected: (String value) {
            _handleMenuSelection(value);
          },
          itemBuilder: (BuildContext context) => [
            PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: const [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete chat'),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'search',
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.grey[700]),
                  const SizedBox(width: 8),
                  const Text('Search'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'ai_service',
              child: Row(
                children: [
                  Icon(Icons.smart_toy, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('AI Service'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleSendPressed(String message) {
    final textMessage = TextMessage(
      authorId: _currentUser.id,
      createdAt: DateTime.now(),
      id: const Uuid().v4(),
      text: message,
    );

    _chatController.insertMessage(textMessage);
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'delete':
        _showDeleteDialog();
        break;
      case 'search':
        _showSearchDialog();
        break;
      case 'ai_service':
        _showAIServiceDialog();
        break;
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Chat'),
          content: const Text(
              'Are you sure you want to delete this chat? This action cannot be undone.'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Chat deleted')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Search Messages'),
          content: TextField(
            decoration: InputDecoration(
              hintText: 'Search in this conversation...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Search'),
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Search functionality not implemented yet')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showAIServiceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('AI Service'),
          content: const Text('Would you like to open the AI chat assistant?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Open AI Chat'),
              onPressed: () {
                Navigator.of(context).pop();
                // Navigate to AI chat widget
                showModalBottomSheet(
                  isScrollControlled: true,
                  context: context,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (context) => SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: AIChat(
                      role: 'patient',
                      isModal: true,
                      mode: AiChatMode.legacyGeneral,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}
