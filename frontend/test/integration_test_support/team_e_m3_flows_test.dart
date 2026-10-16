// WBS 3.6.1 (Team E, Milestone 3): checks for the end-to-end suite's flow
// catalog and skip logic, Software Test Plan §3.13 (TC-E2E-005..009).
//
// CI does not run integration_test/, so these unit tests are what keeps the
// suite's guards honest: a flow is skipped until it is opted in, has a
// backend, and has landed, and only then reaches the wired/unwired check.

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/team_e_m3/flows.dart';

const _url = 'http://10.0.2.2:8081';

TeamEFlow _landed(TeamEFlow f) => TeamEFlow(
      caseId: f.caseId,
      title: f.title,
      workPackage: f.workPackage,
      trace: f.trace,
      dependsOn: f.dependsOn,
      landed: true,
      steps: f.steps,
      passCriteria: f.passCriteria,
    );

void main() {
  test('TC-E2E-005: every flow has a unique case ID, dependencies, steps and '
      'pass criteria', () {
    final ids = teamEFlows.map((f) => f.caseId).toList();
    expect(ids, [
      'TC-E2E-001',
      'TC-E2E-002',
      'TC-E2E-003',
      'TC-E2E-004',
      'TC-E2E-010',
    ]);
    expect(ids.toSet().length, ids.length);
    for (final f in teamEFlows) {
      expect(f.caseId, matches(RegExp(r'^TC-E2E-\d{3}$')));
      expect(f.title, isNotEmpty, reason: f.caseId);
      expect(f.workPackage, isNotEmpty, reason: f.caseId);
      expect(f.trace, isNotEmpty, reason: f.caseId);
      expect(f.dependsOn, isNotEmpty, reason: f.caseId);
      expect(f.steps, isNotEmpty, reason: f.caseId);
      expect(f.passCriteria, isNotEmpty, reason: f.caseId);
    }
  });

  test('TC-E2E-006: without the opt-in every flow is skipped, landed or not, '
      'and the reason names TEAM_E_M3_E2E', () {
    for (final f in [...teamEFlows, ...teamEFlows.map(_landed)]) {
      final reason = skipReasonFor(f, enabled: false, backendUrl: _url);
      expect(reason, contains('TEAM_E_M3_E2E=true'), reason: f.caseId);
    }
  });

  test('TC-E2E-007: opted in without BACKEND_URL, every flow is skipped and '
      'the reason names BACKEND_URL', () {
    for (final f in [...teamEFlows, ...teamEFlows.map(_landed)]) {
      final reason = skipReasonFor(f, enabled: true, backendUrl: '');
      expect(reason, 'Set --dart-define=BACKEND_URL', reason: f.caseId);
    }
  });

  test('TC-E2E-008: opted in with a backend, a flow that has not landed is '
      'skipped and the reason names each dependency', () {
    for (final f in teamEFlows.where((f) => !f.landed)) {
      final reason = skipReasonFor(f, enabled: true, backendUrl: _url);
      expect(reason, startsWith('Blocked: waiting on '), reason: f.caseId);
      for (final d in f.dependsOn) {
        expect(reason, contains(d), reason: '${f.caseId} / $d');
      }
    }
    final photo = teamEFlows.singleWhere((f) => f.caseId == 'TC-E2E-003');
    // PR #207 (KI-05) merged on 2026-09-30, so photo capture now waits only on 3.4.3.
    expect(photo.dependsOn, ['3.4.3']);
  });

  test('TC-E2E-009: opted in with a backend, a landed flow is not skipped', () {
    for (final f in teamEFlows.map(_landed)) {
      expect(skipReasonFor(f, enabled: true, backendUrl: _url), isNull,
          reason: f.caseId);
    }
  });
}
