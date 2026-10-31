import 'package:dio/dio.dart';

import '../../../../services/api_client.dart';
import '../models/health_record.dart';
import 'ehr_resource_mapper.dart';

class AthenaFetchResult {
  final List<HealthRecord> records;

  /// False when the read failed or stopped part way through the pages.
  final bool complete;

  /// Why athenahealth could not be read, when it could not.
  final AthenaReadProblem? problem;

  const AthenaFetchResult(
      {required this.records, this.complete = true, this.problem});
}

/// What the screen tells the patient when an athenahealth read fails.
enum AthenaReadProblem {
  /// 409 NOT_CONNECTED (no consent or no linked chart yet), or 404 when
  /// the server has athena turned off.
  notConnected,

  /// 403 (not a patient): the screen says nothing, as there is nothing
  /// this user can do. A server with athena off (404) reads as
  /// [notConnected], as Epic does, so the patient is still offered Connect.
  hidden,

  /// Anything else.
  unreachable,
}

/// An athenahealth read that failed (offline, server error), as opposed to a
/// record that isn't there.
class AthenaReadException implements Exception {
  const AthenaReadException();
}

/// Reads the patient's athenahealth records from AthenaController.
///
///   GET /api/athena/resources?page&size&from&to
///       -> { items: [EhrResourceListItem], page, size, hasNext }
///   GET /api/athena/resources/{type}/{id}
///       -> the list item's fields plus `resource` (the stored FHIR JSON)
///
/// Pages until `hasNext` is false. The backend already excludes the Patient
/// row and scopes every read to the caller.
class AthenaDataService {
  /// Largest page the backend serves (AthenaController.MAX_PAGE_SIZE).
  static const pageSize = 100;

  /// Stop after this many pages so a misbehaving server can't loop forever.
  static const maxPages = 50;

  Future<AthenaFetchResult> fetchRecords({DateTime? from, DateTime? to}) async {
    final records = <HealthRecord>[];
    for (var page = 0; page < maxPages; page++) {
      final Map<String, dynamic> body;
      try {
        body = await ApiClient.instance.getJson<Map<String, dynamic>>(
          '/api/athena/resources',
          query: {
            'page': page,
            'size': pageSize,
            if (from != null) 'from': _isoDate(from),
            if (to != null) 'to': _isoDate(to),
          },
          parser: (json) =>
              json is Map<String, dynamic> ? json : <String, dynamic>{},
        );
      } on DioException catch (e) {
        return AthenaFetchResult(
            records: records, complete: false, problem: _problemFor(e));
      } catch (_) {
        return AthenaFetchResult(
            records: records,
            complete: false,
            problem: AthenaReadProblem.unreachable);
      }
      final items = body['items'];
      if (items is List) {
        records.addAll(items
            .whereType<Map<String, dynamic>>()
            .map(EhrResourceMapper.toHealthRecord)
            .whereType<HealthRecord>());
      }
      if (body['hasNext'] != true) {
        return AthenaFetchResult(records: records);
      }
    }
    return AthenaFetchResult(
        records: records,
        complete: false,
        problem: AthenaReadProblem.unreachable);
  }

  /// One record with its FHIR resource, or null when there is no such record
  /// to read (404, 409 not connected, 403). Throws [AthenaReadException] when
  /// the read itself fails (offline, server error), so the page can say it
  /// couldn't load the record rather than that the record was removed.
  Future<Map<String, dynamic>?> fetchResource(String type, String id) async {
    try {
      return await ApiClient.instance.getJson<Map<String, dynamic>?>(
        '/api/athena/resources/${Uri.encodeComponent(type)}/${Uri.encodeComponent(id)}',
        parser: (json) => json is Map<String, dynamic> ? json : null,
      );
    } on DioException catch (e) {
      if (_problemFor(e) == AthenaReadProblem.unreachable) {
        throw const AthenaReadException();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static AthenaReadProblem _problemFor(DioException e) {
    final inner = e.error;
    final status =
        e.response?.statusCode ?? (inner is ApiException ? inner.status : null);
    switch (status) {
      case 409:
      case 404:
        return AthenaReadProblem.notConnected;
      case 403:
        return AthenaReadProblem.hidden;
      default:
        return AthenaReadProblem.unreachable;
    }
  }

  static String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
