// WBS 3.6.1 (Team E, Milestone 3): end-to-end workflow suite.
//
// One test per end-to-end case in Software Test Plan §3.13 (TC-E2E-001..004);
// the flows and their dependencies are listed in team_e_m3/flows.dart.
//
// The suite is opt-in so it never runs in another team's emulator job by
// accident. BACKEND_URL is the define the app itself reads, so the app under
// test talks to the same backend. Run it with:
//   flutter test integration_test/team_e_m3_workflows_e2e_test.dart \
//     --dart-define=TEAM_E_M3_E2E=true \
//     --dart-define=BACKEND_URL=http://10.0.2.2:8081
//
// A flow whose features have not merged yet is skipped with the reason. A flow
// marked `landed` but not wired yet fails, so it cannot pass by accident.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'team_e_m3/flows.dart';

const _enabled = bool.fromEnvironment('TEAM_E_M3_E2E');
const _backendUrl = String.fromEnvironment('BACKEND_URL');

/// Step implementations, keyed by case ID. Add a flow here when its feature lands.
final Map<String, Future<void> Function(WidgetTester tester)> _wiredFlows = {};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Team E M3 end-to-end workflows (WBS 3.6.1)', () {
    for (final flow in teamEFlows) {
      final skipReason =
          skipReasonFor(flow, enabled: _enabled, backendUrl: _backendUrl);
      testWidgets(
        '${flow.caseId}: ${flow.title}'
        '${skipReason == null ? '' : ' [$skipReason]'}',
        (tester) async {
          final run = _wiredFlows[flow.caseId];
          if (run == null) {
            fail('${flow.caseId} is marked landed but its steps are not wired:\n'
                '${flow.steps.map((s) => '  - $s').join('\n')}');
          }
          await run(tester);
        },
        skip: skipReason != null,
      );
    }
  });
}
