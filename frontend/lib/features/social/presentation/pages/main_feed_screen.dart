import 'package:care_connect_app/widgets/page_title.dart';
import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/shared/widgets/user_avatar.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../model/PostWithCommentCountDto.dart';

import 'chat_inbox_screen.dart';
import 'comment_screen.dart';
import 'friend_requests_screen.dart';
import 'new_post_screen.dart';
import 'search_user_screen.dart';

class MainFeedScreen extends StatefulWidget {
  final int userId;
  const MainFeedScreen({super.key, required this.userId});

  @override
  State<MainFeedScreen> createState() => _MainFeedScreenState();
}

class _MainFeedScreenState extends State<MainFeedScreen> {
  List<PostWithCommentCountDto> posts = [];
  bool isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    if (widget.userId == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.socialFeedInvalidUser),
          ),
        );
      });
      setState(() => isLoading = false);
    } else {
      fetchFeed();
      _pollingTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => fetchFeed(silent: true),
      );
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchFeed({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);

    try {
      final headers = await ApiService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('${ApiConstants.feed}/friends-feed'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final newPosts =
            data.map((json) => PostWithCommentCountDto.fromJson(json)).toList();

        // Update only if different to prevent unnecessary rebuilds
        if (!listEquals(posts, newPosts)) {
          setState(() {
            posts = newPosts;
            isLoading = false;
          });
        } else if (!silent) {
          setState(() => isLoading = false);
        }
      } else {
        throw Exception('Failed to load feed');
      }
    } catch (e) {
      if (!silent) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.socialFeedLoadError(e.toString()),
            ),
          ),
        );
      }
    }
  }

  Widget buildPostCard(PostWithCommentCountDto post) {
    final String? imageUrl = post.imageUrl;
    final String backendBaseUrl = getBackendBaseUrl();
    final resolvedUrl = imageUrl != null && imageUrl.isNotEmpty
        ? '$backendBaseUrl$imageUrl'
        : null;

    return InkWell(
      onTap: () {
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Post Comments',
              builder: (_) => CommentScreen(postId: post.id),
            ),
          );
          },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  UserAvatar(imageUrl: null, radius: 20),
                  const SizedBox(width: 10),
                  Text(
                    post.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    post.createdAt.toIso8601String().split('T').first,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(post.content),
              if (resolvedUrl != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    resolvedUrl,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Divider(height: 1),
              TextButton.icon(
                onPressed: () {
                    Navigator.push(
                      context,
                      TitledMaterialPageRoute(
                        title: 'Post Comments',
                        builder: (_) => CommentScreen(postId: post.id),
                      ),
                    );
                },
                icon: const Icon(Icons.comment, size: 18),
                label: Text(
                  AppLocalizations.of(context)!
                      .socialFeedComments(post.commentCount),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      drawer: CommonDrawer(currentRoute: '/social-feed'),
      appBar: AppBarHelper.createAppBar(
        context,
        title: l10n.socialFeedTitle,
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchFeed,
              child: posts.isEmpty
                  ? Center(child: Text(l10n.socialFeedEmpty))
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        return buildPostCard(posts[index]);
                      },
                    ),
            ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: AppTheme.primary, // Using centralized theme color
        child: Container(
          height: 56.0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon:
                          const Icon(Icons.person_search, color: Colors.white),
                      tooltip: l10n.socialFeedAddFriend,
                      onPressed: () {
                        Navigator.push(
                          context,
                          TitledMaterialPageRoute(
                            title: 'Search User',
                              builder: (_) =>
                                  SearchUserScreen()
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_add, color: Colors.white),
                      tooltip: l10n.socialFeedFriendRequests,
                      onPressed: () {
                        Navigator.push(
                          context,
                          TitledMaterialPageRoute(
                            title: 'Friend Requests',
                              builder: (_) =>
                                  FriendRequestsScreen()
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat, color: Colors.white),
                      tooltip: l10n.socialFeedMessages,
                      onPressed: () {
                        Navigator.push(
                          context,
                          TitledMaterialPageRoute(
                            title: 'Chat Inbox',
                            builder: (_) => ChatInboxScreen()),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: l10n.socialFeedCreatePost,
                      onPressed: () async {
                        final result = await Navigator.push(
                          context,
                          TitledMaterialPageRoute(
                            title: 'New Post',
                              builder: (_) =>
                                  NewPostScreen()
                          ),
                        );
                        if (result is PostWithCommentCountDto) {
                          setState(() {
                            posts.insert(0, result);
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
