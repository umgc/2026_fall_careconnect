import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../services/api_service.dart';
import '../../../../services/auth_service.dart';
import '../../../../config/env_constant.dart';

/// Client for the patient's Medicare sharing screen (WBS 6.2.59, #323).
///
/// Contract (6.2.56 consent API, merged in #325):
///   GET    /v1/api/caregiver-patient-links/patients/{patientUserId}/caregivers
///          -> [ { caregiverUserId, caregiverName, caregiverEmail, status, ... } ]
///   GET    /v1/api/v3/consent/medicare-view?patientUserId=&granteeUserId=
///          -> { granted, explicitGrant, effectiveConsent, ... }
///   POST   /v1/api/v3/consent/medicare-view   { granteeUserId, granteeRole } -> 201
///   DELETE /v1/api/v3/consent/medicare-view   { granteeUserId }              -> 200
///
/// Medicare View has no care-circle fallback (BR-02), so `granted` is exactly
/// what the patient chose. Only ACTIVE links are listed: a pending or ended
/// link can't read Medicare data whatever the switch says.
///
/// Like MedicareConnectService, a 401 refreshes the token once and retries.
class MedicareSharingService {
  MedicareSharingService();

  /// Swap in a fake for widget tests.
  static MedicareSharingService instance = MedicareSharingService();

  /// The signed-in user's id (the patient's user id). Replaceable in tests.
  static Future<int?> Function() currentUserId =
      () async => (await AuthService.getCurrentUser())?.id;

  /// The signed-in user's role. Replaceable in tests.
  static Future<String?> Function() currentUserRole =
      () async => (await AuthService.getCurrentUser())?.role;

  static String get _host => '${getBackendBaseUrl()}/v1/api';

  static Future<http.Response> _send(
      Future<http.Response> Function(Map<String, String> headers)
          request) async {
    final first = await request(await ApiService.getAuthHeaders());
    if (first.statusCode != 401) return first;
    try {
      final refreshed = await AuthService.forceRefreshToken();
      if (refreshed == null) return first;
    } catch (_) {
      return first;
    }
    return request(await ApiService.getAuthHeaders());
  }

  /// The patient's actively linked caregivers, each with their current
  /// Medicare sharing state. Throws [MedicareSharingException].
  Future<List<SharingCaregiver>> load() async {
    final patientUserId = await currentUserId();
    if (patientUserId == null) {
      throw const MedicareSharingException(MedicareSharingError.signedOut);
    }
    // The links endpoint answers any signed-in user for their own id, so a
    // caregiver would see an empty list rather than being told (DEF-MCR-31).
    final role = await currentUserRole();
    if (role != null && role.toUpperCase() != 'PATIENT') {
      throw const MedicareSharingException(MedicareSharingError.notPatient);
    }

    final http.Response resp;
    try {
      resp = await _send((h) => http.get(
          Uri.parse(
              '$_host/caregiver-patient-links/patients/$patientUserId/caregivers'),
          headers: h));
    } catch (_) {
      throw const MedicareSharingException(MedicareSharingError.network);
    }
    _throwFor(resp.statusCode);

    final List<_Link> links;
    try {
      final body = jsonDecode(resp.body);
      if (body is! List) throw const FormatException();
      links =
          body.whereType<Map<String, dynamic>>().map(_Link.fromJson).toList();
    } catch (_) {
      throw const MedicareSharingException(MedicareSharingError.server);
    }

    // One row per caregiver: a caregiver can appear on more than one link.
    final byUser = <int, _Link>{};
    for (final link in links) {
      if (link.userId == null || !link.active) continue;
      byUser.putIfAbsent(link.userId!, () => link);
    }

    final result = <SharingCaregiver>[];
    for (final link in byUser.values) {
      final shared = await _isShared(patientUserId, link.userId!);
      result.add(SharingCaregiver(
        userId: link.userId!,
        name: link.name,
        email: link.email,
        shared: shared,
      ));
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<bool> _isShared(int patientUserId, int caregiverUserId) async {
    final http.Response resp;
    try {
      resp = await _send((h) => http.get(
          Uri.parse('$_host/v3/consent/medicare-view')
              .replace(queryParameters: {
            'patientUserId': '$patientUserId',
            'granteeUserId': '$caregiverUserId',
          }),
          headers: h));
    } catch (_) {
      throw const MedicareSharingException(MedicareSharingError.network);
    }
    _throwFor(resp.statusCode);
    try {
      final body = jsonDecode(resp.body);
      if (body is! Map || body['granted'] is! bool) {
        throw const FormatException();
      }
      return body['granted'] as bool;
    } catch (_) {
      throw const MedicareSharingException(MedicareSharingError.server);
    }
  }

  /// Turns sharing on (grant) or off (revoke). True when the backend confirms.
  Future<bool> setShared(int caregiverUserId, bool shared) async {
    try {
      final resp = await _send((h) {
        final headers = {...h, 'Content-Type': 'application/json'};
        final url = Uri.parse('$_host/v3/consent/medicare-view');
        return shared
            ? http.post(url,
                headers: headers,
                body: jsonEncode({
                  'granteeUserId': caregiverUserId,
                  'granteeRole': 'CAREGIVER'
                }))
            : http.delete(url,
                headers: headers,
                body: jsonEncode({'granteeUserId': caregiverUserId}));
      });
      return resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  static void _throwFor(int status) {
    if (status == 200) return;
    if (status == 401) {
      throw const MedicareSharingException(MedicareSharingError.signedOut);
    }
    if (status == 403) {
      throw const MedicareSharingException(MedicareSharingError.notPatient);
    }
    throw const MedicareSharingException(MedicareSharingError.server);
  }
}

class _Link {
  final int? userId;
  final String name;
  final String? email;
  final bool active;

  const _Link(this.userId, this.name, this.email, this.active);

  factory _Link.fromJson(Map<String, dynamic> json) {
    final id = json['caregiverUserId'];
    final name = json['caregiverName'];
    final email = json['caregiverEmail'];
    // A missing status is treated as active: older responses didn't send it.
    final status = json['status']?.toString().toUpperCase();
    return _Link(
      id is int ? id : int.tryParse('$id'),
      name is String && name.trim().isNotEmpty ? name.trim() : 'Caregiver',
      email is String && email.trim().isNotEmpty ? email.trim() : null,
      status == null || status == 'ACTIVE',
    );
  }
}

/// One linked caregiver and whether the patient shares Medicare with them.
class SharingCaregiver {
  final int userId;
  final String name;
  final String? email;
  final bool shared;

  const SharingCaregiver({
    required this.userId,
    required this.name,
    this.email,
    required this.shared,
  });

  SharingCaregiver copyWith({bool? shared}) => SharingCaregiver(
      userId: userId, name: name, email: email, shared: shared ?? this.shared);
}

enum MedicareSharingError { signedOut, notPatient, network, server }

class MedicareSharingException implements Exception {
  final MedicareSharingError error;
  const MedicareSharingException(this.error);
}
