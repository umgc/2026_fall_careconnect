// Widget tests for feature_use telemetry on key screens.
//
// Follows telemetry_test.dart capture patterns:
//   - SharedPreferences opt-out mock
//   - http.runWithClient + MockClient for telemetry POST bodies

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/evv/presentation/pages/start_visit_page.dart';
import 'package:care_connect_app/features/health/medication-tracker/pages/medication-tracker.dart';
import 'package:care_connect_app/features/social/presentation/pages/chat_room_screen.dart';
import 'package:care_connect_app/features/telemetry/telemetry.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/widgets/hybrid_video_call_widget.dart';

import '../../mock_user_provider.dart';

const _joinCredentials = <String, dynamic>{
  'meetingId': 'meeting-1',
  'attendeeId': 'attendee-1',
  'joinToken': 'join-token',
  'mediaPlacement': <String, dynamic>{},
};

Future<List<Map<String, dynamic>>> _runWidgetAndCaptureEvents(
  WidgetTester tester,
  Widget widget, {
  Future<void> Function()? interact,
  Size viewportSize = const Size(1080, 2400),
}) async {
  final bodies = <String>[];
  final mock = MockClient((req) async {
    if (req.method == 'POST' &&
        req.url.path.contains('telemetry') &&
        !req.url.path.contains('enabled')) {
      bodies.add(req.body);
    }
    if (req.method == 'GET' &&
        req.url.path.contains('/caregivers/') &&
        req.url.path.endsWith('/patients')) {
      return http.Response(
        jsonEncode([
          {
            'id': 1,
            'firstName': 'Jane',
            'lastName': 'Doe',
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.method == 'POST' && req.url.path.contains('/join')) {
      return http.Response(
        jsonEncode(_joinCredentials),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(jsonEncode({'enabled': true}), 200);
  });

  tester.view.physicalSize = viewportSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  ApiService.debugSetHttpClient(mock);
  try {
    await http.runWithClient(
      () async {
        await Telemetry.setBackendEnabled(true);
        await tester.pumpWidget(widget);
        await tester.pump();
        if (interact != null) {
          await interact();
        }
        await tester.pump(const Duration(milliseconds: 100));
      },
      () => mock,
    );
  } finally {
    ApiService.debugResetHttpClient();
  }

  return bodies
      .map((body) => jsonDecode(body) as Map<String, dynamic>)
      .toList();
}

bool _hasFeatureUse(
  List<Map<String, dynamic>> events,
  String feature,
) {
  return events.any(
    (event) =>
        event['eventName'] == 'feature_use' &&
        (event['details'] as Map<String, dynamic>)['feature'] == feature,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'telemetry_opted_out': false,
    });

    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final key = args['key'] as String?;

      if (call.method == 'read' && key == 'jwt_token') {
        return 'test-jwt-token';
      }
      return null;
    });
  });

  tearDown(() {
    const secureStorageChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  group('feature_use telemetry', () {
    testWidgets('MedicationsTrackerPage emits medications_tracker on init',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT', patientId: null),
      );

      final events = await _runWidgetAndCaptureEvents(
        tester,
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: provider,
            child: const MedicationsTrackerPage(),
          ),
        ),
      );

      expect(_hasFeatureUse(events, 'medications_tracker'), isTrue);
    });

    testWidgets('ChatRoomScreen emits chat_room after initialization',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT'),
      );

      final events = await _runWidgetAndCaptureEvents(
        tester,
        MaterialApp(
          home: ChangeNotifierProvider<UserProvider>.value(
            value: provider,
            child: const ChatRoomScreen(
              peerUserId: 2,
              peerName: 'Alice',
              enableAutoSync: false,
            ),
          ),
        ),
      );

      expect(_hasFeatureUse(events, 'chat_room'), isTrue);
    });

    testWidgets('StartVisitPage emits evv_start_visit on continue',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1),
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => ChangeNotifierProvider<UserProvider>.value(
              value: provider,
              child: const StartVisitPage(patientId: 1),
            ),
          ),
          GoRoute(
            path: '/evv/checkin-location',
            builder: (context, state) =>
                const Scaffold(body: Text('checkin-location')),
          ),
        ],
      );

      final events = await _runWidgetAndCaptureEvents(
        tester,
        MaterialApp.router(routerConfig: router),
        interact: () async {
          await tester.pumpAndSettle();
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Personal Care').last);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Continue to Check-In'));
          await tester.pump();
        },
      );

      expect(_hasFeatureUse(events, 'evv_start_visit'), isTrue);
    });

    testWidgets('HybridVideoCallWidget emits video_call after successful join',
        (tester) async {
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'PATIENT'),
      );

      final events = await _runWidgetAndCaptureEvents(
        tester,
        ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: MaterialApp(
            home: HybridVideoCallWidget(
              userId: '1',
              callId: 'test-call-123',
              recipientId: '2',
              recipientRole: 'CAREGIVER',
              userRole: 'PATIENT',
              isInitiator: false,
            ),
          ),
        ),
        interact: () async {
          await tester.pumpAndSettle(const Duration(seconds: 5));
        },
      );

      expect(_hasFeatureUse(events, 'video_call'), isTrue);
    });
  });
}
