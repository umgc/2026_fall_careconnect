import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:care_connect_app/features/activities/presentation/widgets/auth_network_image.dart';

class ClientActivitiesScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const ClientActivitiesScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ClientActivitiesScreen> createState() => _ClientActivitiesScreenState();
}

class _ClientActivitiesScreenState extends State<ClientActivitiesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ClientActivity> _allActivities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadActivities();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.getClientActivities(widget.clientId);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>?;
        final activities = (list ?? [])
            .map((e) =>
                ClientActivity.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((a) => a.enabled)
            .toList();
        setState(() {
          _allActivities = activities;
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load activities: ${res.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  List<ClientActivity> _activitiesFor(String category) {
    return _allActivities
        .where((a) => a.category.toUpperCase() == category.toUpperCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clientName),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'ADL'),
            Tab(text: 'IADL'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    ActivitiesGrid(
                      activities: _activitiesFor('ADL'),
                      clientId: widget.clientId,
                      clientName: widget.clientName,
                    ),
                    ActivitiesGrid(
                      activities: _activitiesFor('IADL'),
                      clientId: widget.clientId,
                      clientName: widget.clientName,
                    ),
                  ],
                ),
    );
  }
}

class ActivitiesGrid extends StatelessWidget {
  final List<ClientActivity> activities;
  final int clientId;
  final String clientName;

  const ActivitiesGrid({
    super.key,
    required this.activities,
    required this.clientId,
    required this.clientName,
  });

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No activities enabled. Switch to Manage Activities to enable some.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 160,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
          ),
          itemCount: activities.length,
          itemBuilder: (context, index) {
            final activity = activities[index];
            return _ActivityCard(
              activity: activity,
              onTap: () => _showLogSheet(context, activity),
            );
          },
        );
      },
    );
  }

  void _showLogSheet(BuildContext context, ClientActivity activity) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => LogActivitySheet(
        clientId: clientId,
        activity: activity,
        onLogged: () {
          Navigator.of(ctx).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Activity logged')),
          );
        },
        onError: (String message) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: Colors.red),
          );
        },
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final ClientActivity activity;
  final VoidCallback onTap;

  const _ActivityCard({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget iconWidget;
    final iconUrl = activity.customIconUrl ?? activity.defaultIconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      iconWidget = SizedBox(
        width: 64,
        height: 64,
        child: AuthNetworkImage(
          url: iconUrl,
          fallback: Icon(
            iconForActivityName(activity.name, activity.category),
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    } else {
      iconWidget = Icon(
        iconForActivityName(activity.name, activity.category),
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 12),
              Flexible(
                child: Text(
                  activity.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to log an activity (competency score, satisfaction, notes).
class LogActivitySheet extends StatefulWidget {
  final int clientId;
  final ClientActivity activity;
  final VoidCallback onLogged;
  final void Function(String message) onError;

  const LogActivitySheet({
    super.key,
    required this.clientId,
    required this.activity,
    required this.onLogged,
    required this.onError,
  });

  @override
  State<LogActivitySheet> createState() => _LogActivitySheetState();
}

class _LogActivitySheetState extends State<LogActivitySheet> {
  List<CompetencyScaleItem> _scale = [];
  bool _loadingScale = true;
  String? _scaleError;
  int? _selectedScore;
  int? _satisfaction; // 1..5 Likert emoji scale
  final _notesController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadScale();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadScale() async {
    try {
      final res = await ApiService.getCompetencyScale();
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final List<dynamic>? list = decoded is List
            ? decoded
            : (decoded is Map ? decoded['items'] as List<dynamic>? : null);
        final scale = (list ?? [])
            .map((e) => CompetencyScaleItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList();
        if (mounted) {
          setState(() {
            _scale = scale.isNotEmpty ? scale : _defaultScale();
            _scaleError =
                scale.isNotEmpty ? null : 'Using default competency scale';
            _loadingScale = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _scale = _defaultScale();
            _scaleError =
                'Using default competency scale (GET failed: ${res.statusCode})';
            _loadingScale = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _scale = _defaultScale();
          _scaleError = 'Using default competency scale (network error)';
          _loadingScale = false;
        });
      }
    }
  }

  List<CompetencyScaleItem> _defaultScale() {
    return const [
      CompetencyScaleItem(value: 1, label: 'Total Assistance'),
      CompetencyScaleItem(value: 2, label: 'Maximum Assistance'),
      CompetencyScaleItem(value: 3, label: 'Moderate Assistance'),
      CompetencyScaleItem(value: 4, label: 'Minimal Assistance'),
      CompetencyScaleItem(value: 5, label: 'Independent'),
    ];
  }

  Future<void> _submit() async {
    if (_selectedScore == null) return;
    setState(() => _submitting = true);
    try {
      final res = await ApiService.postActivityLog(
        clientId: widget.clientId,
        activityId: widget.activity.id,
        competencyScore: _selectedScore!,
        satisfactionRating: _satisfaction,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        activityName: widget.activity.name,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        widget.onLogged();
      } else {
        final body = res.body;
        widget.onError(
            'Failed to log: ${res.statusCode}${body.isNotEmpty ? " — $body" : ""}');
      }
    } catch (e) {
      widget.onError('Error: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF00897B);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.activity.name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Competency Score',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How independently did the client perform this activity?',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
              ),
              const SizedBox(height: 12),
              if (_loadingScale)
                const Center(child: CircularProgressIndicator())
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _scale.map((item) {
                    final selected = _selectedScore == item.value;
                    return Material(
                      color: selected ? teal : null,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () =>
                            setState(() => _selectedScore = item.value),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selected ? teal : Colors.grey.shade400,
                              width: selected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.value} — ${item.label}',
                            style: TextStyle(
                              color: selected ? Colors.white : null,
                              fontWeight: selected ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_scaleError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _scaleError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Client Satisfaction (optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _SatisfactionButton(
                    emoji: '😫',
                    value: 1,
                    selected: _satisfaction == 1,
                    onTap: () => setState(() => _satisfaction = 1),
                  ),
                  const SizedBox(width: 10),
                  _SatisfactionButton(
                    emoji: '😕',
                    value: 2,
                    selected: _satisfaction == 2,
                    onTap: () => setState(() => _satisfaction = 2),
                  ),
                  const SizedBox(width: 10),
                  _SatisfactionButton(
                    emoji: '😐',
                    value: 3,
                    selected: _satisfaction == 3,
                    onTap: () => setState(() => _satisfaction = 3),
                  ),
                  const SizedBox(width: 10),
                  _SatisfactionButton(
                    emoji: '🙂',
                    value: 4,
                    selected: _satisfaction == 4,
                    onTap: () => setState(() => _satisfaction = 4),
                  ),
                  const SizedBox(width: 10),
                  _SatisfactionButton(
                    emoji: '😄',
                    value: 5,
                    selected: _satisfaction == 5,
                    onTap: () => setState(() => _satisfaction = 5),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Notes (optional)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Add any notes...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed:
                    (_selectedScore != null && !_submitting) ? _submit : null,
                child: _submitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log Activity'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SatisfactionButton extends StatelessWidget {
  final String emoji;
  final int value;
  final bool selected;
  final VoidCallback onTap;

  const _SatisfactionButton({
    required this.emoji,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF00897B) : null,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? const Color(0xFF00897B) : Colors.grey.shade400,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(emoji, style: const TextStyle(fontSize: 40)),
        ),
      ),
    );
  }
}
