// WBS 3.6.1 (Team E, Milestone 3): the end-to-end workflows the suite covers.
//
// Each flow is one case in Software Test Plan §3.13 (TC-E2E-001..004). A flow
// stays blocked until the features it depends on are merged to team-e-develop
// (the entry criterion). When a feature lands, wire its steps in
// team_e_m3_workflows_e2e_test.dart and set `landed: true` here.
//
// The skip logic lives here, not in the test file, so that
// test/integration_test_support/team_e_m3_flows_test.dart (TC-E2E-005..009)
// can check it in CI, which does not run integration_test/.

class TeamEFlow {
  const TeamEFlow({
    required this.caseId,
    required this.title,
    required this.workPackage,
    required this.trace,
    required this.dependsOn,
    required this.landed,
    required this.steps,
    required this.passCriteria,
  });

  /// Test Plan case ID, e.g. `TC-E2E-001`.
  final String caseId;
  final String title;

  /// Level 3 work package in the Team Echo work plan.
  final String workPackage;

  /// SRS 1.4 requirements the flow exercises, or TBD where the SRS has none.
  final String trace;

  /// Build packages and PRs that must be merged before the flow can run.
  final List<String> dependsOn;

  /// True once everything in [dependsOn] is merged to team-e-develop.
  final bool landed;

  /// What the test does, in order. Mirrors docs/verification/3.6.1-e2e-workflow-suite.md.
  final List<String> steps;
  final String passCriteria;

  String get blockedReason =>
      'Blocked: waiting on ${dependsOn.join(', ')} to merge to team-e-develop';
}

/// Why [flow] is skipped, or null when it should run.
///
/// [enabled] is the `TEAM_E_M3_E2E` opt-in; [backendUrl] is `BACKEND_URL`,
/// the same define the app reads for its API base URL.
String? skipReasonFor(
  TeamEFlow flow, {
  required bool enabled,
  required String backendUrl,
}) {
  if (!enabled) return 'Opt-in: pass --dart-define=TEAM_E_M3_E2E=true';
  if (backendUrl.isEmpty) return 'Set --dart-define=BACKEND_URL';
  if (!flow.landed) return flow.blockedReason;
  return null;
}

/// Status as of 2026-09-30: none of the Medicare, record sharing or photo
/// capture features are on team-e-develop yet.
const teamEFlows = <TeamEFlow>[
  TeamEFlow(
    caseId: 'TC-E2E-001',
    title: 'Patient signs in, opens their Medicare data and reads a claim',
    workPackage: '6.2.40 Accessible Medicare Data Views',
    trace: 'FEAT-02 FR-MCR-13, FR-MCR-14 (TC-21.1, TC-21.2); FEAT-01 sign-in',
    dependsOn: ['3.1.6'],
    landed: false,
    steps: [
      'Sign in as the demo patient',
      'Open Medicare data from the health area',
      'The claims and visits list loads (from cache when offline)',
      'Open one claim and read its date, provider and amounts',
    ],
    passCriteria: 'Flow completes on Android and web',
  ),
  TeamEFlow(
    caseId: 'TC-E2E-002',
    title: 'User accepts or rejects each flagged reconciliation conflict',
    workPackage: '6.2.41 Cross-Source Reconciliation & Deduplication',
    trace: 'FR-EHR-07; accept/reject workflow has no SRS requirement (TBD)',
    dependsOn: ['3.2.3'],
    landed: false,
    steps: [
      'Seed two sources that disagree on one field',
      'Sign in as the patient; the conflict appears in the review list',
      'Accept one conflict and reject another',
      'Each choice is applied and an audit row is written',
      'A medication conflict leaves the medication list unchanged until acted on (FR-EHR-07)',
    ],
    passCriteria: 'Each choice is applied and audited',
  ),
  TeamEFlow(
    caseId: 'TC-E2E-003',
    title: 'Photo capture creates a medication with the right type',
    workPackage: '6.2.42 Medication Photo Capture',
    trace: 'Handoff item 1.10; no SRS requirement (TBD)',
    dependsOn: ['3.4.3', 'PR #207 (KI-05)'],
    landed: false,
    steps: [
      'Sign in as the patient and start medication photo capture',
      'Submit the fixture label image',
      'Review the extracted fields and correct one',
      'Confirm; the medication is saved',
      'The saved type uses the backend name, e.g. OVER_THE_COUNTER (KI-05)',
    ],
    passCriteria: 'Saved medication matches the confirmed values; types use backend names',
  ),
  TeamEFlow(
    caseId: 'TC-E2E-004',
    title: 'Patient shares data with a caregiver who reads it in-app',
    workPackage: '6.2.43 Secure Sharing Controls',
    trace: 'No SRS requirement for record sharing or revoke (TBD)',
    dependsOn: ['3.3.3'],
    landed: false,
    steps: [
      'Sign in as the patient and share selected records with the demo caregiver',
      'Sign in as the caregiver; only the selected records are visible',
      'Patient revokes the share',
      'The caregiver can no longer open the records',
    ],
    passCriteria: 'Flow completes end to end',
  ),
];
