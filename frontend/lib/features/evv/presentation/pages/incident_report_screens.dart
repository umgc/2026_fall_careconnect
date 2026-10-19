import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/features/activities/models/client_activity_model.dart';

class IncidentReportWizardScreen extends StatefulWidget {
  final int clientId;
  final String clientName;

  const IncidentReportWizardScreen({
    super.key,
    required this.clientId,
    required this.clientName,
  });

  @override
  State<IncidentReportWizardScreen> createState() =>
      _IncidentReportWizardScreenState();
}

class _IncidentDraft {
  String? incidentType; // FALL, BEHAVIORAL_CRISIS, ...
  DateTime occurredAt = DateTime.now();
  String? location;
  String? triggerNotes;
  final List<String> actions = [];
  String? otherAction;
  String? outcome;
}

class _IncidentReportWizardScreenState
    extends State<IncidentReportWizardScreen> {
  int _step = 0;
  final _draft = _IncidentDraft();
  bool _submitting = false;

  final _locationController = TextEditingController();
  final _triggerController = TextEditingController();
  final _outcomeController = TextEditingController();
  final _otherActionController = TextEditingController();

  final Map<String, bool> _actionChecks = {
    'Called supervisor': false,
    'Contacted emergency services (911)': false,
    'Applied first aid': false,
    'Notified family': false,
    'Completed safety check': false,
    'Moved client to safe location': false,
    'Completed documentation': false,
  };

  @override
  void dispose() {
    _locationController.dispose();
    _triggerController.dispose();
    _outcomeController.dispose();
    _otherActionController.dispose();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _draft.incidentType == null) return;
    if (_step == 1 && (_locationController.text.trim().isEmpty)) return;
    if (_step == 3 && !_hasAnyActionSelected()) return;
    if (_step == 4 && _outcomeController.text.trim().isEmpty) return;

    if (_step < 5) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  bool _hasAnyActionSelected() {
    if (_actionChecks.values.any((v) => v)) return true;
    if (_otherActionController.text.trim().isNotEmpty) return true;
    return false;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _draft.occurredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_draft.occurredAt),
    );
    if (time == null) {
      setState(() => _draft.occurredAt = DateTime(
            date.year,
            date.month,
            date.day,
            _draft.occurredAt.hour,
            _draft.occurredAt.minute,
          ));
    } else {
      setState(() => _draft.occurredAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ));
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    // Collect actions into draft.actions
    _draft.actions.clear();
    _actionChecks.forEach((label, checked) {
      if (checked) _draft.actions.add(label);
    });
    if (_otherActionController.text.trim().isNotEmpty) {
      _draft.actions.add(_otherActionController.text.trim());
    }

    _draft.location = _locationController.text.trim();
    _draft.triggerNotes = _triggerController.text.trim().isEmpty
        ? null
        : _triggerController.text.trim();
    _draft.outcome = _outcomeController.text.trim();

    try {
      final res = await ApiService.postIncidentReport(
        clientId: widget.clientId,
        incidentType: _draft.incidentType!,
        occurredAt: _draft.occurredAt,
        location: _draft.location!,
        triggerNotes: _draft.triggerNotes,
        actionsTaken: _draft.actions,
        outcome: _draft.outcome!,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final entry = IncidentReportEntry.fromJson(
          Map<String, dynamic>.from(data),
        );
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (context) => IncidentReportDetailScreen(
              clientName: widget.clientName,
              report: entry,
            ),
          ),
        );
      } else {
        if (!mounted) return;
        final body = res.body;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to submit report: ${res.statusCode}${body.isNotEmpty ? " — $body" : ""}'),
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
    final totalSteps = 6;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('File Incident Report'),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Step ${_step + 1} of $totalSteps',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: (_step + 1) / totalSteps,
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildStepContent(theme)),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _back,
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _step == totalSteps - 1
                        ? (_submitting ? null : _submit)
                        : _next,
                    child: _submitting
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _step == totalSteps - 1 ? 'Submit Report' : 'Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_step) {
      case 0:
        return _buildIncidentTypeStep(theme);
      case 1:
        return _buildWhenWhereStep(theme);
      case 2:
        return _buildTriggersStep(theme);
      case 3:
        return _buildActionsStep(theme);
      case 4:
        return _buildOutcomeStep(theme);
      case 5:
      default:
        return _buildReviewStep(theme);
    }
  }

  Widget _buildIncidentTypeStep(ThemeData theme) {
    final types = <String, String>{
      'FALL': 'Fall',
      'BEHAVIORAL_CRISIS': 'Behavioral Crisis',
      'MEDICAL_EVENT': 'Medical Event',
      'ELOPEMENT': 'Elopement',
      'SELF_HARM': 'Self-Harm',
      'PROPERTY_DAMAGE': 'Property Damage',
      'OTHER': 'Other',
    };
    final entries = types.entries.toList();
    const spacing = 12.0;
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 160,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final e = entries[index];
        final selected = _draft.incidentType == e.key;
        return InkWell(
          onTap: () => setState(() => _draft.incidentType = e.key),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color:
                    selected ? theme.colorScheme.primary : theme.dividerColor,
                width: selected ? 2 : 1,
              ),
              color: selected
                  ? theme.colorScheme.primary.withOpacity(0.08)
                  : theme.colorScheme.surface,
            ),
            child: Center(
              child: Text(
                e.value,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWhenWhereStep(ThemeData theme) {
    _locationController.text = _locationController.text.isEmpty
        ? (_draft.location ?? '')
        : _locationController.text;
    final dateStr = DateFormat.yMMMd().add_jm().format(_draft.occurredAt);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'When did the incident occur?',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _pickDateTime,
            icon: const Icon(Icons.schedule),
            label: Text(dateStr),
          ),
          const SizedBox(height: 16),
          Text(
            'Where did this occur?',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Location',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTriggersStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Possible triggers or context — optional',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _triggerController,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actions Taken',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ..._actionChecks.entries.map((entry) {
            return CheckboxListTile(
              value: entry.value,
              onChanged: (v) {
                setState(() {
                  _actionChecks[entry.key] = v ?? false;
                });
              },
              title: Text(entry.key),
            );
          }),
          const SizedBox(height: 8),
          TextField(
            controller: _otherActionController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Other actions taken (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'At least one action must be recorded before continuing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutcomeStep(ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Outcome',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _outcomeController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Describe what happened as a result...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep(ThemeData theme) {
    // Prepare final values from controllers
    final typeLabel = _incidentTypeLabel(_draft.incidentType);
    final whenStr = DateFormat.yMMMd().add_jm().format(_draft.occurredAt);
    final actions = <String>[];
    _actionChecks.forEach((label, checked) {
      if (checked) actions.add(label);
    });
    if (_otherActionController.text.trim().isNotEmpty) {
      actions.add(_otherActionController.text.trim());
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review incident report',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _reviewRow('Incident type', typeLabel),
          _reviewRow('When', whenStr),
          _reviewRow('Location', _locationController.text.trim()),
          _reviewRow(
            'Triggers / context',
            _triggerController.text.trim().isEmpty
                ? 'None recorded'
                : _triggerController.text.trim(),
          ),
          const SizedBox(height: 8),
          Text(
            'Actions taken',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (actions.isEmpty)
            Text(
              'No actions recorded',
              style: theme.textTheme.bodyMedium,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: actions
                  .map(
                    (a) => Text('• $a', style: theme.textTheme.bodyMedium),
                  )
                  .toList(),
            ),
          const SizedBox(height: 8),
          _reviewRow('Outcome', _outcomeController.text.trim()),
        ],
      ),
    );
  }

  String _incidentTypeLabel(String? type) {
    switch (type) {
      case 'FALL':
        return 'Fall';
      case 'BEHAVIORAL_CRISIS':
        return 'Behavioral Crisis';
      case 'MEDICAL_EVENT':
        return 'Medical Event';
      case 'ELOPEMENT':
        return 'Elopement';
      case 'SELF_HARM':
        return 'Self-Harm';
      case 'PROPERTY_DAMAGE':
        return 'Property Damage';
      case 'OTHER':
        return 'Other';
      default:
        return 'Unknown';
    }
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class IncidentReportDetailScreen extends StatelessWidget {
  final String clientName;
  final IncidentReportEntry report;

  const IncidentReportDetailScreen({
    super.key,
    required this.clientName,
    required this.report,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whenStr = DateFormat.yMMMd().add_jm().format(report.occurredAt);
    final createdStr = DateFormat.yMMMd().add_jm().format(report.createdAt);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Incident Report'),
            Text(
              clientName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow(
                  'Incident type', _incidentTypeLabel(report.incidentType)),
              _detailRow('When', whenStr),
              _detailRow('Location', report.location),
              _detailRow(
                'Triggers / context',
                (report.triggerNotes ?? '').isEmpty
                    ? 'None recorded'
                    : report.triggerNotes!,
              ),
              const SizedBox(height: 12),
              Text(
                'Actions taken',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              if (report.actions.isEmpty)
                Text(
                  'No actions recorded',
                  style: theme.textTheme.bodyMedium,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: report.actions
                      .map((a) =>
                          Text('• $a', style: theme.textTheme.bodyMedium))
                      .toList(),
                ),
              const SizedBox(height: 12),
              _detailRow('Outcome', report.outcome),
              const SizedBox(height: 12),
              _detailRow('Recorded at', createdStr),
            ],
          ),
        ),
      ),
    );
  }

  String _incidentTypeLabel(String type) {
    return IncidentReportEntry.fromJson({
      'id': report.id,
      'clientId': report.clientId,
      'caregiverId': report.caregiverId,
      'incidentType': type,
      'occurredAt': report.occurredAt.toIso8601String(),
      'location': report.location,
      'triggerNotes': report.triggerNotes,
      'outcome': report.outcome,
      'createdAt': report.createdAt.toIso8601String(),
      'actions': const [],
    }).incidentType.replaceAll('_', ' ').splitMapJoin(
          RegExp(r'(^|_)([A-Z])'),
          onMatch: (m) => '${m.group(2)}',
          onNonMatch: (s) => s,
        );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              // ignore: use_build_context_synchronously
              WidgetsBinding.instance.rootElement!,
            ).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(
              // ignore: use_build_context_synchronously
              WidgetsBinding.instance.rootElement!,
            ).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
