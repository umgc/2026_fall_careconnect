import 'dart:convert';
import 'dart:async';

import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:care_connect_app/widgets/ai_chat_modal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Modal for adding a new medication
class AddMedicationModal extends StatefulWidget {
  final Function(Medication) onMedicationAdded;

  const AddMedicationModal({super.key, required this.onMedicationAdded});

  @override
  State<AddMedicationModal> createState() => _AddMedicationModalState();
}

class _AddMedicationModalState extends State<AddMedicationModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _prescribedByController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedFrequency = 'Once daily';
  final _customFrequencyController = TextEditingController();
  bool _showCustomFrequency = false;

  String _selectedRoute = 'Oral';
  final List<String> _routeOptions = [
    'Oral',
    'IV',
    'Topical',
    'Subcutaneous',
    'Intramuscular',
    'Inhalation',
    'Other',
  ];

  MedicationType _selectedMedicationType = MedicationType.PRESCRIPTION;

  DateTime? _prescribedDate;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = false;

  final List<String> _frequencyOptions = [
    'Once daily',
    'Twice daily',
    'Three times daily',
    'Four times daily',
    'As needed',
    'Custom',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Add New Medication',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => const AIChatModal(
                              role: 'patient',
                              mode: AiChatMode.groundedRecords,
                            ),
                          );
                        },
                        icon: const Icon(Icons.smart_toy, size: 16),
                        label: const Text('Use AI Service'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Medication Name
                    _buildTextField(
                      controller: _nameController,
                      label: 'Medication Name *',
                      hintText: 'e.g., Aspirin, Lisinopril, Metformin',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter medication name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Dosage
                    _buildTextField(
                      controller: _dosageController,
                      label: 'Dosage *',
                      hintText: 'e.g., 10mg, 500mg, 1000 IU',
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter dosage';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Frequency
                    Text(
                      'Frequency *',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedFrequency,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      items: _frequencyOptions.map((String frequency) {
                        return DropdownMenuItem<String>(
                          value: frequency,
                          child: Text(frequency),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedFrequency = newValue!;
                          _showCustomFrequency = newValue == 'Custom';
                          if (!_showCustomFrequency) {
                            _customFrequencyController.clear();
                          }
                        });
                      },
                    ),
                    if (_showCustomFrequency) ...[
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _customFrequencyController,
                        label: 'Custom Frequency',
                        hintText: 'e.g., Every 8 hours, Twice weekly, etc.',
                        validator: (value) {
                          if (_selectedFrequency == 'Custom' &&
                              (value == null || value.isEmpty)) {
                            return 'Please enter custom frequency';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Route (Method of Delivery)
                    Text(
                      'Route *',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedRoute,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      items: _routeOptions.map((String route) {
                        return DropdownMenuItem<String>(
                          value: route,
                          child: Text(route),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedRoute = newValue!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Medication Type
                    Text(
                      'Medication Type',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<MedicationType>(
                      initialValue: _selectedMedicationType,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                      ),
                      items: MedicationType.values.map((MedicationType type) {
                        return DropdownMenuItem<MedicationType>(
                          value: type,
                          child: Text(type.name),
                        );
                      }).toList(),
                      onChanged: (MedicationType? newValue) {
                        setState(() {
                          _selectedMedicationType = newValue!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Prescribed By
                    _buildTextField(
                      controller: _prescribedByController,
                      label: 'Prescribed By',
                      hintText: 'e.g., Dr. Smith',
                    ),
                    const SizedBox(height: 16),

                    // Prescribed Date
                    _buildDateField(
                      label: 'Prescribed Date',
                      date: _prescribedDate,
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _prescribedDate = date;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Start Date
                    _buildDateField(
                      label: 'Start Date',
                      date: _startDate,
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setState(() {
                            _startDate = date;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // End Date
                    _buildDateField(
                      label: 'End Date (Optional)',
                      date: _endDate,
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _startDate ?? DateTime.now(),
                          firstDate: _startDate ?? DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (date != null) {
                          setState(() {
                            _endDate = date;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Notes
                    _buildTextField(
                      controller: _notesController,
                      label: 'Notes',
                      hintText: 'e.g., Take with food, Avoid alcohol',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 32),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _addMedication,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              )
                            : Text(
                                'Add Medication',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                    ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).dividerColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  date != null
                      ? '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                      : 'Select date',
                  style: TextStyle(
                    color: date != null
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _addMedication() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final patientId = userProvider.user?.patientId;

        if (patientId == null) {
          throw Exception('Patient ID not found');
        }

        final frequency = _selectedFrequency == 'Custom'
            ? _customFrequencyController.text
            : _selectedFrequency;

        // Format dates to ISO 8601 strings
        String? formatDate(DateTime? date) {
          if (date == null) return null;
          return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        }

        final medicationData = {
          'medicationName': _nameController.text,
          'dosage': _dosageController.text,
          'frequency': frequency,
          'route': _selectedRoute,
          'medicationType': _selectedMedicationType.name,
          if (_prescribedByController.text.isNotEmpty)
            'prescribedBy': _prescribedByController.text,
          if (_prescribedDate != null)
            'prescribedDate': formatDate(_prescribedDate),
          if (_startDate != null) 'startDate': formatDate(_startDate),
          if (_endDate != null) 'endDate': formatDate(_endDate),
          if (_notesController.text.isNotEmpty) 'notes': _notesController.text,
        };


        final response = await ApiService.addPatientMedication(
          patientId,
          medicationData,
        );
        
        unawaited(
          Telemetry.event('feature.medications.add', {'status': response}),
        );

        if (response.statusCode == 200) {
          // Parse the response to get the created medication
          final Map<String, dynamic> responseData =
              response.body.isNotEmpty ? Map<String, dynamic>.from(
                  // ignore: inference_failure_on_function_invocation
                  jsonDecode(response.body)) : {};

          final medication = Medication.fromJson(responseData);

          // Show success snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Medication added successfully!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // Call callback with the created medication
          widget.onMedicationAdded(medication);

          // Close modal
          if (mounted) {
            Navigator.pop(context);
          }
        } else {
          // Show error snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('Failed to add medication: ${response.statusCode}'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        print('Error adding medication: $e');

        // Show error snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _prescribedByController.dispose();
    _notesController.dispose();
    _customFrequencyController.dispose();
    super.dispose();
  }
}
