import 'package:flutter/material.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'symptom_input_form.dart';
import 'symptom_card.dart';

class SymptomTab extends StatefulWidget {
  final String patientId;

  const SymptomTab({super.key, required this.patientId});

  @override
  State<SymptomTab> createState() => _SymptomTabState();
}

class _SymptomTabState extends State<SymptomTab> {
  List<Map<String, dynamic>> _symptoms = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchSymptoms();
  }

  // Transform backend symptom data to UI format
  Map<String, dynamic> _transformSymptomToUI(Map<String, dynamic> apiSymptom) {
    final int severity = apiSymptom['severity'] ?? 1;
    String severityLabel;
    bool requiresAttention;

    if (severity >= 5) {
      severityLabel = 'severe';
      requiresAttention = true;
    } else if (severity >= 3) {
      severityLabel = 'moderate';
      requiresAttention = false;
    } else {
      severityLabel = 'mild';
      requiresAttention = false;
    }

    final symptomKey = apiSymptom['symptomKey'] ?? '';
    final symptomValue = apiSymptom['symptomValue'] ?? '';
    final title =
        symptomValue.isNotEmpty ? '$symptomKey $symptomValue' : symptomKey;

    final takenAt = apiSymptom['takenAt'] as String?;
    String timeDisplay = 'Unknown time';
    if (takenAt != null) {
      try {
        final dt = DateTime.parse(takenAt);
        final now = DateTime.now();
        final diff = now.difference(dt);

        if (diff.inMinutes < 60) {
          timeDisplay = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeDisplay = '${diff.inHours}h ago';
        } else {
          timeDisplay = '${diff.inDays}d ago';
        }
      } catch (e) {
        timeDisplay = takenAt;
      }
    }

    return {
      'id': apiSymptom['id'],
      'title': title,
      'severity': severityLabel,
      'time': timeDisplay,
      'description': apiSymptom['clinicalNotes'] ?? 'No additional notes',
      'requiresAttention': requiresAttention,
      'caregiverAlert': requiresAttention,
    };
  }

  // Fetch all symptoms for this patient
  Future<void> _fetchSymptoms() async {
    final int? patientIdInt = int.tryParse(widget.patientId);
    if (patientIdInt == null) return;

    setState(() => _isLoading = true);

    try {
      final symptoms = await ApiService.getSymptomsForPatient(patientIdInt);
      setState(() {
        _symptoms = symptoms.map((s) => _transformSymptomToUI(s)).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load symptoms: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Function to add symptoms
  Future<void> _addSymptom(Map<String, dynamic> symptomData) async {
    setState(() {
      _symptoms.insert(0, symptomData);
    });
  }

  // Function to remove a symptom at a given index
  Future<void> _removeSymptom(int index) async {
    final symptom = _symptoms[index];
    final symptomId = symptom['id'] as int?;

    if (symptomId == null) return;

    try {
      await ApiService.deleteSymptom(symptomId);
      setState(() {
        _symptoms.removeAt(index);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Symptom deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete symptom: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SymptomInputForm(
            patientId: widget.patientId,
            onSymptomAdded: _addSymptom,
          ),
          const SizedBox(height: 24),
          Text(
            'Recent Mental Health Symptoms',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_symptoms.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'No symptoms recorded yet',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _symptoms.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final symptom = _symptoms[index];
                return SymptomCard(
                  title: symptom['title'],
                  severity: symptom['severity'],
                  time: symptom['time'],
                  description: symptom['description'],
                  requiresAttention: symptom['requiresAttention'],
                  caregiverAlert: symptom['caregiverAlert'],
                  // Pass the delete callback to the SymptomCard
                  onDelete: () => _removeSymptom(index),
                );
              },
            ),
        ],
      ),
    );
  }
}
