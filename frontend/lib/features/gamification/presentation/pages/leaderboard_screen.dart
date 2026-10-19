import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:care_connect_app/config/env_constant.dart';
import 'package:care_connect_app/services/api_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  List<dynamic> leaderboard = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchLeaderboard();
  }

  Future<void> fetchLeaderboard() async {
    final uri = Uri.parse('${getBackendBaseUrl()}/v1/api/users/leaderboard');

    try {
      final headers = await ApiService.getAuthHeaders();
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        setState(() {
          leaderboard = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        print("Failed to fetch leaderboard: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching leaderboard: $e");
    }
  }

  String getMedalEmoji(int index) {
    switch (index) {
      case 0:
        return '🥇';
      case 1:
        return '🥈';
      case 2:
        return '🥉';
      default:
        return '#${index + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        backgroundColor: Colors.blue.shade900,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : leaderboard.isEmpty
              ? const Center(child: Text('No leaderboard data available.'))
              : ListView.builder(
                  itemCount: leaderboard.length,
                  itemBuilder: (context, index) {
                    final user = leaderboard[index];
                    final medal = getMedalEmoji(index);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      elevation: 2,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: user['profileImageUrl'] != null &&
                                  user['profileImageUrl'].toString().isNotEmpty
                              ? NetworkImage(user['profileImageUrl'])
                              : null,
                          child: user['profileImageUrl'] == null ||
                                  user['profileImageUrl'].toString().isEmpty
                              ? const Icon(Icons.person)
                              : null,
                        ),
                        title: Text(
                          user['name'] ?? 'Anonymous',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                            'XP: ${user['xp']}  |  Level: ${user['level']}'),
                        trailing: Text(
                          medal,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: index == 0
                                ? Colors.amber
                                : index == 1
                                    ? Colors.grey
                                    : index == 2
                                        ? Colors.brown
                                        : Colors.black54,
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
