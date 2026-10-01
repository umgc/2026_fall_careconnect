import '../models/identity_conflict.dart';

class IdentityConflictService {
  final bool useMock;
  IdentityConflictService({this.useMock = true});

  Future<List<IdentityConflict>> fetchPending() async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 400));
      return _mockPending;
    }
    // TODO wire to backend when ready, e.g.:
    // final env = await ApiClient.instance.getJson<Map<String, dynamic>>(
    //   '/v1/api/ehr/identity-conflicts?status=PENDING');
    // return ((env['resources'] as List?) ?? [])
    //     .map((j) => IdentityConflict.fromJson(j as Map<String, dynamic>))
    //     .toList();
    return const [];
  }

  Future<bool> resolve(int conflictId, {required bool accepted}) async {
    if (useMock) {
      await Future.delayed(const Duration(milliseconds: 400));
      return true;
    }
    // TODO wire to backend when ready, e.g.:
    // await ApiClient.instance.postJson(
    //   '/v1/api/ehr/identity-conflicts/$conflictId/resolve',
    //   body: {'status': accepted ? 'ACCEPTED' : 'REJECTED', 'resolvedBy': 'PATIENT'});
    return true;
  }

  static final _mockPending = <IdentityConflict>[
    IdentityConflict(
      id: 1,
      fieldName: 'date_of_birth',
      canonicalValueBefore: '05/14/1980',
      incomingValue: '05/14/1985',
      canonicalSourceLabel: 'Epic',
      incomingSourceLabel: 'Cerner',
      status: ConflictStatus.pending,
      detectedAt: DateTime(2026, 9, 26),
    ),
  ];
}