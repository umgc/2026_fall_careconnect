// home_care_document_api.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';

import '../models/home_care_document_models.dart';

/// A picked source document held in memory (works on web and mobile).
class PickedHomeCareFile {
  final Uint8List bytes;
  final String name;

  const PickedHomeCareFile({required this.bytes, required this.name});
}

class HomeCareDocumentApi {
  /// Fetches the digitizable document types and their field schemas.
  /// Falls back to the local schema mirror when the backend is unavailable
  /// so manual entry keeps working.
  static Future<List<HomeCareDocumentTypeInfo>> fetchDocumentTypes() async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();
      final resp = await http
          .get(Uri.parse('${ApiConstants.homeCareDocuments}/types'),
              headers: headers)
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is List) {
          final types = body
              .map((e) =>
                  HomeCareDocumentTypeInfo.fromJson(e as Map<String, dynamic>))
              .toList();
          if (types.isNotEmpty) return types;
        }
      }
    } catch (e) {
      print('⚠️ Falling back to local home-care document types: $e');
    }
    return defaultHomeCareDocumentTypes;
  }

  /// Runs the uploaded document through the OCR + LLM pipeline and returns
  /// draft structured fields for review. Never throws: any failure returns a
  /// manual-entry fallback result so the user can continue by hand.
  static Future<HomeCareExtractionResult> extract({
    required HomeCareDocumentTypeInfo documentType,
    required List<PickedHomeCareFile> files,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.homeCareDocuments}/extract');
      final headers = await AuthTokenManager.getAuthHeaders();
      headers.remove('Content-Type'); // set by the multipart request

      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields['documentType'] = documentType.type;

      for (final file in files) {
        final mime = lookupMimeType(file.name, headerBytes: file.bytes) ??
            'application/octet-stream';
        final parts = mime.split('/');
        req.files.add(http.MultipartFile.fromBytes(
          'files',
          file.bytes,
          filename: file.name,
          contentType: MediaType(parts[0], parts[1]),
        ));
      }

      final streamed = await req.send().timeout(const Duration(seconds: 180));
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        if (body is Map<String, dynamic> && body['fields'] is List) {
          return HomeCareExtractionResult.fromJson(body);
        }
      }

      print('⚠️ extract failed: ${resp.statusCode} ${resp.body}');
      return HomeCareExtractionResult.manualFallback(
        documentType,
        message:
            'Automatic extraction was unavailable. Please enter the fields manually.',
      );
    } catch (e) {
      print('⚠️ extract error: $e');
      return HomeCareExtractionResult.manualFallback(
        documentType,
        message:
            'Automatic extraction failed. Please enter the fields manually.',
      );
    }
  }
}
