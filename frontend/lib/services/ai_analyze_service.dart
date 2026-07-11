import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:care_connect_app/config/environment_config.dart';
import 'package:care_connect_app/services/api_service.dart';

class AiAnalyzeService {
  /// POST /api/ai/analyze/allergy
  static Future<Map<String, dynamic>> extractAllergy({
    required int patientId,
    required String transcript,
    String? allergen,
    String? severity,
    String? reaction,
  }) async {
    final base = EnvironmentConfig.baseUrl;
    final uri = Uri.parse('$base/api/ai/analyze/allergy');

    final jwt = await ApiService.getJwtToken();
    if (jwt.isEmpty) throw Exception('No JWT available');

    final body = {
      "patientId": patientId,
      "text": transcript,
      "context": {
        if (allergen != null && allergen.trim().isNotEmpty) "allergen": allergen.trim(),
        if (severity != null && severity.trim().isNotEmpty) "severity": severity.trim(),
        if (reaction != null && reaction.trim().isNotEmpty) "reaction": reaction.trim(),
      }
    };

    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('AI analyze failed (${res.statusCode}): ${res.body}');
    }

    final decoded = json.decode(res.body);

    if (decoded is Map) {
      final data = (decoded['data'] is Map) ? decoded['data'] : decoded;
      return {
        "allergen": _pickAllergyField(data, ['allergen', 'medication', 'drug']),
        "reaction": (data['reaction'] ?? '').toString(),
        "severity": (data['severity'] ?? '').toString().toUpperCase(),
      };
    }

    return {"allergen": "", "reaction": transcript, "severity": ""};
  }

  static String _pickAllergyField(Map data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// POST /v1/api/ai/analyze/symptom
  static Future<Map<String, dynamic>> extractSymptom({
    required int patientId,
    required String transcript,
    String? symptomKeyHint,
    String? severityHint,
    String? notesHint,
    Map<String, dynamic>? context,
  }) async {
    final base = EnvironmentConfig.baseUrl;
    final uri = Uri.parse('$base/v1/api/ai/analyze/symptom');

    final jwt = await ApiService.getJwtToken();
    if (jwt.isEmpty) throw Exception('No JWT available');

    final body = {
      "patientId": patientId,
      "text": transcript,
      "context": {
        if (symptomKeyHint != null && symptomKeyHint.trim().isNotEmpty)
          "symptomKey": symptomKeyHint.trim(),
        if (severityHint != null && severityHint.trim().isNotEmpty)
          "severity": severityHint.trim(),
        if (notesHint != null && notesHint.trim().isNotEmpty) "notes": notesHint.trim(),
        if (context != null) ...context,
      }
    };

    final res = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $jwt',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('AI symptom analyze failed (${res.statusCode}): ${res.body}');
    }

    final decoded = json.decode(res.body);
    if (decoded is Map && decoded['data'] is Map) return decoded['data'];
    return {
      "symptomKey": "",
      "symptomValue": "",
      "severity": "",
      "notes": transcript
    };
  }
}
