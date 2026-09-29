// WBS 3.6.1 (Team E, Milestone 3): end-to-end workflow suite.
//
// One test per STP-M3-E end-to-end requirement (16, 21, 22, 27); the flows and
// their dependencies are listed in team_e_m3/flows.dart.
//
// The suite is opt-in so it never runs in another team's emulator job by
// accident. Run it with:
//   flutter test integration_test/team_e_m3_workflows_e2e_test.dart \
//     --dart-define=TEAM_E_M3_E2E=true \
//     --dart-define=TEAM_E_BACKEND_URL=http://10.0.2.2:8080
//
// A flow whose features have not merged yet is skipped with the reason. A flow
// marked `landed` but not wired yet fails, so it cannot pass by accident.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'team_e_m3/flows.dart';

const _enabled = bool.fromEnvironment('TEAM_E_M3_E2E');
const _backendUrl = String.fromEnvironment('TEAM_E_BACKEND_URL');

/// Step implementations, keyed by STP ID. Add a flow here when its feature lands.
final Map<String, Future<void> Function(WidgetTester tester)> _wiredFlows = {};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Team E M3 end-to-end workflows (WBS 3.6.1)', () {
    for (final flow in teamEFlows) {
      final skipReason = _skipReason(flow);
      testWidgets(
        '${flow.stpId}: ${flow.title}'
        '${skipReason == null ? '' : ' [$skipReason]'}',
        (tester) async {
          final run = _wiredFlows[flow.stpId];
          if (run == null) {
            fail('${flow.stpId} is marked landed but its steps are not wired:\n'
                '${flow.steps.map((s) => '  - $s').join('\n')}');
          }
          await run(tester);
        },
        skip: skipReason != null,
      );
    }
  });
}

String? _skipReason(TeamEFlow flow) {
  if (!_enabled) return 'Opt-in: pass --dart-define=TEAM_E_M3_E2E=true';
  if (_backendUrl.isEmpty) return 'Set --dart-define=TEAM_E_BACKEND_URL';
  if (!flow.landed) return flow.blockedReason;
  return null;
}
