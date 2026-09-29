// WBS 3.6.1 (Team E, Milestone 3): the end-to-end workflows the suite covers.
//
// Each flow comes from one STP-M3-E test requirement in
// docs/verification/M3-STP-test-requirements-team-e.md. A flow stays blocked
// until the features it depends on are merged to team-e-develop (the STP entry
// criterion). When a feature lands, wire its steps in
// team_e_m3_workflows_e2e_test.dart and set `landed: true` here.

class TeamEFlow {
  const TeamEFlow({
    required this.stpId,
    required this.title,
    required this.workPackage,
    required this.dependsOn,
    required this.landed,
    required this.steps,
    required this.passCriteria,
  });

  /// STP-M3-E requirement this flow verifies, e.g. `STP-M3-E-16`.
  final String stpId;
  final String title;

  /// Level 3 work package in the Team Echo work plan.
  final String workPackage;

  /// M3 build packages that must be merged before the flow can run.
  final List<String> dependsOn;

  /// True once every package in [dependsOn] is merged to team-e-develop.
  final bool landed;

  /// What the test does, in order. Mirrors docs/verification/3.6.1-e2e-workflow-suite.md.
  final List<String> steps;
  final String passCriteria;

  String get blockedReason =>
      'Blocked: waiting on ${dependsOn.join(', ')} to merge to team-e-develop';
}

/// Status as of 2026-09-29: none of the Medicare, sharing or photo capture
/// endpoints exist on team-e-develop yet (canonical schema is in PR #209).
const teamEFlows = <TeamEFlow>[
  TeamEFlow(
    stpId: 'STP-M3-E-16',
    title: 'Patient signs in, opens their Medicare data and reads a claim',
    workPackage: '6.2.40 Accessible Medicare Data Views',
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
    stpId: 'STP-M3-E-21',
    title: 'User accepts or rejects each flagged reconciliation conflict',
    workPackage: '6.2.41 Cross-Source Reconciliation & Deduplication',
    dependsOn: ['3.2.3'],
    landed: false,
    steps: [
      'Seed two sources that disagree on one field',
      'Sign in as the patient; the conflict appears in the review list',
      'Accept one conflict and reject another',
      'Each choice is applied and an audit row is written',
      'A medication conflict leaves the medication list unchanged until acted on (STP-M3-E-20)',
    ],
    passCriteria: 'Each choice is applied and audited',
  ),
  TeamEFlow(
    stpId: 'STP-M3-E-22',
    title: 'Photo capture creates a medication with the right type',
    workPackage: '6.2.42 Medication Photo Capture',
    dependsOn: ['3.4.3'],
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
    stpId: 'STP-M3-E-27',
    title: 'Patient shares data with a caregiver who reads it in-app',
    workPackage: '6.2.43 Secure Sharing Controls',
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
