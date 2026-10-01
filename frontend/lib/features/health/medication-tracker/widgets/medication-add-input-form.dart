import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:care_connect_app/features/health/medication-tracker/data/medication_photo_tts.dart';
import 'package:care_connect_app/features/health/medication-tracker/data/medications_api.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication-model.dart';
import 'package:care_connect_app/features/health/medication-tracker/models/medication_photo_extraction.dart';
import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/shared/widgets/disclaimer_banner.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:care_connect_app/widgets/ai_chat_modal.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

/// Modal for adding a new medication
class AddMedicationModal extends StatefulWidget {
  final Function(Medication) onMedicationAdded;

  /// Picks a medication label photo. Defaults to the device camera.
  final Future<XFile?> Function()? pickLabelPhoto;

  /// Sends a label photo for extraction. Defaults to [extractMedicationPhoto].
  final Future<MedicationPhotoExtractionResult> Function(
    int patientId,
    Uint8List imageBytes,
    String fileName,
  )? extractLabelPhoto;

  /// Reads prefilled details aloud. Defaults to [MedicationPhotoTts].
  final MedicationPhotoTts? readAloud;

  const AddMedicationModal({
    super.key,
    required this.onMedicationAdded,
    this.pickLabelPhoto,
    this.extractLabelPhoto,
    this.readAloud,
  });

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

  MedicationType? _selectedMedicationType = MedicationType.PRESCRIPTION;

  DateTime? _prescribedDate;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isLoading = false;

  bool _isReadingPhoto = false;
  MedicationPhotoExtractionResult? _photoResult;

  /// Set when a rescan fails after a successful scan; the earlier review
  /// values and flags stay in place.
  String? _rescanFailureMessage;
  final Set<String> _machineGenerated = {};
  final Set<String> _editedByUser = {};

  /// Bumped on prefill so the dropdowns rebuild with the extracted values.
  int _prefillGeneration = 0;
  MedicationPhotoTts? _tts;

  bool get _isPhotoReview =>
      _photoResult != null && !_photoResult!.manualEntryRequired;

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
                Expanded(
                  child: Text(
                    _isPhotoReview ? 'Review Medication' : 'Add New Medication',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  key: const Key('medication-cancel-button'),
                  tooltip: 'Cancel',
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
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
                        Tooltip(
                          message:
                              'Take a photo of the medication label to fill in this form',
                          child: OutlinedButton.icon(
                            key: const Key('medication-photo-capture-button'),
                            onPressed: _isReadingPhoto || _isLoading
                                ? null
                                : _captureLabelPhoto,
                            icon: const Icon(Icons.camera_alt, size: 16),
                            label: const Text('Scan Label'),
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
                      ],
                    ),
                    _buildPhotoStatus(),
                    const SizedBox(height: 16),

                    // Medication Name
                    _buildTextField(
                      fieldKey: const Key('medication-name-field'),
                      onChanged: (_) => _markEditedByUser(
                          MedicationPhotoFieldKey.medicationName),
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
                    _buildPhotoFieldNote(MedicationPhotoFieldKey.medicationName),
                    const SizedBox(height: 16),

                    // Dosage
                    _buildTextField(
                      fieldKey: const Key('medication-dosage-field'),
                      onChanged: (_) =>
                          _markEditedByUser(MedicationPhotoFieldKey.dosage),
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
                    _buildPhotoFieldNote(MedicationPhotoFieldKey.dosage),
                    const SizedBox(height: 16),

                    // Frequency
                    Text(
                      'Frequency *',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                    const SizedBox(height: 8),
                    KeyedSubtree(
                      key: const Key('medication-frequency-field'),
                      child: DropdownButtonFormField<String>(
                      key: ValueKey('frequency-$_prefillGeneration'),
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
                        _markEditedByUser(MedicationPhotoFieldKey.frequency);
                      },
                    ),
                    ),
                    if (_showCustomFrequency) ...[
                      const SizedBox(height: 16),
                      _buildTextField(
                        fieldKey: const Key('medication-custom-frequency-field'),
                        onChanged: (_) =>
                            _markEditedByUser(MedicationPhotoFieldKey.frequency),
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
                    _buildPhotoFieldNote(MedicationPhotoFieldKey.frequency),
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
                    KeyedSubtree(
                      key: const Key('medication-type-field'),
                      child: DropdownButtonFormField<MedicationType>(
                      key: ValueKey('type-$_prefillGeneration'),
                      initialValue: _selectedMedicationType,
                      isExpanded: true,
                      hint: const Text('Select a type'),
                      validator: (value) =>
                          value == null ? 'Please select a medication type' : null,
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
                          child: Text(type.label, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (MedicationType? newValue) {
                        setState(() {
                          _selectedMedicationType = newValue!;
                        });
                        _markEditedByUser(MedicationPhotoFieldKey.medicationType);
                      },
                    ),
                    ),
                    _buildPhotoFieldNote(MedicationPhotoFieldKey.medicationType),
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
                        key: const Key('medication-save-button'),
                        onPressed: _isLoading || _isReadingPhoto
                            ? null
                            : _addMedication,
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
    Key? fieldKey,
    ValueChanged<String>? onChanged,
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
          key: fieldKey,
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          onChanged: onChanged,
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

  Widget _buildPhotoStatus() {
    final theme = Theme.of(context);
    if (_isReadingPhoto) {
      return Padding(
        key: const Key('medication-photo-progress'),
        padding: const EdgeInsets.only(top: 12),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text('Reading the label photo...',
                  style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    final result = _photoResult;
    if (result == null) return const SizedBox.shrink();

    if (result.manualEntryRequired) {
      return _buildPhotoFailureMessage(result.message ?? _unreadablePhotoMessage);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_rescanFailureMessage != null) ...[
            _buildPhotoFailureMessage(_rescanFailureMessage!),
            const SizedBox(height: 12),
          ],
          const DisclaimerBanner.medication(),
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              result.message ??
                  'Details were read from the photo. Review and edit before saving.',
              key: const Key('medication-photo-review-message'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: 'Read the filled-in details aloud',
            child: OutlinedButton.icon(
              key: const Key('medication-photo-read-aloud-button'),
              onPressed: _readDetailsAloud,
              icon: const Icon(Icons.volume_up, size: 16),
              label: const Text('Read Aloud'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoFailureMessage(String message) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('medication-photo-fallback-message'),
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows whether a field was read from the photo, edited, or left blank.
  Widget _buildPhotoFieldNote(String key) {
    if (!_isPhotoReview) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final (IconData icon, String text, String noteKey) = _machineGenerated
            .contains(key)
        ? (Icons.auto_awesome, 'Read from photo. Please check it.', 'ai')
        : _editedByUser.contains(key)
            ? (Icons.edit, 'Edited by you.', 'edited')
            : (Icons.help_outline, 'Not found on the label. Please fill this in.',
                'missing');

    return Padding(
      key: Key('medication-photo-$noteKey-note-$key'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }

  static const _unreadablePhotoMessage =
      'The photo could not be read. Please enter the medication manually.';

  Future<void> _captureLabelPhoto() async {
    final patientId =
        Provider.of<UserProvider>(context, listen: false).user?.patientId;
    if (patientId == null) {
      _applyPhotoResult(MedicationPhotoExtractionResult.manualFallback(
        message:
            'Photo reading is not available. Please enter the medication manually.',
      ));
      return;
    }

    XFile? photo;
    try {
      photo = await (widget.pickLabelPhoto ?? _pickPhotoFromCamera)();
    } catch (_) {
      _applyPhotoResult(MedicationPhotoExtractionResult.manualFallback(
        message:
            'The camera could not be opened. Please enter the medication manually.',
      ));
      return;
    }
    if (photo == null || !mounted) return;

    setState(() {
      _isReadingPhoto = true;
    });
    MedicationPhotoExtractionResult result;
    try {
      final extract = widget.extractLabelPhoto ??
          (int id, Uint8List bytes, String name) => extractMedicationPhoto(
                patientId: id,
                imageBytes: bytes,
                fileName: name,
              );
      result = await extract(patientId, await photo.readAsBytes(), photo.name);
    } catch (_) {
      result = MedicationPhotoExtractionResult.manualFallback(
        message: _unreadablePhotoMessage,
      );
    }
    if (!mounted) return;
    _applyPhotoResult(result);
  }

  Future<XFile?> _pickPhotoFromCamera() {
    return ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 92,
    );
  }

  void _applyPhotoResult(MedicationPhotoExtractionResult result) {
    setState(() {
      _isReadingPhoto = false;
      if (result.manualEntryRequired && _isPhotoReview) {
        _rescanFailureMessage = result.message ?? _unreadablePhotoMessage;
        return;
      }
      _rescanFailureMessage = null;
      _photoResult = result;
      _machineGenerated.clear();
      _editedByUser.clear();
      if (result.manualEntryRequired) return;

      final name = result.prefilledValue(MedicationPhotoFieldKey.medicationName);
      if (name != null) {
        _nameController.text = name;
        _machineGenerated.add(MedicationPhotoFieldKey.medicationName);
      }

      final dosage = result.prefilledValue(MedicationPhotoFieldKey.dosage);
      if (dosage != null) {
        _dosageController.text = dosage;
        _machineGenerated.add(MedicationPhotoFieldKey.dosage);
      }

      final frequency = result.prefilledValue(MedicationPhotoFieldKey.frequency);
      if (frequency != null) {
        _selectedFrequency = _frequencyOptions.firstWhere(
          (option) =>
              option != 'Custom' &&
              option.toLowerCase() == frequency.toLowerCase(),
          orElse: () => 'Custom',
        );
        _showCustomFrequency = _selectedFrequency == 'Custom';
        _customFrequencyController.text = _showCustomFrequency ? frequency : '';
        _machineGenerated.add(MedicationPhotoFieldKey.frequency);
      }

      _selectedMedicationType = medicationTypeFromExtracted(
        result.prefilledValue(MedicationPhotoFieldKey.medicationType),
      );
      if (_selectedMedicationType != null) {
        _machineGenerated.add(MedicationPhotoFieldKey.medicationType);
      }

      _prefillGeneration++;
    });
  }

  void _markEditedByUser(String key) {
    if (!_isPhotoReview || _editedByUser.contains(key)) return;
    setState(() {
      _machineGenerated.remove(key);
      _editedByUser.add(key);
    });
  }

  Future<void> _readDetailsAloud() async {
    String describe(String label, String value) =>
        value.trim().isEmpty ? '$label: not filled in.' : '$label: ${value.trim()}.';
    final frequency = _selectedFrequency == 'Custom'
        ? _customFrequencyController.text
        : _selectedFrequency;
    final text = [
      'Please check these details before saving.',
      describe('Medication name', _nameController.text),
      describe('Dosage', _dosageController.text),
      describe('Frequency', frequency),
      describe('Medication type', _selectedMedicationType?.name ?? ''),
    ].join(' ');

    _tts ??= widget.readAloud ?? MedicationPhotoTts();
    try {
      await _tts!.speak(text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Read aloud is not available on this device.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
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
          'medicationType': _selectedMedicationType!.name,
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
          Telemetry.event('feature.medications.add', {'statusCode': response.statusCode})
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
    unawaited(_tts?.stop());
    _nameController.dispose();
    _dosageController.dispose();
    _prescribedByController.dispose();
    _notesController.dispose();
    _customFrequencyController.dispose();
    super.dispose();
  }
}
