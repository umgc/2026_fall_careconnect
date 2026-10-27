// Page-title test for HybridVideoCallWidget
// (lib/widgets/hybrid_video_call_widget.dart): ending a call that was opened
// as the root page, with forcePatientDetailsOnExit set, replaces it with a
// page titled "Patient Details" (WCAG 2.4.2).
import 'dart:convert';

import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';
import 'package:care_connect_app/widgets/page_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/titled_route_probe.dart';
import '../mock_user_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      // A signed-in caregiver: only the JWT is stored.
      (call) async =>
          call.method == 'read' && (call.arguments as Map)['key'] == 'jwt_token'
              ? 'test-jwt'
              : null,
    );
  });

  testWidgets('ending the call opens a page titled "Patient Details"',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final probe = TitledRouteProbe();
    // Every call endpoint answers with a local mock meeting, so the active
    // call controls (with End call) render without Chime.
    final client = MockClient((_) async => http.Response(
        jsonEncode({
          'callId': 'call-exit',
          'meetingId': 'meeting-1',
          'attendeeId': 'attendee-1',
          'joinToken': 'local-join-token-1',
          'mediaPlacement': <String, dynamic>{},
        }),
        200));
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(mockUser: MockUser(role: 'CAREGIVER')),
        child: MaterialApp(
          navigatorObservers: [probe],
          home: const HybridVideoCallWidget(
            userId: '10',
            callId: 'call-exit',
            recipientId: '20',
            recipientRole: 'PATIENT',
            userRole: 'CAREGIVER',
            callKind: 'GENERAL',
            returnPatientDetailsId: '20',
            forcePatientDetailsOnExit: true,
            returnAsCaregiver: true,
          ),
        ),
      ));
      for (var i = 0; i < 40; i++) {
        await tester.idle();
        await tester.pump(const Duration(milliseconds: 100));
      }
      for (final e in find
          .byWidgetPredicate((w) => w is Text || w is Tooltip)
          .evaluate()) {
        final w = e.widget;
        debugPrint(
            'W: ${w.runtimeType} ${w is Text ? w.data : w is Tooltip ? w.message : ''}');
      }
      final before = probe.pushed.length;
      await tester.tap(find.byTooltip('End call'));
      for (var i = 0; i < 10 && probe.pushed.length == before; i++) {
        await tester.idle();
      }
      // The call page was the only route, so swap in a blank page rather
      // than removing the replacement (and never build Patient Details).
      final route = probe.pushed.last;
      expect(route, isA<TitledMaterialPageRoute>());
      final content = (route as TitledMaterialPageRoute)
          .buildContent(probe.navigator!.context);
      expect((content as PageTitle).title, 'Patient Details');
      probe.navigator!.replace(
          oldRoute: route,
          newRoute: MaterialPageRoute<void>(builder: (_) => const SizedBox()));
      await tester.pump();
    }, () => client);
  });
}
