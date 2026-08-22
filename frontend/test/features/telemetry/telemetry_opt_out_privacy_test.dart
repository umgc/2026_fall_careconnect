// Regression coverage for the privacy boundary between a user's local opt-out
// and the administrator-controlled backend telemetry toggle.

import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local opt-out performs no telemetry HTTP requests', () async {
    SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
    final requests = <http.Request>[];

    await http.runWithClient(
      () => Telemetry.event('screen_view', {'screen': 'home'}),
      () => MockClient((request) async {
        requests.add(request);
        return http.Response('{"enabled":true}', 200);
      }),
    );

    expect(
      requests,
      isEmpty,
      reason: 'A local opt-out must not POST telemetry or PUT the global toggle.',
    );
  });
}
