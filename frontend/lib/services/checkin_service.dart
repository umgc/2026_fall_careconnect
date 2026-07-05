import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/env_constant.dart';
import 'auth_token_manager.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/answer_dto.dart';

class CheckInSummary {
  final int checkInId;
  final int patientId;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final int questionCount;

  const CheckInSummary({
    required this.checkInId,
    required this.patientId,
    required this.createdAt,
    required this.submittedAt,
    required this.reviewedAt,
    required this.questionCount,
  });
}

class CheckInAnswerDetail {
  final int questionId;
  final String prompt;
  final String type;
  final bool required;
  final int ordinal;
  final String? valueText;
  final bool? valueBoolean;
  final num? valueNumber;
  final DateTime? answeredAt;

  const CheckInAnswerDetail({
    required this.questionId,
    required this.prompt,
    required this.type,
    required this.required,
    required this.ordinal,
    required this.valueText,
    required this.valueBoolean,
    required this.valueNumber,
    required this.answeredAt,
  });
}

class CheckInDetail {
  final int checkInId;
  final int patientId;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String status;
  final List<CheckInAnswerDetail> answers;

  const CheckInDetail({
    required this.checkInId,
    required this.patientId,
    required this.createdAt,
    required this.submittedAt,
    required this.reviewedAt,
    required this.status,
    required this.answers,
  });
}

class CheckInPage {
  final List<CheckInSummary> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  const CheckInPage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });
}

/// Service that handles creating and retrieving patient check-ins.
/// Used by both patient and caregiver dashboards.
class CheckinService {
  static String get _baseUrl => '${getBackendBaseUrl()}/api/checkins';
  static String get _questionsUrl => '${getBackendBaseUrl()}/api/questions';

  static int? _parseIntId(String raw) => int.tryParse(raw.trim());

  static List<int> _extractQuestionIds(dynamic decoded) {
    if (decoded is! List) return const [];

    final ids = <int>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final rawId = item['id'];
      if (rawId is int) {
        ids.add(rawId);
      } else if (rawId is num) {
        ids.add(rawId.toInt());
      } else if (rawId is String) {
        final parsed = int.tryParse(rawId);
        if (parsed != null) ids.add(parsed);
      }
    }
    return ids;
  }

  static Future<List<int>> _fetchActiveQuestionIds() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Accept'] = 'application/json';

    final url = Uri.parse(_questionsUrl).replace(
      queryParameters: const {'active': 'true'},
    );
    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(response.body);
    return _extractQuestionIds(decoded);
  }

  /// Adds a new check-in for a patient.
  /// Uses the snapshot creation contract: patientId + selectedQuestionIds.
  static Future<bool> addCheckin(String patientId, String _caregiverId) async {
    final parsedPatientId = _parseIntId(patientId);
    if (parsedPatientId == null) return false;

    final selectedQuestionIds = await _fetchActiveQuestionIds();
    if (selectedQuestionIds.isEmpty) return false;

    final url = Uri.parse(_baseUrl);
    final body = jsonEncode({
      'patientId': parsedPatientId,
      'selectedQuestionIds': selectedQuestionIds,
    });

    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http.post(
      url,
      headers: headers,
      body: body,
    );

    return response.statusCode == 201 || response.statusCode == 200;
  }

  /// Creates a check-in using explicit question IDs and returns the new check-in ID.
  /// Returns null if the request fails or the response does not include an ID.
  static Future<int?> createCheckinWithSelectedQuestions({
    required String patientId,
    required List<int> selectedQuestionIds,
  }) async {
    final parsedPatientId = _parseIntId(patientId);
    if (parsedPatientId == null || selectedQuestionIds.isEmpty) return null;

    final url = Uri.parse(_baseUrl);
    final body = jsonEncode({
      'patientId': parsedPatientId,
      'selectedQuestionIds': selectedQuestionIds,
    });

    final headers = await AuthTokenManager.getAuthHeaders();
    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode != 201 && response.statusCode != 200) return null;

    final rawBody = response.body.trim();
    if (rawBody.isEmpty) return null;

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) return null;

    final rawId = decoded['checkInId'] ?? decoded['checkinId'] ?? decoded['id'];
    if (rawId is int) return rawId;
    if (rawId is num) return rawId.toInt();
    if (rawId is String) return int.tryParse(rawId);
    return null;
  }

  static DateTime? _tryParseDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static CheckInSummary? _toSummary(dynamic raw) {
    if (raw is! Map<String, dynamic>) return null;
    final rawCheckInId = raw['checkInId'];
    final rawPatientId = raw['patientId'];
    final checkInId = rawCheckInId is int
        ? rawCheckInId
        : int.tryParse(rawCheckInId?.toString() ?? '');
    final patientId = rawPatientId is int
        ? rawPatientId
        : int.tryParse(rawPatientId?.toString() ?? '');
    if (checkInId == null || patientId == null) return null;

    return CheckInSummary(
      checkInId: checkInId,
      patientId: patientId,
      createdAt: _tryParseDate(raw['createdAt']),
      submittedAt: _tryParseDate(raw['submittedAt']),
      reviewedAt: _tryParseDate(raw['reviewedAt']),
      questionCount: raw['questionCount'] is int
          ? raw['questionCount'] as int
          : int.tryParse(raw['questionCount']?.toString() ?? '') ?? 0,
    );
  }

  static Future<List<CheckInSummary>> fetchCheckInsForPatient(
    String patientId,
  ) async {
    final parsedPatientId = _parseIntId(patientId);
    if (parsedPatientId == null) return const [];

    final url = Uri.parse('$_baseUrl/patients/$parsedPatientId');
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) return const [];

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return const [];
    return decoded.map(_toSummary).whereType<CheckInSummary>().toList();
  }

  static Future<CheckInPage?> fetchCheckInsForPatientFiltered({
    required String patientId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int page = 0,
    int size = 20,
  }) async {
    final parsedPatientId = _parseIntId(patientId);
    if (parsedPatientId == null) return null;

    final query = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
    };
    if (status != null && status.isNotEmpty && status != 'all') {
      query['status'] = status;
    }
    if (startDate != null) {
      query['startDate'] =
          '${startDate.year.toString().padLeft(4, '0')}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    }
    if (endDate != null) {
      query['endDate'] =
          '${endDate.year.toString().padLeft(4, '0')}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
    }

    final url = Uri.parse('$_baseUrl/patients/$parsedPatientId/search')
        .replace(queryParameters: query);
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final rawItems = decoded['items'];
    final items = rawItems is List
        ? rawItems.map(_toSummary).whereType<CheckInSummary>().toList()
        : const <CheckInSummary>[];
    return CheckInPage(
      items: items,
      page: decoded['page'] is int
          ? decoded['page'] as int
          : int.tryParse(decoded['page']?.toString() ?? '') ?? 0,
      size: decoded['size'] is int
          ? decoded['size'] as int
          : int.tryParse(decoded['size']?.toString() ?? '') ?? size,
      totalElements: decoded['totalElements'] is int
          ? decoded['totalElements'] as int
          : int.tryParse(decoded['totalElements']?.toString() ?? '') ??
              items.length,
      totalPages: decoded['totalPages'] is int
          ? decoded['totalPages'] as int
          : int.tryParse(decoded['totalPages']?.toString() ?? '') ?? 0,
    );
  }

  static Future<CheckInDetail?> fetchCheckInDetail(int checkInId) async {
    final url = Uri.parse('$_baseUrl/$checkInId/detail');
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final response = await http.get(url, headers: headers);
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final rawAnswers = decoded['answers'];
    final answers = rawAnswers is List
        ? rawAnswers
            .whereType<Map<String, dynamic>>()
            .map((entry) {
              final rawQuestionId = entry['questionId'];
              final questionId = rawQuestionId is int
                  ? rawQuestionId
                  : int.tryParse(rawQuestionId?.toString() ?? '');
              if (questionId == null) return null;

              return CheckInAnswerDetail(
                questionId: questionId,
                prompt: entry['prompt']?.toString() ?? '',
                type: entry['type']?.toString() ?? '',
                required: entry['required'] == true,
                ordinal: entry['ordinal'] is int
                    ? entry['ordinal'] as int
                    : int.tryParse(entry['ordinal']?.toString() ?? '') ?? 0,
                valueText: entry['valueText']?.toString(),
                valueBoolean: entry['valueBoolean'] is bool
                    ? entry['valueBoolean'] as bool
                    : null,
                valueNumber: entry['valueNumber'] is num
                    ? entry['valueNumber'] as num
                    : num.tryParse(entry['valueNumber']?.toString() ?? ''),
                answeredAt: _tryParseDate(entry['answeredAt']),
              );
            })
            .whereType<CheckInAnswerDetail>()
            .toList()
        : const <CheckInAnswerDetail>[];

    final rawCheckInId = decoded['checkInId'];
    final rawPatientId = decoded['patientId'];
    final parsedCheckInId = rawCheckInId is int
        ? rawCheckInId
        : int.tryParse(rawCheckInId?.toString() ?? '');
    final parsedPatientId = rawPatientId is int
        ? rawPatientId
        : int.tryParse(rawPatientId?.toString() ?? '');
    if (parsedCheckInId == null || parsedPatientId == null) return null;

    return CheckInDetail(
      checkInId: parsedCheckInId,
      patientId: parsedPatientId,
      createdAt: _tryParseDate(decoded['createdAt']),
      submittedAt: _tryParseDate(decoded['submittedAt']),
      reviewedAt: _tryParseDate(decoded['reviewedAt']),
      status: decoded['status']?.toString() ?? 'draft',
      answers: answers,
    );
  }

  /// Fetches the total number of check-ins tied to a caregiver.
  /// Example use: final count = await CheckinService.getCheckinCount(caregiverId);
  static Future<int> getCheckinCount(String caregiverId) async {
    final url = Uri.parse('$_baseUrl/count?caregiverId=$caregiverId');
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Accept'] = 'application/json';
    final response = await http.get(url, headers: headers);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['count'] ?? 0;
    } else {
      return 0;
    }
  }

  /// Submits answers for a check-in.
  /// POST /api/checkins/{checkInId}/answers
  static Future<SubmitAnswersResponseDTO> submitAnswers({
    required int checkInId,
    required SubmitAnswersRequestDTO request,
  }) async {
    final url = Uri.parse('$_baseUrl/$checkInId/answers');
    final body = jsonEncode(request.toJson());

    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';

    final response = await http.post(
      url,
      headers: headers,
      body: body,
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return SubmitAnswersResponseDTO.fromJson(data);
    } else {
      // Parse error response from backend
      String errorMessage = 'Failed to submit answers: ${response.statusCode}';
      try {
        final errorData = jsonDecode(response.body);
        if (errorData is Map && errorData['error'] != null) {
          errorMessage = errorData['error'];
        }
      } catch (_) {
        // Failed to parse error response, use default message
      }
      throw Exception(errorMessage);
    }
  }
}
