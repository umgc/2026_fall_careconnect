import 'package:care_connect_app/widgets/page_title.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../providers/user_provider.dart';
import '../model/conversation_preview_dto.dart';
import 'chat_room_screen.dart';
import 'my_friend_screen.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  int? _userId;
  List<ConversationPreviewDto> inbox = [];
  bool isLoading = true;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_initialized) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in')),
        );
        return;
      }

      _userId = user.id;
      fetchInbox();
      _initialized = true;
    }
  }

  Future<void> fetchInbox() async {
    setState(() => isLoading = true);
    try {
      final data = await ApiService.getInbox(_userId!);
      setState(() {
        inbox = (data)
            .map((json) => ConversationPreviewDto.fromJson(json))
            .toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load inbox: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userId == null) {
      return Scaffold(
        // appBar: AppBar(title: const Text('Messages')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'Contacts',
            onPressed: () {
              Navigator.push(
                context,
                TitledMaterialPageRoute(
                  title: 'My Friends',
                  builder: (_) => MyFriendsScreen()),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : inbox.isEmpty
              ? const Center(child: Text('No messages yet'))
              : ListView.builder(
                  itemCount: inbox.length,
                  itemBuilder: (context, index) {
                    final convo = inbox[index];
                    return ListTile(
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              convo.peerName,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: convo.hasUnread
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (convo.relationshipLabel.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                convo.relationshipLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blueGrey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        convo.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: convo.hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            convo.timestamp
                                .toLocal()
                                .toString()
                                .substring(0, 16),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                          if (convo.hasUnread)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          TitledMaterialPageRoute(
                            title: 'Conversation',
                            builder: (_) => ChatRoomScreen(
                              peerUserId: convo.peerId,
                              peerName: convo.peerName,
                            ),
                          ),
                        );
                        if (mounted) fetchInbox();
                      },
                    );
                  },
                ),
    );
  }
}
