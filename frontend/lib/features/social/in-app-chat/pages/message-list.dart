import 'package:care_connect_app/features/social/in-app-chat/pages/chat-page.dart';
import 'package:care_connect_app/widgets/default_app_header.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MessagesListPage extends StatefulWidget {
  const MessagesListPage({super.key});

  @override
  State<MessagesListPage> createState() => _MessagesListPageState();
}

class _MessagesListPageState extends State<MessagesListPage> {
  // Live search
  final TextEditingController _searchController = TextEditingController();

  // All conversations (built from local stored messages)
  List<_Conversation> _conversations = [];
  // Filtered view
  List<_Conversation> _filtered = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = _conversations
          .where((c) =>
              c.name.toLowerCase().contains(q) ||
              c.role.toLowerCase().contains(q))
          .toList();
    });
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);

    // Pull the same local store that MessagingService uses: key = 'local_messages'
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('local_messages');

    final List<_Conversation> items = [];

    if (jsonString != null && jsonString.isNotEmpty) {
      final Map<String, dynamic> map = jsonDecode(jsonString);

      // map: { "<userA>_<userB>": [ {message map}, ... ] }
      map.forEach((convKey, list) {
        if (list is List && list.isNotEmpty) {
          final last = Map<String, dynamic>.from(list.last as Map);

          final String senderName =
              (last['senderName'] ?? 'Unknown').toString();
          final String lastMessage = (last['message'] ?? '').toString();
          final String role = (last['messageType'] ?? 'Care Team').toString();
          final DateTime ts =
              DateTime.tryParse((last['timestamp'] ?? '').toString()) ??
                  DateTime.now();
          final bool hasUnread = !(last['read'] ?? false);

          // Build a conversation row using the last entry
          items.add(
            _Conversation(
              id: convKey,
              name: senderName,
              role: role,
              lastMessage: lastMessage,
              timestamp: ts,
              hasUnread: hasUnread,
              // Simple color seed so avatars are stable but not all blue
              colorSeed: senderName,
            ),
          );
        }
      });

      // Newest first
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }

    setState(() {
      _conversations = items;
      _filtered = items;
      _isLoading = false;
    });
  }

  Future<void> _deleteConversation(String id) async {
    // Remove from in-memory lists
    setState(() {
      _conversations.removeWhere((c) => c.id == id);
      _filtered.removeWhere((c) => c.id == id);
    });

    // Remove from local store (same key MessagingService uses)
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('local_messages');
    if (jsonString != null && jsonString.isNotEmpty) {
      final Map<String, dynamic> map = jsonDecode(jsonString);
      map.remove(id);
      await prefs.setString('local_messages', jsonEncode(map));
    }
  }

  // Small helper so you don’t need the timeago package
  String _relativeTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);

    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    // fallback date for older items
    return '${t.month}/${t.day}/${t.year}';
  }

  Color _avatarColorFromSeed(String seed) {
    // quick stable color from name
    final code = seed.runes.fold<int>(0, (p, c) => p + c);
    final colors = [
      Colors.blue,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.indigo,
      Colors.green,
      Colors.brown,
    ];
    return colors[code % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: DefaultAppHeader(),
      body: Column(
        children: [
          Container(
            color:
                Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .1),
            margin: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                hintStyle: TextStyle(color: Colors.grey[500]),
                prefixIcon: Icon(Icons.search, color: Colors.grey[500]),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              ),
              // live filter as you type (the listener also covers this)
              onChanged: (_) {},
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No Messages to Display',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final c = _filtered[i];
                          return Dismissible(
                            key: ValueKey(c.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (_) => _deleteConversation(c.id),
                            child: _buildMessageItem(
                              context,
                              c.name,
                              c.role,
                              c.lastMessage,
                              _relativeTime(c.timestamp),
                              _avatarColorFromSeed(c.colorSeed),
                              hasUnread: c.hasUnread,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // ——— your original row builder kept EXACTLY the same API ———
  Widget _buildMessageItem(
    BuildContext context,
    String name,
    String role,
    String lastMessage,
    String time,
    Color avatarColor, {
    bool hasUnread = false,
  }) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              contactName: name,
              contactRole: role,
            ),
          ),
        );
      },
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: .01),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: avatarColor,
              radius: 24,
              child: const Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        time,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    role,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conversation {
  final String id;
  final String name;
  final String role;
  final String lastMessage;
  final DateTime timestamp;
  final bool hasUnread;
  final String colorSeed;

  _Conversation({
    required this.id,
    required this.name,
    required this.role,
    required this.lastMessage,
    required this.timestamp,
    required this.hasUnread,
    required this.colorSeed,
  });
}
