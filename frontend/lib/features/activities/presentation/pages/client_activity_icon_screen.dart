import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';

/// Simplified client-facing icon screen for logging activities.
class ClientActivityIconScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const ClientActivityIconScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<ClientActivityIconScreen> createState() =>
      _ClientActivityIconScreenState();
}

class _ClientActivityIconScreenState extends State<ClientActivityIconScreen> {
  List<ClientActivity> _activities = [];
  bool _loading = true;
  String? _error;
  final Set<int> _debouncedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
        if (mounted) {
          setState(() {
            _activities = activities;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load: ${res.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _onTap(ClientActivity activity) async {
    if (_debouncedIds.contains(activity.id)) return;
    setState(() => _debouncedIds.add(activity.id));

    // brief 500ms client-side debounce
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _debouncedIds.remove(activity.id));
    });

    try {
      final res = await ApiService.postClientEvent(
        clientId: widget.clientId,
        activityId: activity.id,
      );
      if (!mounted) return;
      if (res.statusCode == 429) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already logged recently')),
        );
        return;
      }
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${activity.name} logged')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to log: ${res.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tap to log activity'),
            Text(
              widget.clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _activities.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No activities enabled. Ask your caregiver to enable activities.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 200, // larger tiles for client use
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                      ),
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final a = _activities[index];
                        final disabled = _debouncedIds.contains(a.id);
                        return GestureDetector(
                          onTap: disabled ? null : () => _onTap(a),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: disabled
                                  ? theme.colorScheme.primary.withOpacity(0.15)
                                  : theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: theme.colorScheme.primary,
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.self_improvement,
                                      size: 64,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      a.name,
                                      textAlign: TextAlign.center,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
