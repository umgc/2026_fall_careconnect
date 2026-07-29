import 'dart:convert';
import 'package:care_connect_app/features/notetaker/models/patient_note_model.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../config/env_constant.dart';

class PatientNotetakerKeyword {
  final String keyword;
  final String event_type;

  PatientNotetakerKeyword({required this.keyword, required this.event_type});

  Map<String, String> toJson() => {
    'keyword': keyword,
    'event_type': event_type,
  };
}

/// Notetaker Configuration Data Transfer Object
class PatientNotetakerConfigDTO {
  final int? id;
  final int patientId;
  final bool isEnabled;
  final bool permitCaregiverAccess;
  final List<PatientNotetakerKeyword> triggerKeywords;
  final DateTime? updatedAt;

  PatientNotetakerConfigDTO({
    this.id,
    required this.patientId,
    required this.isEnabled,
    required this.permitCaregiverAccess,
    required this.triggerKeywords,
    this.updatedAt,
  });

  factory PatientNotetakerConfigDTO.fromJson(Map<String, dynamic> json) {
    return PatientNotetakerConfigDTO(
      id: json['id'],
      patientId: json['patientId'],
      isEnabled: json['isEnabled'] ?? 'DEFAULT',
      permitCaregiverAccess: json['permitCaregiverAccess'],
      triggerKeywords: (List<dynamic>.from(json['triggerKeywords'] ?? [])
          .map(
            (trigger) => PatientNotetakerKeyword(
              keyword: trigger['keyword'],
              event_type: trigger['event_type'],
            ),
          )
          .toList()),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'patientId': patientId,
      'isEnabled': isEnabled,
      'permitCaregiverAccess': permitCaregiverAccess,
      'triggerKeywords': triggerKeywords
          .map((trigger) => trigger.toJson())
          .toList(),
    };
  }

  PatientNotetakerConfigDTO copyWith({
    int? id,
    int? patientId,
    bool? isEnabled,
    bool? permitCaregiverAccess,
    List<PatientNotetakerKeyword>? triggerKeywords,
    DateTime? updatedAt,
  }) {
    return PatientNotetakerConfigDTO(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      isEnabled: isEnabled ?? this.isEnabled,
      permitCaregiverAccess:
          permitCaregiverAccess ?? this.permitCaregiverAccess,
      triggerKeywords: triggerKeywords ?? this.triggerKeywords,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Service to manage Notetaker configuration settings for patients
class NotetakerConfigService {
  static String get baseUrl =>
      '${getBackendBaseUrl()}/v1/api/patient-notetaker';

  /// Create or update Notetaker configuration for a user
  /// Returns the saved PatientNotetakerConfigDTO or null on failure
  static Future<PatientNotetakerConfigDTO?> saveUserNotetakerConfig(
    PatientNotetakerConfigDTO config, {
    required int userId,
  }) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      authHeaders['Content-Type'] = 'application/json';
      authHeaders['Accept'] = '*/*';

      // Compose request body to match backend API
      final requestBody = {
        'userId': userId,
        'patientId': config.patientId,
        'isEnabled': config.isEnabled,
        'permitCaregiverAccess': config.permitCaregiverAccess,
        'triggerKeywords': config.triggerKeywords
            .map((trigger) => trigger.toJson())
            .toList(),
      };

      final response = await http.put(
        Uri.parse('$baseUrl/${config.patientId}/config'),
        headers: authHeaders,
        body: jsonEncode(requestBody),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return PatientNotetakerConfigDTO.fromJson(data);
      } else {
        print(
          '❌ Failed to save/update Notetaker config: ${response.statusCode}',
        );
        return null;
      }
    } catch (e) {
      print('❌ Error saving/updating Notetaker config: $e');
      return null;
    }
  }

  /// Get Notetaker configuration for the logged-in user
  /// Usage: NotetakerConfigService.getUserAIConfig(context)
  static Future<PatientNotetakerConfigDTO?> getUserNotetakerConfig(
    int patientId,
    context,
  ) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final uri = Uri.parse('$baseUrl/${patientId.toString()}/config');
      print('❌ Getting Notetaker config for patientId $patientId from: $uri');
      final response = await http.get(uri, headers: authHeaders);
      print('❌ Notetaker config response status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PatientNotetakerConfigDTO.fromJson(data);
      } else if (response.statusCode == 404) {
        print(
          '❌ No Notetaker config found for patientId $patientId, using default',
        );
        return _getDefaultConfig(patientId);
      } else {
        print('❌ Failed to get Notetaker config: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error getting Notetaker config: $e');
      return null;
    }
  }

  // ...keep only DTO and single config logic if needed...

  /// Get default notetaker configuration for a patient
  static PatientNotetakerConfigDTO _getDefaultConfig(int patientId) {
    return PatientNotetakerConfigDTO(
      patientId: patientId,
      isEnabled: true,
      permitCaregiverAccess: false,
      triggerKeywords: [
        PatientNotetakerKeyword(
          keyword: 'PII_Social Security',
          event_type: 'ALERT',
        ),
        PatientNotetakerKeyword(
          keyword: 'PII_Credit Card',
          event_type: 'ALERT',
        ),
      ],
    );
  }

  static Future<List<PatientNote>> getPatientNotes(int patientId) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final uri = Uri.parse('$baseUrl/${patientId.toString()}/notes');
      final response = await http.get(uri, headers: authHeaders);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> data;
        if (decoded is List) {
          data = decoded;
        } else if (decoded is Map && decoded.containsKey('data')) {
          data = decoded['data'] as List<dynamic>;
        } else if (decoded is Map && decoded.containsKey('notes')) {
          data = decoded['notes'] as List<dynamic>;
        } else {
          return [];
        }
        final notes = <PatientNote>[];
        for (var i = 0; i < data.length; i++) {
          final noteJson = data[i];
          try {
            final note = PatientNote.fromJson(noteJson);
            notes.add(note);
          } catch (e) {
            // Skip malformed notes
          }
        }
        return notes;
      } else if (response.statusCode == 404) {
        return [];
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  /// Loads a single patient note by id (used by Ask AI citation deep links).
  static Future<PatientNote?> getPatientNote(int patientId, String noteId) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final uri = Uri.parse('$baseUrl/$patientId/notes/$noteId');
      final response = await http.get(uri, headers: authHeaders);
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return PatientNote.fromJson(decoded);
      }
      if (decoded is Map) {
        return PatientNote.fromJson(Map<String, dynamic>.from(decoded));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<PatientNote> createPatientNote(PatientNote note) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      authHeaders['Content-Type'] = 'application/json';
      authHeaders['Accept'] = '*/*';

      final response = await http.post(
        Uri.parse('$baseUrl/${note.patientId}/notes'),
        headers: authHeaders,
        body: jsonEncode(note.toJson()),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return PatientNote.fromJson(data);
      } else {
        throw Exception('Failed to update note: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error updating note: $e');
    }
  }

  static Future<PatientNote> updatePatientNote(PatientNote note) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      authHeaders['Content-Type'] = 'application/json';
      authHeaders['Accept'] = '*/*';

      final response = await http.put(
        Uri.parse('$baseUrl/${note.patientId}/notes/${note.id}'),
        headers: authHeaders,
        body: jsonEncode(note.toJson()),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return PatientNote.fromJson(data);
      } else {
        throw Exception('Failed to update note: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error updating note: $e');
    }
  }

  static Future<void> deletePatientNote(String noteId, int patientId) async {
    try {
      final authHeaders = await ApiService.getAuthHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/${patientId.toString()}/notes/$noteId'),
        headers: authHeaders,
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return;
      }
    } catch (e) {
      print('Error deleting note: $e');
      return;
    }
  }
}
