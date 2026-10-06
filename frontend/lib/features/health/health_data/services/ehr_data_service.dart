import '../../../../services/auth_token_manager.dart';
import '../../../../services/api_client.dart';
import '../models/health_record.dart';
import '../models/patient_demographics.dart';

class EhrDataService {
  Future<List<HealthRecord>> fetchRecords() async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();

      final resources = await ApiClient.instance.getJson<List<dynamic>>(
        '/api/ehr/resources',
        headers: headers,
        parser: (json) => json is List ? json : <dynamic>[],
      );

      return resources
          .whereType<Map<String, dynamic>>()
          .map(_toHealthRecord)
          .toList();
    } catch (_) {
      return <HealthRecord>[];
    }
  }

  Future<PatientDemographics?> fetchPatientDemographics() async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();

      return await ApiClient.instance.getJson<PatientDemographics>(
        '/api/ehr/patient',
        headers: headers,
        parser: (json) => PatientDemographics.fromJson(
          json as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  HealthRecord _toHealthRecord(Map<String, dynamic> resource) {
    return HealthRecord.single(
      id: (resource['resourceId'] ?? '').toString(),
      source: _sourceFrom(resource['source']),
      type: _recordTypeFrom(resource['category']),
      title: _stringOrNull(resource['title']) ?? 'Health record',
      date: _parseDate(resource['occurredAt']),
      status: _stringOrNull(resource['status']),
    );
  }

  RecordSource _sourceFrom(dynamic source) {
    switch (source?.toString().toUpperCase()) {
      case 'CERNER':
        return RecordSource.cerner;
      case 'ATHENA':
        return RecordSource.athena;
      case 'MEDICARE':
        return RecordSource.medicare;
      case 'EPIC':
      default:
        return RecordSource.epic;
    }
  }

  RecordType _recordTypeFrom(dynamic category) {
    switch (category?.toString()) {
      case 'Conditions':
        return RecordType.condition;
      case 'Medications':
        return RecordType.medication;
      case 'Allergies':
        return RecordType.allergy;
      default:
        return RecordType.other;
    }
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) return null;

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
