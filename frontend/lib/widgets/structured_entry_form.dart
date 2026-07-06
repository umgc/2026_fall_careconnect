import 'package:flutter/material.dart';
import '../services/structured_entry_service.dart';

/// Dialog form for creating or editing a structured entry captured from an
/// uploaded onboarding document.
///
/// The original uploaded file stays linked to the record as supporting
/// evidence (shown read-only at the top of the form). A patient or employee
/// context is required before the entry can be saved, and required fields for
/// the selected document type are enforced by form validation (and re-checked
/// by the backend).
class StructuredEntryFormDialog extends StatefulWidget {
  final int fileId;
  final String fileName;
  final String fileCategory;

  /// Patient context the entry pertains to (care recipient).
  final int? patientId;

  /// Employee context the entry pertains to (caregiver / staff member).
  final int? employeeUserId;

  /// Existing entry when editing; `null` when creating.
  final StructuredEntryDTO? existingEntry;

  const StructuredEntryFormDialog({
    super.key,
    required this.fileId,
    required this.fileName,
    required this.fileCategory,
    this.patientId,
    this.employeeUserId,
    this.existingEntry,
  });

  /// Opens the form. Returns `true` when an entry was saved.
  static Future<bool?> show(
    BuildContext context, {
    required int fileId,
    required String fileName,
    required String fileCategory,
    int? patientId,
    int? employeeUserId,
    StructuredEntryDTO? existingEntry,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => StructuredEntryFormDialog(
        fileId: fileId,
        fileName: fileName,
        fileCategory: fileCategory,
        patientId: patientId,
        employeeUserId: employeeUserId,
        existingEntry: existingEntry,
      ),
    );
  }

  @override
  State<StructuredEntryFormDialog> createState() =>
      _StructuredEntryFormDialogState();
}

class _StructuredEntryFormDialogState extends State<StructuredEntryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  late String _documentType;
  bool _isSaving = false;

  bool get _isEditing => widget.existingEntry != null;

  int? get _patientId => widget.existingEntry?.patientId ?? widget.patientId;

  int? get _employeeUserId =>
      widget.existingEntry?.employeeUserId ?? widget.employeeUserId;

  bool get _hasContext => _patientId != null || _employeeUserId != null;

  @override
  void initState() {
    super.initState();
    final existingType = widget.existingEntry?.documentType;
    if (DocumentFieldTemplates.isSupported(existingType)) {
      _documentType = existingType!;
    } else if (DocumentFieldTemplates.isSupported(widget.fileCategory)) {
      _documentType = widget.fileCategory;
    } else {
      _documentType = DocumentFieldTemplates.supportedTypes.first;
    }
    _rebuildControllers();
  }

  /// (Re)create controllers for the current document type, keeping values
  /// for keys shared between templates and pre-filling from the existing entry.
  void _rebuildControllers() {
    final previousValues = {
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();

    for (final spec in DocumentFieldTemplates.fieldsFor(_documentType)) {
      final initial = previousValues[spec.key] ??
          widget.existingEntry?.fields[spec.key] ??
          '';
      _controllers[spec.key] = TextEditingController(text: initial);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(controller.text) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 60),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_hasContext) {
      // Backend enforces this too; keep the client-side guard so the user
      // gets immediate feedback instead of a failed request.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A patient or employee must be associated before saving this entry.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final fields = <String, String>{
      for (final entry in _controllers.entries)
        if (entry.value.text.trim().isNotEmpty)
          entry.key: entry.value.text.trim(),
    };

    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isEditing) {
        await StructuredEntryService.updateEntry(
          entryId: widget.existingEntry!.id,
          documentType: _documentType,
          fields: fields,
          patientId: _patientId,
          employeeUserId: _employeeUserId,
        );
      } else {
        await StructuredEntryService.createEntry(
          fileId: widget.fileId,
          documentType: _documentType,
          fields: fields,
          patientId: _patientId,
          employeeUserId: _employeeUserId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _isEditing ? 'Structured entry updated' : 'Structured entry saved',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final specs = DocumentFieldTemplates.fieldsFor(_documentType);

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Structured Entry' : 'New Structured Entry'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Linked original file (kept as supporting evidence)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.attachment, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.fileName,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Original file stays linked as supporting evidence',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Patient / employee context (required before saving)
                if (_hasContext)
                  Row(
                    children: [
                      Icon(
                        _patientId != null ? Icons.person : Icons.badge,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _patientId != null
                            ? 'Patient record #$_patientId'
                            : 'Employee record #$_employeeUserId',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'No patient or employee is associated with this '
                          'file. The entry cannot be saved without one.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 16),

                // Document type
                DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  decoration: const InputDecoration(
                    labelText: 'Document type',
                    border: OutlineInputBorder(),
                  ),
                  items: DocumentFieldTemplates.supportedTypes.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_displayName(type)),
                    );
                  }).toList(),
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null || value == _documentType) return;
                          setState(() {
                            _documentType = value;
                            _rebuildControllers();
                          });
                        },
                ),
                const SizedBox(height: 16),

                // Captured fields for the selected document type
                ...specs.map((spec) {
                  final controller = _controllers[spec.key]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: controller,
                      readOnly: spec.isDate,
                      onTap: spec.isDate ? () => _pickDate(controller) : null,
                      decoration: InputDecoration(
                        labelText:
                            spec.required ? '${spec.label} *' : spec.label,
                        hintText: spec.hint,
                        border: const OutlineInputBorder(),
                        suffixIcon: spec.isDate
                            ? const Icon(Icons.calendar_today, size: 18)
                            : null,
                      ),
                      validator: spec.required
                          ? (value) => (value == null || value.trim().isEmpty)
                              ? '${spec.label} is required'
                              : null
                          : null,
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: (_isSaving || !_hasContext) ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(_isEditing ? 'Update Entry' : 'Save Entry'),
        ),
      ],
    );
  }

  String _displayName(String type) {
    final words = type.toLowerCase().split('_');
    return words
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
