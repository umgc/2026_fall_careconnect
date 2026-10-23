import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';
import 'package:care_connect_app/features/activities/presentation/widgets/auth_network_image.dart';
import 'package:care_connect_app/features/activities/presentation/pages/client_activities_screen.dart';
import 'package:care_connect_app/features/activities/services/local_activity_prefs_store.dart';

/// ADL or IADL category screen with Log Activities and Manage Activities modes.
class ClientCategoryActivitiesScreen extends StatefulWidget {
  final int clientId;
  final String clientName;
  final String category; // 'ADL' | 'IADL'

  const ClientCategoryActivitiesScreen({
    super.key,
    required this.clientId,
    required this.clientName,
    required this.category,
  });

  @override
  State<ClientCategoryActivitiesScreen> createState() =>
      _ClientCategoryActivitiesScreenState();
}

class _ClientCategoryActivitiesScreenState
    extends State<ClientCategoryActivitiesScreen> {
  static const int _modeLog = 0;
  static const int _modeManage = 1;
  int _modeIndex = _modeLog;

  List<ClientActivity> _clientActivities = [];
  List<Activity> _allActivities = [];
  bool _loading = true;
  String? _error;
  bool _logInvalidated = true;
  final Map<int, bool> _toggleLoading = {};
  final Map<int, String?> _customIconUrl = {};

  @override
  void initState() {
    super.initState();
    _loadForCurrentMode();
  }

  Future<void> _loadForCurrentMode() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (_modeIndex == _modeLog) {
      await _loadClientActivities();
      setState(() => _logInvalidated = false);
    } else {
      await _loadManageData();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadClientActivities() async {
    try {
      final res = await ApiService.getClientActivities(widget.clientId);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>?;
        final activities = (list ?? [])
            .map((e) =>
                ClientActivity.fromJson(Map<String, dynamic>.from(e as Map)))
            .where((a) =>
                a.category.toUpperCase() == widget.category.toUpperCase())
            .toList();
        // If backend returns none, fall back to locally-enabled defaults so
        // caregivers can immediately see toggled-on activities in Log mode.
        if (activities.isEmpty) {
          final enabledNames = await LocalActivityPrefsStore.getEnabledNames(
            clientId: widget.clientId,
            category: widget.category,
          );
          final defaults = _defaultActivitiesForCategory(widget.category);
          final enabled = defaults
              .where((a) => enabledNames.any(
                    (n) => n.toLowerCase() == a.name.toLowerCase(),
                  ))
              .map(
                (a) => ClientActivity(
                  id: a.id,
                  name: a.name,
                  category: a.category,
                  defaultIconUrl: a.defaultIconUrl,
                  enabled: true,
                ),
              )
              .toList();
          if (mounted) {
            setState(() {
              _clientActivities = enabled;
            });
          }
          return;
        }
        if (mounted) {
          setState(() {
            _clientActivities = activities;
          });
        }
      } else {
        if (mounted)
          setState(() => _error = 'Failed to load: ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    }
  }

  Future<void> _loadManageData() async {
    try {
      final res = await ApiService.getActivities(category: widget.category);
      List<Activity> all = [];
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>?;
        all = (list ?? [])
            .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      if (all.isEmpty) {
        all = _defaultActivitiesForCategory(widget.category);
      }

      final clientRes = await ApiService.getClientActivities(widget.clientId);
      final Map<int, ClientActivity> configMap = {};
      if (clientRes.statusCode == 200) {
        final clientList = jsonDecode(clientRes.body) as List<dynamic>?;
        for (final e in clientList ?? []) {
          final a =
              ClientActivity.fromJson(Map<String, dynamic>.from(e as Map));
          if (a.category.toUpperCase() == widget.category.toUpperCase()) {
            configMap[a.id] = a;
          }
        }
      }

      if (mounted) {
        setState(() {
          _allActivities = all;
          _clientActivities = configMap.values.toList();
          for (final a in _clientActivities) {
            _customIconUrl[a.id] = a.customIconUrl;
          }
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allActivities = _defaultActivitiesForCategory(widget.category);
        _error = null;
      });
    }
  }

  List<Activity> _defaultActivitiesForCategory(String category) {
    final c = category.toUpperCase().trim();
    if (c == 'ADL') {
      const names = <String>[
        'Bathing',
        'Dressing',
        'Toileting',
        'Transferring',
        'Mobility/Ambulation',
        'Eating',
        'Personal Hygiene & Grooming',
      ];
      return List<Activity>.generate(
        names.length,
        (i) => Activity(id: i + 1, name: names[i], category: 'ADL'),
      );
    }
    if (c == 'IADL') {
      const names = <String>[
        'Meal Preparation',
        'Housekeeping',
        'Laundry',
        'Medication Management',
        'Money Management',
        'Transportation',
        'Communication',
        'Community Participation',
        'Shopping',
        'Safety Awareness',
      ];
      return List<Activity>.generate(
        names.length,
        (i) => Activity(id: i + 1, name: names[i], category: 'IADL'),
      );
    }
    return const <Activity>[];
  }

  List<ClientActivity> get _enabledForLog => _clientActivities
      .where((a) =>
          a.enabled &&
          a.category.toUpperCase() == widget.category.toUpperCase())
      .toList();

  bool _isEnabledForClient(int activityId) {
    return _clientActivities.any((a) => a.id == activityId && a.enabled);
  }

  String? _customIconFor(int activityId) => _customIconUrl[activityId];

  Future<void> _onToggle(int activityId, bool enabled) async {
    setState(() => _toggleLoading[activityId] = true);
    try {
      final res = await ApiService.putClientActivityConfig(
        widget.clientId,
        activityId,
        isEnabled: enabled,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (enabled) {
          final act = _allActivities.firstWhere((a) => a.id == activityId);
          setState(() {
            _clientActivities.add(ClientActivity(
              id: act.id,
              name: act.name,
              category: act.category,
              defaultIconUrl: act.defaultIconUrl,
              customIconUrl: _customIconUrl[activityId],
              enabled: true,
            ));
          });
          await LocalActivityPrefsStore.setEnabled(
            clientId: widget.clientId,
            category: widget.category,
            activityName: act.name,
            enabled: true,
          );
        } else {
          String? removedName;
          setState(() {
            final idx = _clientActivities.indexWhere((a) => a.id == activityId);
            if (idx >= 0) {
              removedName = _clientActivities[idx].name;
              _clientActivities.removeAt(idx);
            }
          });
          if (removedName != null) {
            await LocalActivityPrefsStore.setEnabled(
              clientId: widget.clientId,
              category: widget.category,
              activityName: removedName!,
              enabled: false,
            );
          }
        }
        setState(() => _logInvalidated = true);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update: ${res.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _toggleLoading.remove(activityId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${widget.category} Activities'),
            Text(
              widget.clientName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.8),
                  ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _segment('Log Activities', _modeLog),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _segment('Manage Activities', _modeManage),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                _modeIndex == _modeLog ? _buildLogMode() : _buildManageMode(),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, int index) {
    final selected = _modeIndex == index;
    return Material(
      color: selected ? const Color(0xFF00897B) : null,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () {
          setState(() {
            _modeIndex = index;
            if (index == _modeManage || _logInvalidated) _loadForCurrentMode();
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? const Color(0xFF00897B) : Colors.grey.shade400,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogMode() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final enabled = _enabledForLog;
    if (enabled.isEmpty) {
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
    return ActivitiesGrid(
      activities: enabled,
      clientId: widget.clientId,
      clientName: widget.clientName,
    );
  }

  Widget _buildManageMode() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _allActivities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_allActivities.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No activities defined for this category.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _allActivities.length,
      itemBuilder: (context, index) {
        final act = _allActivities[index];
        final enabled = _isEnabledForClient(act.id);
        final loading = _toggleLoading[act.id] == true;
        final customIcon = _customIconFor(act.id);
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: SizedBox(
              width: 48,
              height: 48,
              child: _iconWidget(act, customIcon),
            ),
            title: Text(
              act.name,
              style: TextStyle(
                decoration: enabled ? null : TextDecoration.lineThrough,
                decorationColor: Colors.grey,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: enabled,
                    onChanged: (v) => _onToggle(act.id, v),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _iconWidget(Activity act, String? customIconUrl) {
    final url = customIconUrl ?? act.defaultIconUrl;
    if (url != null && url.isNotEmpty) {
      return AuthNetworkImage(
        url: url,
        fallback: Icon(
          iconForActivityName(act.name, act.category),
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return Icon(
      iconForActivityName(act.name, act.category),
      size: 48,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}
