import 'dart:convert';
import 'dart:typed_data';

import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../models/medication-model.dart';
import '../models/medication_photo_extraction.dart';

Future<List<Medication>> fetchMedicationsFromEnhancedProfile({
  required String baseUrl,   // e.g. http://10.0.2.2:8080 (emulator) or http://localhost:8080 (web)
  required int patientId,    // from /v1/api/patients/me
  required String jwtToken,  // Bearer <token>
}) async {
  final uri = Uri.parse('$baseUrl/v1/api/patients/$patientId/profile/enhanced');

  final res = await http.get(
    uri,
    headers: {
      'Authorization': 'Bearer $jwtToken',
      'Content-Type': 'application/json',
    },
  );

  if (res.statusCode != 200) {
    throw Exception('Profile fetch failed: ${res.statusCode} ${res.body}');
  }

  final Map<String, dynamic> body = json.decode(res.body);
  final Map<String, dynamic> data = (body['data'] as Map<String, dynamic>?) ?? {};
  final List meds = (data['activeMedications'] as List?) ?? const [];

  return meds
      .whereType<Map<String, dynamic>>()
      .map((m) => Medication.fromJson(m))
      .toList();
}

/// Sends a medication label photo to the OCR + LLM pipeline and returns draft
/// fields for review. The photo bytes stay in memory and are never logged.
/// Never throws: any failure returns a manual-entry fallback result.
Future<MedicationPhotoExtractionResult> extractMedicationPhoto({
  required int patientId,
  required Uint8List imageBytes,
  required String fileName,
  http.Client? client,
}) async {
  const unreadableMessage =
      'The photo could not be read. Please enter the medication manually.';
  try {
    final uri = Uri.parse(
      '${ApiConstants.patientsV3}/$patientId/medications/extract-photo',
    );
    final headers = await AuthTokenManager.getAuthHeaders();
    headers.remove('Content-Type'); // set by the multipart request

    final mime = lookupMimeType(fileName, headerBytes: imageBytes) ?? 'image/jpeg';
    final mimeParts = mime.split('/');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: fileName,
        contentType: MediaType(mimeParts[0], mimeParts[1]),
      ));

    final streamed = await (client?.send(request) ?? request.send())
        .timeout(const Duration(seconds: 90));
    final resp = await http.Response.fromStream(streamed);
    final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : null;

    if (resp.statusCode == 200 &&
        body is Map<String, dynamic> &&
        body['fields'] is List) {
      return MedicationPhotoExtractionResult.fromJson(body);
    }
    final serverMessage = body is Map<String, dynamic> ? body['message'] : null;
    if (resp.statusCode == 400 &&
        serverMessage is String &&
        serverMessage.isNotEmpty) {
      return MedicationPhotoExtractionResult.manualFallback(
        message: serverMessage,
      );
    }
    return MedicationPhotoExtractionResult.manualFallback(
      message: unreadableMessage,
    );
  } catch (_) {
    return MedicationPhotoExtractionResult.manualFallback(
      message: unreadableMessage,
    );
  }
}
