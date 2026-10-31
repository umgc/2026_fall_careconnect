import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/gamification_service.dart';
import 'leaderboard_screen.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'achievement_detail_screen.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';

class GamificationScreen extends StatefulWidget {
  const GamificationScreen({super.key});

  @override
  State<GamificationScreen> createState() => _GamificationScreenState();
}

final List<String> motivationalMessages = [
  "You're doing great — keep going! 💪",
  "Small steps every day lead to big results.",
  "Believe in yourself and all that you are.",
  "Progress, not perfection.",
  "One day at a time — you got this!",
];

class _GamificationScreenState extends State<GamificationScreen> {
  int level = 1;
  int xp = 0;
  int xpTarget = 50;
  List<Map<String, dynamic>> allAchievements = [];
  List<Map<String, dynamic>> earnedAchievements = [];
  bool isLoading = true;

  late ConfettiController _confettiController;
  int userId = 1;
  late SharedPreferences _prefs;
  int previousAchievementCount = 0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    initializePrefsAndLoad();
  }

  late String dailyMessage;

  void pickDailyMessage() {
    final l10n = AppLocalizations.of(context)!;
    final messages = [
      l10n.gamificationDailyMessage1,
      l10n.gamificationDailyMessage2,
      l10n.gamificationDailyMessage3,
      l10n.gamificationDailyMessage4,
      l10n.gamificationDailyMessage5,
    ];
    dailyMessage = messages[DateTime.now().day % messages.length];
  }

  Future<void> initializePrefsAndLoad() async {
    _prefs = await SharedPreferences.getInstance();
    userId = int.tryParse(_prefs.getString('userId') ?? '') ?? 1;

    previousAchievementCount = _prefs.getInt('achievement_count') ?? 0;
    await loadGamificationData();
    pickDailyMessage();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> loadGamificationData() async {
    try {
      final progress = await GamificationService.fetchXPProgress(userId);
      final earned = await GamificationService.fetchAchievements(userId);
      final all = await GamificationService.fetchAllAchievements(userId);

      // Confetti trigger
      if (earned.length > previousAchievementCount) {
        _confettiController.play();
        previousAchievementCount = earned.length;
        await _prefs.setInt('achievement_count', earned.length);
      }
      print("Earned Achievements: $earned");
      print("All Achievements: $all");

      List<Map<String, dynamic>> merged = (all).map<Map<String, dynamic>>((a) {
        final match = earned.firstWhere(
          (e) =>
              (e['achievement']?['title']?.toString().trim().toLowerCase() ??
                  '') ==
              (a['title']?.toString().trim().toLowerCase() ?? ''),
          orElse: () => null,
        );
        return {...a, 'unlocked': match != null};
      }).toList();
      print("Earned Achievements: $earned");
      print("All Achievements: $all");

      setState(() {
        level = progress['level'];
        xp = progress['xp'];
        earnedAchievements = List<Map<String, dynamic>>.from(earned);
        allAchievements = merged;
        xpTarget = level * 50;
        isLoading = false;
      });
    } catch (e) {
      print("Error loading gamification data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: AppBarHelper.createAppBar(
        context,
        title: l10n.gamificationTitle,
        additionalActions: [
          IconButton(
            icon: const Icon(Icons.emoji_events),
            onPressed: () {
              Navigator.push(
                context,
                TitledMaterialPageRoute(
                  title: 'Achievement Details',
                  builder: (_) =>
                      AchievementDetailScreen(achievements: allAchievements),
                ),
              );
            },
          ),
        ],
      ),
      drawer: const CommonDrawer(currentRoute: '/gamification'),
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),
                      Text(
                        l10n.gamificationHeading,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 30),
                      Icon(Icons.shield, size: 80, color: colorScheme.primary),
                      const SizedBox(height: 12),
                      Text(
                        l10n.gamificationLevel(level),
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          dailyMessage,
                          style: textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: (xp % xpTarget) / xpTarget,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        color: colorScheme.primary,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '$xp / $xpTarget XP',
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          l10n.gamificationAchievements,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: ListView.builder(
                          itemCount: allAchievements
                              .where((a) => a['unlocked'] == true)
                              .length,
                          itemBuilder: (context, index) {
                            final unlockedAchievements = allAchievements
                                .where((a) => a['unlocked'] == true)
                                .toList();
                            final achievement = unlockedAchievements[index];
                            return buildAchievement(achievement);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            TitledMaterialPageRoute(
                              title: 'Leaderboard',
                                builder: (_) => const LeaderboardScreen()),
                          );
                        },
                        icon: const Icon(Icons.leaderboard),
                        label: Text(l10n.gamificationLeaderboard),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.secondary,
                          foregroundColor: colorScheme.onSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 2,
              emissionFrequency: 0.05,
              numberOfParticles: 25,
              maxBlastForce: 20,
              minBlastForce: 5,
              gravity: 0.3,
              shouldLoop: false,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAchievement(Map<String, dynamic> achievement) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            TitledMaterialPageRoute(
              title: 'Achievement Details',
              builder: (_) => AchievementDetailScreen(
                achievements: allAchievements,
              ),
            ),
          );
        },
        child: Row(
          children: [
            Expanded(
              child: Text(
                achievement['title'] ??
                    AppLocalizations.of(context)!
                        .gamificationUnnamedAchievement,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: achievement['unlocked'] == true
                    ? Colors.green.shade300
                    : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                achievement['unlocked'] == true
                    ? Icons.check
                    : Icons.lock_outline,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
