import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../models/hiring_form_models.dart';
import 'enhanced_file_service.dart';

/// Loads the bundled hiring & onboarding form definitions (shipped as Flutter
/// assets under `assets/forms/`) and files completed forms into the existing
/// file-attachment system via [EnhancedFileService].
///
/// This is self-contained: it reads the same structured schema the backend
/// uses, so the page can render every form's sections/fields/validation and
/// surface version/effective-date metadata without a dedicated forms API.
class HiringFormAssetService {
  /// The bundled definitions, in the order they should be presented.
  static const List<String> _assetFiles = [
    'assets/forms/w4-2026.form.json',
    'assets/forms/i9-2025.form.json',
    'assets/forms/direct-deposit.form.json',
    'assets/forms/sworn-disclosure.form.json',
    'assets/forms/health-screening.form.json',
    'assets/forms/general-hiring.form.json',
    'assets/forms/pre-hire.form.json',
  ];

  static List<FormDefinition>? _cache;

  /// Load and parse all bundled form definitions (cached after first load).
  static Future<List<FormDefinition>> loadDefinitions() async {
    if (_cache != null) return _cache!;
    final defs = <FormDefinition>[];
    for (final path in _assetFiles) {
      try {
        final raw = await rootBundle.loadString(path);
        final json = jsonDecode(raw) as Map<String, dynamic>;
        defs.add(FormDefinition.fromJson(json));
      } catch (e) {
        // Skip a definition that fails to load rather than breaking the page,
        // but surface the failure so a malformed form isn't silently dropped.
        debugPrint('HiringFormAssetService: failed to load "$path": $e');
      }
    }
    _cache = defs;
    return defs;
  }

  /// Upload a completed form document into the file-attachment system under the
  /// form's mapped category (e.g. ONBOARDING_FORM).
  ///
  /// Byte-based so it works identically on web and native — no `dart:io`, which
  /// keeps this widget tree compilable for Flutter web.
  static Future<FileUploadResponse?> uploadCompletedForm({
    required FormDefinition definition,
    required Uint8List bytes,
    required String fileName,
    int? patientId,
  }) {
    return EnhancedFileService.uploadFileWeb(
      fileBytes: bytes,
      fileName: fileName,
      category: definition.fileCategory,
      description: '${definition.title} (v${definition.version})',
      patientId: patientId,
    );
  }
}
