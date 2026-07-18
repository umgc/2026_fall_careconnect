import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/services/enhanced_file_service.dart';

import '../models/home_care_document_models.dart';

/// Human review screen for a digitized home-care document.
///
/// AI-prefilled values are clearly marked as machine-generated and stay
/// editable; when extraction failed the same form opens blank for manual
/// entry. Saving stores the confirmed structured record through the existing
/// file upload service under the matching onboarding category.
class HomeCareDocumentReviewPage extends StatefulWidget {
  final HomeCareExtractionResult result;
  final int? patientId;

  const HomeCareDocumentReviewPage({
    super.key,
    required this.result,
    this.patientId,
  });

  @override
  State<HomeCareDocumentReviewPage> createState() =>
      _HomeCareDocumentReviewPageState();
}

class _HomeCareDocumentReviewPageState
    extends State<HomeCareDocumentReviewPage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;

  /// Fields whose current value is still the untouched machine-generated one.
  late final Set<String> _machineGenerated;
  final Set<String> _editedByUser = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final f in widget.result.fields)
        f.key: TextEditingController(text: f.value),
    };
    _machineGenerated = {
      for (final f in widget.result.fields)
        if (f.machineGenerated) f.key,
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Scaffold(
      appBar: AppBar(title: Text('Review: ${result.documentTypeDisplayName}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusBanner(result),
            const SizedBox(height: 16),
            ...result.fields.map(_buildFieldRow),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              style: AppTheme.primaryButtonStyle,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_saving ? 'Saving...' : 'Confirm & Save'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(HomeCareExtractionResult result) {
    final theme = Theme.of(context);
    final manual = result.manualEntryRequired;
    final color = manual ? AppTheme.warning : theme.colorScheme.primary;
    final text = result.message ??
        (manual
            ? 'Automatic extraction was unavailable. Please enter the fields manually.'
            : 'Fields below were prefilled by AI from your document. Review and edit them before saving.');

    return Card(
      color: color.withOpacity(0.08),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(manual ? Icons.edit_note : Icons.auto_awesome, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow(HomeCareExtractedField field) {
    final isMachine = _machineGenerated.contains(field.key);
    final wasEdited = _editedByUser.contains(field.key);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: _controllers[field.key],
        enabled: field.editable && !_saving,
        decoration: InputDecoration(
          labelText: field.label,
          helperText: isMachine
              ? 'Machine-generated — please verify before saving'
              : (wasEdited ? 'Edited by you' : null),
          suffixIcon: isMachine
              ? const Tooltip(
                  message: 'Prefilled by AI (OCR + LLM)',
                  child: Icon(Icons.auto_awesome, size: 20),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (_) {
          if (isMachine) {
            setState(() {
              _machineGenerated.remove(field.key);
              _editedByUser.add(field.key);
            });
          }
        },
      ),
    );
  }

  Future<void> _save() async {
    final userId = widget.patientId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save digitized form: missing user ID.'),
          backgroundColor: AppTheme.error,
        ),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _saving = true);

    try {
      final record = {
        'documentType': widget.result.documentType,
        'documentTypeDisplayName': widget.result.documentTypeDisplayName,
        'sourceDocumentLink': widget.result.documentLink,
        'digitizedAt': DateTime.now().toIso8601String(),
        'fields': [
          for (final f in widget.result.fields)
            {
              'key': f.key,
              'label': f.label,
              'value': _controllers[f.key]!.text.trim(),
              'source': _machineGenerated.contains(f.key)
                  ? 'machine-generated'
                  : 'manual',
            },
        ],
      };

      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(record)),
      );
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName =
          '${widget.result.documentType.toLowerCase()}_digitized_$timestamp.json';

      final response = await EnhancedFileService.uploadFileWeb(
        fileBytes: bytes,
        fileName: fileName,
        category: homeCareDocumentTypeToFileCategory(widget.result.documentType),
        description:
            'Digitized ${widget.result.documentTypeDisplayName} (reviewed)',
        patientId: userId,
      );

      if (!mounted) return;

      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved digitized form: ${response.fileName}'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Upload failed - no response received');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save digitized form: $e'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
