import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_input_form.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'allergies_card.dart';

class AllergiesTab extends StatefulWidget {
  final String patientId;

  const AllergiesTab({super.key, required this.patientId});

  @override
  State<AllergiesTab> createState() => _AllergiesTabState();
}

class _AllergiesTabState extends State<AllergiesTab> {
  final List<Map<String, dynamic>> _allergies = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchAllergies();
  }

  // Fetch allergies from backend
  Future<void> _fetchAllergies() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final patientId = userProvider.user?.patientId;

      if (patientId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Patient ID not found')),
          );
        }
        return;
      }

      final List<dynamic> allergies =
          await ApiService.fetchAllergies(patientId);

      setState(() {
        _allergies.clear();
        _allergies.addAll(
          allergies.map(
            (a) => {
              'id': a['id'],
              'drug': a['allergen'],
              'severity': a['severity'] ?? 'Unknown',
              'reaction': a['reaction'] ?? '',
              'note': a['notes'] ?? '',
            },
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load allergies: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addAllergy(Map<String, dynamic> allergyData) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final patientId = userProvider.user?.patientId;

    try {
      if (patientId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Patient ID not found')),
          );
        }
        return;
      }

      final data = await ApiService.addAllergy(allergyData, patientId);
      setState(() {
        _allergies.insert(0, {
          'id': data['id'],
          'drug': data['allergen'],
          'severity': data['severity'] ?? 'Unknown',
          'reaction': data['reaction'] ?? '',
          'note': data['notes'] ?? '',
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allergy added successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add allergy: $e')),
        );
      }
    }
  }

  Future<void> _removeAllergy(int index) async {
    final allergy = _allergies[index];
    final id = allergy['id'];

    try {
      final success = await ApiService.removeAllergy(id);
      if (success) {
        setState(() {
          _allergies.removeAt(index);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Allergy deleted successfully')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to delete allergy')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting allergy: $e')),
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
          AllergyInputForm(
            patientId: widget.patientId,
            onAllergyAdded: _addAllergy,
          ),
          const SizedBox(height: 24),
          Text(
            'Known Drug Allergies',
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
          else if (_allergies.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text(
                  'No allergies recorded yet',
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
              itemCount: _allergies.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final allergy = _allergies[index];
                return AllergyCard(
                  drug: allergy['drug'],
                  severity: allergy['severity'],
                  reaction: allergy['reaction'],
                  note: allergy['note'],
                  onDelete: () => _removeAllergy(index),
                );
              },
            ),
        ],
      ),
    );
  }
}
