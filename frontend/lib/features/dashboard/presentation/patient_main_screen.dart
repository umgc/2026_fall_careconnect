import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/widgets/common_drawer.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/app_bar_helper.dart';

class PatientDashboard extends StatefulWidget {
  final int userId;
  const PatientDashboard({super.key, required this.userId});

  @override
  State<PatientDashboard> createState() => _PatientDashboardState();
}

class _PatientDashboardState extends State<PatientDashboard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  final caregivers = [
    {
      'name': 'Arnold Simpson',
      'status': 'Available',
      'lastSeen': '15 mins ago',
    },
    {'name': 'Ryan Simpson', 'status': 'Available', 'lastSeen': '25 mins ago'},
    {
      'name': 'Jackie Simpson',
      'status': 'Available',
      'lastSeen': '20 mins ago',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarHelper.createAppBar(context, title: 'Patient Dashboard'),
      drawer: const CommonDrawer(currentRoute: '/dashboard'),
      body: SafeArea(
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Consumer<UserProvider>(
                  builder: (context, userProvider, child) {
                    final userName = userProvider.user?.name ?? 'Patient';
                    return Text(
                      'Good Morning !!!  $userName',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'How are you feeling today?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      EmojiLabel(emoji: '😡', label: 'Angry'),
                      EmojiLabel(emoji: '😐', label: 'Sad'),
                      EmojiLabel(emoji: '😫', label: 'Tired'),
                      EmojiLabel(emoji: '😨', label: 'Fearful'),
                      EmojiLabel(emoji: '😑', label: 'Neutral'),
                      EmojiLabel(emoji: '😊', label: 'Happy'),
                    ],
                  ),
                ),
                const Divider(height: 30, thickness: 2),
                Text(
                  'How is your pain today?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 500;

                    if (isMobile) {
                      // Use horizontal scrolling for mobile to prevent overflow
                      return const SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            PainEmojiLabel(emoji: '😀', label: '1\nNo Pain'),
                            SizedBox(width: 12),
                            PainEmojiLabel(emoji: '🙂', label: '2\nMild'),
                            SizedBox(width: 12),
                            PainEmojiLabel(emoji: '😐', label: '3\nModerate'),
                            SizedBox(width: 12),
                            PainEmojiLabel(emoji: '😣', label: '4\nSevere'),
                            SizedBox(width: 12),
                            PainEmojiLabel(emoji: '😭', label: '5\nWorst Pain'),
                          ],
                        ),
                      );
                    } else {
                      // Use traditional row layout for larger screens
                      return const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          PainEmojiLabel(emoji: '😀', label: '1\nNo Pain'),
                          PainEmojiLabel(emoji: '🙂', label: '2\nMild'),
                          PainEmojiLabel(emoji: '😐', label: '3\nModerate'),
                          PainEmojiLabel(emoji: '😣', label: '4\nSevere'),
                          PainEmojiLabel(emoji: '😭', label: '5\nWorst Pain'),
                        ],
                      );
                    }
                  },
                ),
                const Divider(height: 30, thickness: 2),
                ...caregivers.map(
                  (c) => CaregiverCard(
                    name: c['name']!,
                    status: c['status']!,
                    lastInteraction: c['lastSeen']!,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).dividerTheme.color ??
                            Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.medication,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Medication Tracker',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                '3 medications scheduled today',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).dividerTheme.color ??
                            Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.restaurant_menu,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Diet Tracking',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Add today\'s meals',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context).hintColor,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Theme.of(context).iconTheme.color,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmojiLabel extends StatelessWidget {
  final String emoji;
  final String label;

  const EmojiLabel({super.key, required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color ??
                  Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerTheme.color ??
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.2),
              ),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class PainEmojiLabel extends StatelessWidget {
  final String emoji;
  final String label;

  const PainEmojiLabel({super.key, required this.emoji, required this.label});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 500;

    return Container(
      constraints: BoxConstraints(
        minWidth: isMobile ? 50 : 60,
        maxWidth: isMobile ? 65 : 80,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: TextStyle(fontSize: isMobile ? 20 : 24)),
          SizedBox(height: isMobile ? 2 : 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: isMobile ? 9 : 11,
                  height: 1.1,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class CaregiverCard extends StatelessWidget {
  final String name;
  final String status;
  final String lastInteraction;

  const CaregiverCard({
    super.key,
    required this.name,
    required this.status,
    required this.lastInteraction,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Theme.of(context).dividerTheme.color ??
              Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Text(
                name.substring(0, 1),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: status == 'Available'
                              ? Theme.of(context).colorScheme.secondary
                              : Theme.of(context).disabledColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        status,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                  onPressed: () {},
                  icon: const Icon(Icons.videocam, size: 16),
                  label: const Text('Call'),
                ),
                const SizedBox(height: 4),
                Text(
                  lastInteraction,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
