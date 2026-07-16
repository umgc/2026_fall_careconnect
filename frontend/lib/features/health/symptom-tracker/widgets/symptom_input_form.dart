import 'package:care_connect_app/features/ai/presentation/pages/voice_command_ai.dart';
import 'package:care_connect_app/widgets/ai_chat_modal.dart';
import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/ai_analyze_service.dart';


class SymptomInputForm extends StatefulWidget {
  final String patientId;
  final Function(Map<String, dynamic>)? onSymptomAdded;

  const SymptomInputForm({
    super.key,
    required this.patientId,
    this.onSymptomAdded,
  });

  @override
  State<SymptomInputForm> createState() => _SymptomInputFormState();
}

class _SymptomInputFormState extends State<SymptomInputForm> {
  String _selectedSeverity = 'Mild';
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _symptomController = TextEditingController();

  String? _symptomKeyField;
  String? _symptomValueField;

  bool _saving = false;

  int _severityToInt(String label) {
    switch (label) {
      case 'Severe':
        return 5;
      case 'Moderate':
        return 3;
      case 'Mild':
      default:
        return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record Mental Health Symptom',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      // capture context-dependent handles up front
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);

                      final transcript = await navigator.push<String>(
                        MaterialPageRoute(
                          builder: (_) => const VoiceCommandAI(singleShot: true),
                          fullscreenDialog: true,
                        ),
                      );

                      if (!mounted || transcript == null) return;
                      final t = transcript.trim();
                      if (t.isEmpty) return;

                      setState(() {
                        _symptomController.text = t;
                        _symptomKeyField = t;
                        _symptomValueField = null;
                      });

                      try {
                        final int? intPidForAI = int.tryParse(widget.patientId);
                        if (intPidForAI == null) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('Invalid patient ID')),
                          );
                          return;
                        }

                        final ai = await DeepseekService.extractSymptom(
                          patientId: intPidForAI,
                          transcript: t,
                        );

                        final sevRaw = (ai['severity'] ?? '').toString().toUpperCase();
                        final uiSeverity = switch (sevRaw) {
                          'SEVERE' => 'Severe',
                          'MODERATE' => 'Moderate',
                          'MILD' => 'Mild',
                          _ => _selectedSeverity,
                        };

                        setState(() {
                          final key = (ai['symptomKey'] ?? '').toString().trim();
                          final val = (ai['symptomValue'] ?? '').toString().trim();

                          _symptomKeyField   = key.isNotEmpty ? key : t;     // fallback to transcript
                          _symptomValueField = val.isNotEmpty ? val : null;

                          // single visible text field = key + value
                          _symptomController.text = [
                            _symptomKeyField,
                            _symptomValueField
                          ].where((s) => (s ?? '').isNotEmpty).join(' ');

                          // notes
                          final notes = (ai['notes'] ?? t).toString().trim();
                          if (notes.isNotEmpty) _notesController.text = notes;

                          _selectedSeverity = uiSeverity;
                        });
                        messenger.showSnackBar(
                          const SnackBar(content: Text('AI analyzed symptom ✅')),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(content: Text('AI analysis failed: $e')),
                        );
                        setState(() {
                          final prev = _notesController.text.trim();
                          _notesController.text = prev.isEmpty ? t : '$prev\n$t';
                          _symptomKeyField = t;
                          _symptomValueField = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.mic, size: 16),
                    label: const Text('Use AI Voice'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const AIChatModal(role: 'patient'),
                      );
                    },
                    icon: const Icon(Icons.smart_toy, size: 16),
                    label: const Text('Use AI Service'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Mental Health Symptom',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _symptomController,
            decoration: InputDecoration(
              hintText: 'e.g., Suicidal thoughts, Manic episode, Anxiety...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
            onChanged: (txt) {
              _symptomKeyField = txt.trim().isNotEmpty ? txt.trim() : null;
              _symptomValueField = null;
            },
          ),
          const SizedBox(height: 16),
          const Text('Severity', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _selectedSeverity,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
            items: const ['Mild', 'Moderate', 'Severe']
                .map((value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                .toList(),
            onChanged: (newValue) {
              if (newValue == null) return;
              setState(() => _selectedSeverity = newValue);
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'Clinical Notes',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText:
              'Describe the symptom, onset, duration, triggers, and context for healthcare providers...',
              hintStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : () async {
                final messenger = ScaffoldMessenger.of(context);

                final display = _symptomController.text.trim();
                if (display.isEmpty) return;

                final keyToSend = (_symptomKeyField ?? '').isNotEmpty ? _symptomKeyField!.trim() : display;
                final valToSend = (_symptomValueField ?? '').isNotEmpty ? _symptomValueField!.trim() : null;

                setState(() => _saving = true);
                try {
                  final int? intPidForApi = int.tryParse(widget.patientId);
                  if (intPidForApi == null) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Invalid patient ID')),
                    );
                    setState(() => _saving = false);
                    return;
                  }
                  final saved = await ApiService.createSymptom(
                    patientId: intPidForApi,
                    symptomKey: keyToSend,
                    symptomValue: valToSend,
                    severity: _severityToInt(_selectedSeverity),
                    clinicalNotes: _notesController.text.trim(),
                    completed: true,
                  );

                  if (!mounted) return;

                  // Transform API response to UI format for SymptomCard
                  final String severityLabel = _selectedSeverity.toLowerCase();
                  final uiSymptom = {
                    'id': saved['id'], // Include id from backend for deletion
                    'title': display,
                    'severity': severityLabel,
                    'time': 'Just now',
                    'description': _notesController.text.trim().isNotEmpty
                        ? _notesController.text.trim()
                        : 'No additional notes',
                    'requiresAttention': _selectedSeverity == 'Severe',
                    'caregiverAlert': _selectedSeverity == 'Severe',
                  };

                  widget.onSymptomAdded?.call(uiSymptom);
                  _symptomController.clear();
                  _notesController.clear();
                  _symptomKeyField = null;
                  _symptomValueField = null;
                  setState(() {
                    _selectedSeverity = 'Mild';
                  });

                  messenger.showSnackBar(
                    const SnackBar(content: Text('✅ Symptom saved')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text('❌ Failed to save: $e')),
                  );
                } finally {
                  if (mounted) {
                    setState(() => _saving = false);
                  }
                }
              },
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: Text(_saving ? 'Saving…' : 'Record Symptom'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    _symptomController.dispose();
    super.dispose();
  }
}
