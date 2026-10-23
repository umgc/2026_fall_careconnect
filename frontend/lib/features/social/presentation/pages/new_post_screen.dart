import 'dart:convert';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;

import '../../../../providers/user_provider.dart';
import '../model/PostWithCommentCountDto.dart';

class NewPostScreen extends StatefulWidget {
  const NewPostScreen({super.key});

  @override
  State<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends State<NewPostScreen> {
  final TextEditingController _contentController = TextEditingController();
  bool isPosting = false;

  Future<void> submitPost(int userId) async {
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post content cannot be empty')),
      );
      return;
    }

    setState(() => isPosting = true);
    try {
      final uri = Uri.parse('${getBackendBaseUrl()}/v1/api/feed/create');
      final headers = await ApiService.getAuthHeaders();

      headers['Content-Type'] = 'application/json';

      final body = jsonEncode({
        'userId': userId,
        'content': content,
      });

      final response = await http.post(uri, headers: headers, body: body);

      print('Create post status: ${response.statusCode}');
      print('Create post body: ${response.body}');

      setState(() => isPosting = false);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        final newPost = PostWithCommentCountDto.fromJson(json);
        Navigator.pop(context, newPost);
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${response.body}')));
      }
    } catch (e) {
      setState(() => isPosting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exception: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Create New Post'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: Text('User not logged in')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Post'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextFormField(
              controller: _contentController,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'What’s on your mind?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isPosting ? null : () => submitPost(user.id),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade900,
              ),
              child: isPosting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}
