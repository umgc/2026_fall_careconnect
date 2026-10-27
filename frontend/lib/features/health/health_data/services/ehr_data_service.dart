import '../../../../services/auth_token_manager.dart';
import '../../../../services/api_client.dart';
import '../models/health_record.dart';
import '../models/patient_demographics.dart';
import 'ehr_resource_mapper.dart';

class EhrDataService {
  Future<List<HealthRecord>> fetchRecords({int? patientId}) async =>
      await tryFetchRecords(patientId: patientId) ?? <HealthRecord>[];

  /// Returns available records, or null when every attempted EHR read fails.
  /// Each endpoint is isolated so one unavailable source does not hide
  /// records returned successfully by another source.
  Future<List<HealthRecord>?> tryFetchRecords({int? patientId}) async {
    late final Map<String, String> headers;

    try {
      headers = await AuthTokenManager.getAuthHeaders();
    } catch (_) {
      return null;
    }

    final records = <HealthRecord>[];
    var requestSucceeded = false;

    final unifiedResources = await _tryFetchList(
      '/api/ehr/resources',
      query: {'source': 'ALL'},
      headers: headers,
    );

    if (unifiedResources != null) {
      requestSucceeded = true;

      records.addAll(
        unifiedResources
            .map(EhrResourceMapper.toHealthRecord)
            .whereType<HealthRecord>(),
      );
    }

    if (patientId != null) {
      final basePath = '/v1/api/cerner/patients/$patientId';

      final allergies = await _tryFetchEnvelopeList(
        '$basePath/allergies',
        'allergies',
        headers: headers,
      );

      if (allergies != null) {
        requestSucceeded = true;
        records.addAll(allergies.map(_toCernerAllergy));
      }

      final conditions = await _tryFetchEnvelopeList(
        '$basePath/conditions',
        'conditions',
        headers: headers,
      );

      if (conditions != null) {
        requestSucceeded = true;

        records.addAll(
          conditions
              .where((condition) => condition['hiddenFromActiveList'] != true)
              .map(_toCernerCondition),
        );
      }

      final encounters = await _tryFetchEnvelopeList(
        '$basePath/encounters',
        'encounters',
        headers: headers,
      );

      if (encounters != null) {
        requestSucceeded = true;
        records.addAll(encounters.map(_toCernerEncounter));
      }
    }

    return requestSucceeded ? records : null;
  }

  Future<List<Map<String, dynamic>>?> _tryFetchList(
    String path, {
    Map<String, dynamic>? query,
    required Map<String, String> headers,
  }) async {
    try {
      final values = await ApiClient.instance.getJson<List<dynamic>>(
        path,
        query: query,
        headers: headers,
        parser: (json) => json is List ? json : <dynamic>[],
      );

      return values
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>?> _tryFetchEnvelopeList(
    String path,
    String field, {
    required Map<String, String> headers,
  }) async {
    try {
      final envelope = await ApiClient.instance.getJson<Map<String, dynamic>>(
        path,
        headers: headers,
        parser: (json) {
          if (json is Map<String, dynamic>) {
            return json;
          }

          if (json is Map) {
            return Map<String, dynamic>.from(json);
          }

          return <String, dynamic>{};
        },
      );

      final values = envelope[field];

      if (values is! List) {
        return <Map<String, dynamic>>[];
      }

      return values
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
    } catch (_) {
      return null;
    }
  }

  /// Sources the Patient Information card reads, most preferred first.
  /// Epic is the default source of /api/ehr/patient; athenahealth fills any
  /// field Epic doesn't have, or the whole card when there is no Epic chart.
  static const demographicsSources = ['EPIC', 'ATHENAHEALTH'];

  /// The patient's demographics, field by field from the first source in
  /// [demographicsSources] that has each one. Null when no source has any.
  Future<PatientDemographics?> fetchPatientDemographics() async =>
      mergeDemographics(await fetchDemographicsBySource());

  /// Each source's demographics by source name (null where a source has
  /// none), so a caller can see where they disagree. Callers look sources
  /// up by name: a source that isn't there is null, never an error.
  Future<Map<String, PatientDemographics?>> fetchDemographicsBySource() async {
    final results = await Future.wait(
        demographicsSources.map(_fetchPatientDemographicsFrom));
    return {
      for (var i = 0; i < demographicsSources.length; i++)
        demographicsSources[i]: results[i],
    };
  }

  /// Field by field from the first source, in [demographicsSources] order,
  /// that has each one. A source missing from [bySource] is skipped.
  static PatientDemographics? mergeDemographics(
      Map<String, PatientDemographics?> bySource) {
    PatientDemographics? merged;
    for (final source in demographicsSources) {
      final d = bySource[source];
      merged = merged == null ? d : merged.fillFrom(d);
    }
    return merged == null || merged.isEmpty ? null : merged;
  }

  Future<PatientDemographics?> _fetchPatientDemographicsFrom(
      String source) async {
    try {
      final headers = await AuthTokenManager.getAuthHeaders();

      return await ApiClient.instance.getJson<PatientDemographics>(
        '/api/ehr/patient',
        query: {'source': source},
        headers: headers,
        parser: (json) => PatientDemographics.fromJson(
          json as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      return null;
    }
  }
  HealthRecord _toCernerAllergy(Map<String, dynamic> allergy) {
    return HealthRecord.single(
      id: (allergy['sourceRecordId'] ?? '').toString(),
      source: RecordSource.cerner,
      type: RecordType.allergy,
      title: _stringOrNull(allergy['substanceText']) ??
          _stringOrNull(allergy['substanceCode']) ??
          'Allergy',
      date: _parseDate(allergy['recordedDate']),
      status: _stringOrNull(allergy['clinicalStatus']),
    );
  }

  HealthRecord _toCernerCondition(Map<String, dynamic> condition) {
    return HealthRecord.single(
      id: (condition['sourceRecordId'] ?? '').toString(),
      source: RecordSource.cerner,
      type: RecordType.condition,
      title: _stringOrNull(condition['conditionText']) ??
          _firstCodeLabel(condition['conditionCodes']) ??
          'Condition',
      date: _parseDate(condition['onsetValue']) ??
          _parseDate(condition['recordedDate']),
      status: _stringOrNull(condition['clinicalStatus']),
    );
  }

  HealthRecord _toCernerEncounter(Map<String, dynamic> encounter) {
    return HealthRecord.single(
      id: (encounter['sourceRecordId'] ?? '').toString(),
      source: RecordSource.cerner,
      type: RecordType.appointment,
      title: _firstCodeLabel(encounter['encounterTypes']) ??
          _stringOrNull(encounter['classDisplay']) ??
          'Clinical encounter',
      date: _parseDate(encounter['periodStart']),
      status: _stringOrNull(encounter['status']),
    );
  }

  String? _firstCodeLabel(dynamic values) {
    if (values is! List) {
      return null;
    }

    for (final value in values) {
      if (value is! Map) {
        continue;
      }

      final display = _stringOrNull(value['display']);
      if (display != null) {
        return display;
      }

      final code = _stringOrNull(value['code']);
      if (code != null) {
        return code;
      }
    }

    return null;
  }

  String? _stringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

}
