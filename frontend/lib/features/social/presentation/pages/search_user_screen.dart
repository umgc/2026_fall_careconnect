import 'dart:convert';

import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import '../../../../providers/user_provider.dart';
import '../model/search_user_dto.dart';

class SearchUserScreen extends StatefulWidget {
  const SearchUserScreen({super.key});

  @override
  State<SearchUserScreen> createState() => _SearchUserScreenState();
}

class _SearchUserScreenState extends State<SearchUserScreen> {
  final TextEditingController _controller = TextEditingController();
  List<SearchUserDto> results = [];
  bool isLoading = false;

  Future<void> searchUsers(int currentUserId) async {
    setState(() => isLoading = true);
    try {
      final response = await ApiService.searchUsers(
        _controller.text.trim(),
        currentUserId,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          results = (data as List)
              .map((json) => SearchUserDto.fromJson(json))
              .toList();
        });
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Search failed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
    setState(() => isLoading = false);
  }

  Future<void> sendRequest(int fromUserId, int toUserId) async {
    try {
      final response = await ApiService.sendFriendRequest(fromUserId, toUserId);
      if (response.statusCode == 201) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Friend request sent')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request failed')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserProvider>(context).user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Search Users')),
        body: const Center(child: Text('User not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Search Users',
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Search by name or email',
                suffixIcon: IconButton(
                  icon: Icon(Icons.search),
                  onPressed: () => searchUsers(user.id),
                ),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final searchUser = results[index];
                      return ListTile(
                        title: Text(searchUser.name),
                        subtitle: Text(searchUser.email),
                        trailing: ElevatedButton(
                          onPressed: () => sendRequest(user.id, searchUser.id),
                          child: Text('Add'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
