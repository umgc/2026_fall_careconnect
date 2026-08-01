import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_token_manager.dart';
import '../config/env_constant.dart';

/// Thrown when an STML request fails. [message] is safe to show directly
/// to the user.
class StmlException implements Exception {
  final String message;
  StmlException(this.message);

  @override
  String toString() => message;
}

class StmlCard {
  final String type; // RECALL, APPOINTMENT, ACTION_ITEM, MEDICATION
  final String headline;
  final String detail;
  final String sourceType;
  final DateTime? timestamp;

  const StmlCard({
    required this.type,
    required this.headline,
    required this.detail,
    required this.sourceType,
    this.timestamp,
  });

  factory StmlCard.fromJson(Map<String, dynamic> json) {
    return StmlCard(
      type: json['type'] as String? ?? '',
      headline: json['headline'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      sourceType: json['sourceType'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }
}

/// STML-2: the Daily Memory Brief shown on app open.
class StmlBrief {
  final int patientId;
  final DateTime? generatedAt;
  final List<StmlCard> cards;
  final String disclaimer;

  const StmlBrief({
    required this.patientId,
    required this.cards,
    required this.disclaimer,
    this.generatedAt,
  });

  factory StmlBrief.fromJson(Map<String, dynamic> json) {
    return StmlBrief(
      patientId: (json['patientId'] as num?)?.toInt() ?? 0,
      generatedAt: json['generatedAt'] != null
          ? DateTime.tryParse(json['generatedAt'] as String)
          : null,
      cards: (json['cards'] as List<dynamic>? ?? [])
          .map((c) => StmlCard.fromJson(c as Map<String, dynamic>))
          .toList(),
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }
}

class StmlRecallSource {
  final String sourceType;
  final String summary;
  final String date;

  const StmlRecallSource({
    required this.sourceType,
    required this.summary,
    required this.date,
  });

  factory StmlRecallSource.fromJson(Map<String, dynamic> json) {
    return StmlRecallSource(
      sourceType: json['sourceType'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      date: json['date'] as String? ?? '',
    );
  }
}

/// STML-1: a plain-language recall answer with source citations.
class StmlRecallResult {
  final String answer;
  final List<StmlRecallSource> sources;
  final String disclaimer;

  const StmlRecallResult({
    required this.answer,
    required this.sources,
    required this.disclaimer,
  });

  factory StmlRecallResult.fromJson(Map<String, dynamic> json) {
    return StmlRecallResult(
      answer: json['answer'] as String? ?? '',
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((s) => StmlRecallSource.fromJson(s as Map<String, dynamic>))
          .toList(),
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }
}

class StmlCheckInItem {
  final String type;
  final String summary;
  final String date;
  final String source;

  const StmlCheckInItem({
    required this.type,
    required this.summary,
    required this.date,
    required this.source,
  });

  factory StmlCheckInItem.fromJson(Map<String, dynamic> json) {
    return StmlCheckInItem(
      type: json['type'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      date: json['date'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }
}

/// STML-3: caregiver check-in preparation view (consent-gated).
class StmlCheckIn {
  final bool consentGranted;
  final List<StmlCheckInItem> notes;
  final List<StmlCheckInItem> pendingItems;
  final String disclaimer;

  const StmlCheckIn({
    required this.consentGranted,
    required this.notes,
    required this.pendingItems,
    required this.disclaimer,
  });

  factory StmlCheckIn.fromJson(Map<String, dynamic> json) {
    return StmlCheckIn(
      consentGranted: json['consentGranted'] as bool? ?? false,
      notes: (json['notes'] as List<dynamic>? ?? [])
          .map((n) => StmlCheckInItem.fromJson(n as Map<String, dynamic>))
          .toList(),
      pendingItems: (json['pendingItems'] as List<dynamic>? ?? [])
          .map((n) => StmlCheckInItem.fromJson(n as Map<String, dynamic>))
          .toList(),
      disclaimer: json['disclaimer'] as String? ?? '',
    );
  }
}

class StmlSearchResult {
  final String sourceType;
  final String content;
  final String sender;
  final String date;
  final String conversationId;

  const StmlSearchResult({
    required this.sourceType,
    required this.content,
    required this.sender,
    required this.date,
    required this.conversationId,
  });

  factory StmlSearchResult.fromJson(Map<String, dynamic> json) {
    return StmlSearchResult(
      sourceType: json['sourceType'] as String? ?? '',
      content: json['content'] as String? ?? '',
      sender: json['sender'] as String? ?? '',
      date: json['date'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
    );
  }
}

/// STML-4: recall history search results.
class StmlSearchResults {
  final int totalResults;
  final List<StmlSearchResult> results;

  const StmlSearchResults({required this.totalResults, required this.results});

  factory StmlSearchResults.fromJson(Map<String, dynamic> json) {
    return StmlSearchResults(
      totalResults: (json['totalResults'] as num?)?.toInt() ?? 0,
      results: (json['results'] as List<dynamic>? ?? [])
          .map((r) => StmlSearchResult.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Client for the STML (Short-Term Memory Support) endpoints (SRS §6).
///
/// All four endpoints are gated server-side by RBAC scope checks and return
/// 403 when the caller isn't authorized for the requested patient.
class StmlService {
  static String get _baseUrl => '${getBackendBaseUrl()}/v1/api/stml';

  static Future<Map<String, String>> _headers() async {
    final headers = await AuthTokenManager.getAuthHeaders();
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  static StmlException _errorFor(int statusCode) {
    switch (statusCode) {
      case 401:
        return StmlException('Please log in again.');
      case 403:
        return StmlException(
          "You aren't authorized to view this patient's information.",
        );
      default:
        return StmlException('Something went wrong. Please try again.');
    }
  }

  /// STML-2: the Daily Memory Brief shown on app open.
  static Future<StmlBrief> getDailyBrief(int patientId) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse('$_baseUrl/patients/$patientId/brief'),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw StmlException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) throw _errorFor(response.statusCode);
    return StmlBrief.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// STML-1: "What did we discuss?" recall.
  static Future<StmlRecallResult> recall({
    required int patientId,
    required String question,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/patients/$patientId/recall'),
            headers: await _headers(),
            body: jsonEncode({'question': question}),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw StmlException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) throw _errorFor(response.statusCode);
    return StmlRecallResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// STML-3: caregiver check-in preparation view. [caregiverId] must be the
  /// requesting caregiver's own ID; the server enforces consent gating.
  static Future<StmlCheckIn> getCheckIn({
    required int patientId,
    required int caregiverId,
  }) async {
    final http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(
              '$_baseUrl/patients/$patientId/checkin?caregiverId=$caregiverId',
            ),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw StmlException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) throw _errorFor(response.statusCode);
    return StmlCheckIn.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// STML-4: search recall history by keyword, sender, or date.
  static Future<StmlSearchResults> search({
    required int patientId,
    String? keyword,
    String? sender,
    String? fromDate,
    String? toDate,
  }) async {
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$_baseUrl/patients/$patientId/search'),
            headers: await _headers(),
            body: jsonEncode({
              if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
              if (sender != null && sender.isNotEmpty) 'sender': sender,
              if (fromDate != null && fromDate.isNotEmpty) 'fromDate': fromDate,
              if (toDate != null && toDate.isNotEmpty) 'toDate': toDate,
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw StmlException(
        'Could not reach the server. Check your connection and try again.',
      );
    }
    if (response.statusCode != 200) throw _errorFor(response.statusCode);
    return StmlSearchResults.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
