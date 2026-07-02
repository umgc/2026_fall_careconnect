import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../config/theme/app_theme.dart';
import '../../models/hiring_form_models.dart';
import '../../services/hiring_form_asset_service.dart';
import 'hiring_form_fill_page.dart';

/// Tab that surfaces the required hiring & onboarding digital forms (W-4, I-9,
/// direct deposit, sworn disclosure, health, general hiring, pre-hire).
///
/// It reads the bundled structured schema, lists each form with its version and
/// effective-date metadata, lets the user inspect every section/field/validation
/// (read-only), and upload a completed copy which is filed into the existing
/// file-attachment records under the form's category.
class HiringFormsTab extends StatefulWidget {
  const HiringFormsTab({super.key, this.patientId});

  /// Optional patient context for the uploaded file-attachment record.
  final int? patientId;

  @override
  State<HiringFormsTab> createState() => _HiringFormsTabState();
}

class _HiringFormsTabState extends State<HiringFormsTab> {
  late Future<List<FormDefinition>> _future;

  @override
  void initState() {
    super.initState();
    _future = HiringFormAssetService.loadDefinitions();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FormDefinition>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final forms = snapshot.data ?? const <FormDefinition>[];
        if (forms.isEmpty) {
          return const Center(child: Text('No hiring forms available.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: forms.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  'Required hiring & onboarding documents',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              );
            }
            return _FormCard(
              definition: forms[index - 1],
              patientId: widget.patientId,
            );
          },
        );
      },
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.definition, this.patientId});

  final FormDefinition definition;
  final int? patientId;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withOpacity(0.12),
          child: const Icon(Icons.assignment_outlined, color: AppTheme.primary),
        ),
        title: Text(
          definition.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (definition.sourceFormNumber != null)
                _chip(definition.sourceFormNumber!, Icons.description_outlined),
              _chip('v${definition.version}', Icons.tag),
              if (definition.effectiveDate != null)
                _chip('eff. ${definition.effectiveDate}', Icons.event),
              _chip('${definition.fieldCount} fields', Icons.list_alt),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                _FormDetailPage(definition: definition, patientId: patientId),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon) {
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(icon, size: 14, color: AppTheme.textSecondary),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: AppTheme.backgroundSecondary,
      side: BorderSide.none,
    );
  }
}

/// Read-only renderer of a single form definition + upload action.
class _FormDetailPage extends StatefulWidget {
  const _FormDetailPage({required this.definition, this.patientId});

  final FormDefinition definition;
  final int? patientId;

  @override
  State<_FormDetailPage> createState() => _FormDetailPageState();
}

class _FormDetailPageState extends State<_FormDetailPage> {
  bool _uploading = false;

  FormDefinition get d => widget.definition;

  Future<void> _uploadCompletedForm() async {
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
        allowMultiple: false,
        // Load bytes on every platform so the upload path is byte-based and
        // free of dart:io (keeps this widget compilable for Flutter web).
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _uploading = false);
        return;
      }

      final bytes = result.files.single.bytes;
      if (bytes == null) throw Exception('Could not read selected file');
      final response = await HiringFormAssetService.uploadCompletedForm(
        definition: d,
        bytes: bytes,
        fileName: result.files.single.name,
        patientId: widget.patientId,
      );

      if (!mounted) return;
      if (response != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Filed "${d.title}" under ${d.fileCategory}'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        throw Exception('Upload failed - no response');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _fillOutForm() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            HiringFormFillPage(definition: d, patientId: widget.patientId),
      ),
    );
    if (submitted == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(d.title),
        actions: [
          IconButton(
            tooltip: 'Upload a completed copy',
            onPressed: _uploading ? null : _uploadCompletedForm,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _metadataCard(),
          for (final section in d.sections) _sectionCard(section),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _uploading ? null : _fillOutForm,
        icon: const Icon(Icons.edit_document),
        label: const Text('Fill out & submit'),
        backgroundColor: AppTheme.primary,
      ),
    );
  }

  Widget _metadataCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.issuingAuthority != null)
              _metaRow('Issuing authority', d.issuingAuthority!),
            if (d.sourceFormNumber != null)
              _metaRow(
                  'Source form',
                  '${d.sourceFormNumber}'
                  '${d.sourceEdition != null ? ' (${d.sourceEdition})' : ''}'),
            _metaRow('Version', d.version),
            if (d.effectiveDate != null) _metaRow('Effective date', d.effectiveDate!),
            if (d.expirationDate != null) _metaRow('Expires', d.expirationDate!),
            _metaRow('Filed as', d.fileCategory),
            if (d.description != null) ...[
              const SizedBox(height: 8),
              Text(d.description!,
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(FormSectionDef section) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        initiallyExpanded: section.order == 0,
        title: Text(section.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(spacing: 6, children: [
            if (section.completedBy != null)
              _miniTag('by ${section.completedBy!.toLowerCase()}'),
            if (!section.required) _miniTag('optional'),
            if (section.repeatable) _miniTag('repeatable'),
            _miniTag('${section.fields.length} fields'),
          ]),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        children: [
          for (final field in [...section.fields]..sort((a, b) => a.order.compareTo(b.order)))
            _fieldRow(field),
        ],
      ),
    );
  }

  Widget _fieldRow(FormFieldDef field) {
    final rules = field.validations
        .map((v) => v.summary)
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
                    children: [
                      TextSpan(text: field.label),
                      if (field.required)
                        const TextSpan(
                            text: ' *',
                            style: TextStyle(
                                color: AppTheme.error, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              if (field.sensitive)
                const Icon(Icons.lock_outline, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              _miniTag(field.fieldType.display),
            ],
          ),
          if (field.helpText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(field.helpText!,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ),
          if (field.options.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final o in field.options)
                    _miniTag(o.label, subtle: true),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 10,
              runSpacing: 2,
              children: [
                if (rules.isNotEmpty)
                  Text('Rules: ${rules.join(', ')}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                if (field.sourceMapping != null &&
                    field.sourceMapping!.label.isNotEmpty)
                  Text('Source: ${field.sourceMapping!.label}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          const Divider(height: 14),
        ],
      ),
    );
  }

  Widget _miniTag(String label, {bool subtle = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: subtle
            ? AppTheme.backgroundSecondary
            : AppTheme.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: subtle ? AppTheme.textSecondary : AppTheme.primaryDark)),
    );
  }
}
