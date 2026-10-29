import 'package:care_connect_app/widgets/page_title.dart';
import 'dart:convert';

import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/features/social/presentation/pages/my_friend_screen.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../../../providers/user_provider.dart';
import '../model/friend_request_dto.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() => _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  int? _userId;

  List<FriendRequestDto> requests = [];
  bool isLoading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_userId == null) {
      final user = Provider.of<UserProvider>(context, listen: false).user;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not logged in')),
        );
        setState(() => isLoading = false);
        return;
      }

      setState(() {
        _userId = user.id;
      });

      fetchRequests();
    }
  }

  Future<void> fetchRequests() async {
    if (_userId == null) return;

    setState(() => isLoading = true);
    final url = Uri.parse(
      '${getBackendBaseUrl()}/v1/api/friends/requests/$_userId',
    );
    final headers = await ApiService.getAuthHeaders();
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      setState(() {
        requests = data.map((json) => FriendRequestDto.fromJson(json)).toList();
        isLoading = false;
      });
    } else {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load requests')));
    }
  }

  Future<void> acceptRequest(int requestId) async {
    final url = Uri.parse('${getBackendBaseUrl()}/v1/api/friends/accept');
    final headers = await ApiService.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'requestId': requestId}),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request accepted')));
      fetchRequests();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to accept request')));
    }
  }

  Future<void> rejectRequest(int requestId) async {
    final url = Uri.parse('${getBackendBaseUrl()}/v1/api/friends/reject');
    final headers = await ApiService.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'requestId': requestId}),
    );

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Request rejected')));
      fetchRequests();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reject request')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: 'Friend Requests',
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.group),
            tooltip: 'My Friends',
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
          : requests.isEmpty
              ? const Center(child: Text('No pending requests'))
              : ListView.builder(
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    final req = requests[index];
                    return ListTile(
                      title: Text(req.fromUsername),
                      subtitle: Text('Request ID: ${req.id}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: () => acceptRequest(req.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            child: const Text('Accept'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () => rejectRequest(req.id),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Reject'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
