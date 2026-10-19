import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:care_connect_app/features/activities/presentation/pages/client_activities_screen.dart';

/// Embeddable "Activities" section for the Health tab: ADL / IADL tabs and grid.
/// Use inside a ListView or similar; [contentHeight] constrains the tab content for scrolling.
class ClientActivitiesSection extends StatefulWidget {
  final int clientId;
  final String clientName;

  /// Height for the tab content area when embedded (e.g. in a ListView). If null, expands.
  final double? contentHeight;

  const ClientActivitiesSection({
    super.key,
    required this.clientId,
    required this.clientName,
    this.contentHeight = 360,
  });

  @override
  State<ClientActivitiesSection> createState() =>
      _ClientActivitiesSectionState();
}

class _ClientActivitiesSectionState extends State<ClientActivitiesSection>
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
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.self_improvement,
                    color: theme.colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Activities',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else ...[
              TabBar(
                controller: _tabController,
                labelColor: theme.colorScheme.primary,
                tabs: const [
                  Tab(text: 'ADL'),
                  Tab(text: 'IADL'),
                ],
              ),
              SizedBox(
                height: widget.contentHeight ?? 360,
                child: TabBarView(
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
              ),
            ],
          ],
        ),
      ),
    );
  }
}
