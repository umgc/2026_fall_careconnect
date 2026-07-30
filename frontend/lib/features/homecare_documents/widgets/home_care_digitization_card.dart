import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';

import '../models/home_care_document_models.dart';
import '../pages/home_care_document_review_page.dart';
import '../services/home_care_document_api.dart';

typedef HomeCareTypesLoader = Future<List<HomeCareDocumentTypeInfo>> Function();
typedef HomeCareExtractor = Future<HomeCareExtractionResult> Function({
  required HomeCareDocumentTypeInfo documentType,
  required List<PickedHomeCareFile> files,
});

/// Upload-tab card for Home Care Document Digitization: pick a hiring
/// document type and file(s), run them through the OCR + LLM pipeline, and
/// open the prefilled draft for human review. Extraction failures land on the
/// same review screen in manual-entry mode.
class HomeCareDigitizationCard extends StatefulWidget {
  final int? patientId;
  final VoidCallback? onSaved;

  /// Test seams: default to the real API when not provided.
  final HomeCareTypesLoader? typesLoader;
  final HomeCareExtractor? extractor;
  final List<PickedHomeCareFile>? initialFiles;

  const HomeCareDigitizationCard({
    super.key,
    this.patientId,
    this.onSaved,
    this.typesLoader,
    this.extractor,
    this.initialFiles,
  });

  @override
  State<HomeCareDigitizationCard> createState() =>
      _HomeCareDigitizationCardState();
}

class _HomeCareDigitizationCardState extends State<HomeCareDigitizationCard> {
  List<HomeCareDocumentTypeInfo> _types = defaultHomeCareDocumentTypes;
  HomeCareDocumentTypeInfo? _selectedType;
  final List<PickedHomeCareFile> _pickedFiles = [];
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFiles != null) {
      _pickedFiles.addAll(widget.initialFiles!);
    }
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    final loader = widget.typesLoader ?? HomeCareDocumentApi.fetchDocumentTypes;
    List<HomeCareDocumentTypeInfo> types;
    try {
      types = await loader();
    } catch (_) {
      types = defaultHomeCareDocumentTypes;
    }
    if (types.isEmpty) {
      types = defaultHomeCareDocumentTypes;
    }
    if (!mounted) return;
    setState(() {
      _types = types;
      if (_selectedType != null) {
        // Re-resolve the selection against the freshly loaded list so the
        // dropdown value is always an item of the current list.
        _selectedType = types.firstWhere(
          (t) => t.type == _selectedType!.type,
          orElse: () => types.first,
        );
      }
    });
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (final f in result.files) {
        if (f.bytes != null) {
          _pickedFiles.add(PickedHomeCareFile(bytes: f.bytes!, name: f.name));
        }
      }
    });
  }

  Future<void> _digitize() async {
    final type = _selectedType;
    if (type == null || _pickedFiles.isEmpty) return;

    setState(() => _processing = true);

    final extractor = widget.extractor ?? HomeCareDocumentApi.extract;
    final t = AppLocalizations.of(context)!;
    HomeCareExtractionResult result;
    try {
      result = await extractor(
        documentType: type,
        files: List.of(_pickedFiles),
      );
    } catch (_) {
      // The default extractor never throws, but injected ones might — fall
      // back to manual entry rather than leaving the card stuck processing.
      result = HomeCareExtractionResult.manualFallback(
        type,
        message:
            t.homecarewidget_extractionFailed,
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }

    if (!mounted) return;

    if (result.manualEntryRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ??
              t.homecarewidget_extractionUnavailable),
          backgroundColor: AppTheme.warning,
        ),
      );
    }

    await _openReview(result);
  }

  Future<void> _enterManually() async {
    final type = _selectedType;
    if (type == null) return;
    await _openReview(HomeCareExtractionResult.manualFallback(type));
  }

  Future<void> _openReview(HomeCareExtractionResult result) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => HomeCareDocumentReviewPage(
          result: result,
          patientId: widget.patientId,
        ),
      ),
    );

    if (saved == true) {
      setState(() => _pickedFiles.clear());
      widget.onSaved?.call();
    }
  }

  String _translateDisplayName(String displayname){
    final t = AppLocalizations.of(context)!;
    switch(displayname){
      case('Employment Application'):
        return t.filemanage_empApplication;
      case('Certification / License'):
        return t.filemanage_cert;
      case('Tax Form (W-4)'):
        return t.filemanage_taxForm;
      case('Work Authorization (I-9)'):
        return t.filemanage_workAuth;
      default:
        return displayname;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canDigitize =
        _selectedType != null && _pickedFiles.isNotEmpty && !_processing;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.document_scanner, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    local.homecarewidget_homeCareDigitization,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${local.homecarewidget_digitizationDescr1}'
              '${local.homecarewidget_digitizationDescr2}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedType?.type,
              items: _types
                  .map((t) => DropdownMenuItem<String>(
                        value: t.type,
                        child: Text(_translateDisplayName(t.displayName)),
                      ))
                  .toList(),
              onChanged: _processing
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _selectedType =
                            _types.firstWhere((t) => t.type == value);
                      });
                    },
              hint: Text(local.homecarewidget_docTypeHint),
              decoration: InputDecoration(
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _processing ? null : _pickFiles,
                  icon: const Icon(Icons.attach_file),
                  label: Text(local.homecarewidget_chooseFiles),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _pickedFiles.isEmpty
                        ? local.homecarewidget_noFileSelected
                        : _pickedFiles.map((f) => f.name).join(', '),
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_pickedFiles.isNotEmpty && !_processing)
                  IconButton(
                    onPressed: () => setState(() => _pickedFiles.clear()),
                    icon: const Icon(Icons.clear),
                    tooltip: local.homecarewidget_clearSelectFile,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: canDigitize ? _digitize : null,
                  style: AppTheme.primaryButtonStyle,
                  icon: _processing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label:
                      Text(_processing ? '${local.voicecommand_processingState}...' : local.homecarewidget_digitizeReview),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _selectedType == null || _processing
                      ? null
                      : _enterManually,
                  child: Text(local.homecarewidget_enterManual),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
