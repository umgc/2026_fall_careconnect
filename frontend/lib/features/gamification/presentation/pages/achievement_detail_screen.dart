import 'package:flutter/material.dart';

class AchievementDetailScreen extends StatelessWidget {
  final List<Map<String, dynamic>> achievements;

  const AchievementDetailScreen({super.key, required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Achievements")),
      body: ListView.builder(
        itemCount: achievements.length,
        itemBuilder: (context, index) {
          final achievement = achievements[index];

          // ✅ Handle different types of unlocked field
          final rawUnlocked = achievement['unlocked'];
          final unlocked =
              rawUnlocked == true || rawUnlocked == 'true' || rawUnlocked == 1;

          return ListTile(
            leading: Text(
              achievement['badge_icon'] ?? '🏆',
              style: const TextStyle(fontSize: 24),
            ),
            title: Text(
              achievement['title'] ?? '',
              style: TextStyle(
                fontWeight: unlocked ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            subtitle: Text(
              achievement['description'] ?? 'No description available',
              style: TextStyle(
                color: unlocked ? Colors.black54 : Colors.grey,
              ),
            ),
            trailing: Icon(
              unlocked ? Icons.check_circle : Icons.lock_outline,
              color: unlocked ? Colors.green : Colors.grey,
            ),
          );
        },
      ),
    );
  }
}
