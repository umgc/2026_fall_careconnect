import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';

class BehavioralIncidentFormScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const BehavioralIncidentFormScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<BehavioralIncidentFormScreen> createState() =>
      _BehavioralIncidentFormScreenState();
}

class _BehavioralIncidentFormScreenState
    extends State<BehavioralIncidentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _behaviorController = TextEditingController();
  final _triggerController = TextEditingController();
  DateTime _occurredAt = DateTime.now();
  bool _submitting = false;

  @override
  void dispose() {
    _behaviorController.dispose();
    _triggerController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null) {
      setState(() => _occurredAt = DateTime(date.year, date.month, date.day,
          _occurredAt.hour, _occurredAt.minute));
    } else {
      setState(() => _occurredAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final res = await ApiService.postBehavioralIncident(
        clientId: widget.clientId,
        observedBehavior: _behaviorController.text.trim(),
        occurredAt: _occurredAt,
        triggerNotes: _triggerController.text.trim().isEmpty
            ? null
            : _triggerController.text.trim(),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Behavioral incident logged')),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => BehavioralIncidentHistoryScreen(
              clientId: widget.clientId,
              clientName: widget.clientName,
            ),
          ),
        );
      } else {
        if (!mounted) return;
        final body = res.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to log incident: ${res.statusCode}${body.isNotEmpty ? " — $body" : ""}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = DateFormat.yMMMd().add_jm().format(_occurredAt);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Log Behavior'),
            Text(
              widget.clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _behaviorController,
                decoration: const InputDecoration(
                  labelText: 'Observed Behavior',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please describe the observed behavior';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text(
                'When did this occur?',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _pickDateTime,
                icon: const Icon(Icons.schedule),
                label: Text(dateStr),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _triggerController,
                decoration: const InputDecoration(
                  labelText: 'Possible causes or context — optional',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const Spacer(),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log Behavior'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BehavioralIncidentHistoryScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const BehavioralIncidentHistoryScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<BehavioralIncidentHistoryScreen> createState() =>
      _BehavioralIncidentHistoryScreenState();
}

class _BehavioralIncidentHistoryScreenState
    extends State<BehavioralIncidentHistoryScreen> {
  List<BehavioralIncidentEntry> _incidents = [];
  bool _loading = true;
  String? _error;

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
      final res = await ApiService.getBehavioralIncidents(widget.clientId);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>?;
        final incidents = (list ?? [])
            .map((e) => BehavioralIncidentEntry.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList();
        if (mounted) {
          setState(() {
            _incidents = incidents;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Behavioral history'),
            Text(
              widget.clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
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
                : _incidents.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No behavioral incidents logged yet.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _incidents.length,
                        itemBuilder: (context, index) {
                          final inc = _incidents[index];
                          final dateStr = DateFormat.yMMMd()
                              .add_jm()
                              .format(inc.occurredAt);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(
                                inc.observedBehavior,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(height: 4),
                                  Text(
                                    dateStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  if (inc.triggerNotes != null &&
                                      inc.triggerNotes!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      inc.triggerNotes!,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                              isThreeLine: true,
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
