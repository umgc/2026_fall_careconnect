// More happy-path tests for PatientVirtualCheckIn
// (lib/features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart):
// the assigned questionnaire load outcomes, and the camera record / pause /
// resume / submit / discard flow against a fake camera platform.
import 'dart:async';
import 'dart:convert';

// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../mock_user_provider.dart';

class _FakeCamera extends CameraPlatform with MockPlatformInterfaceMixin {
  final calls = <String>[];
  bool hasCamera = true;

  @override
  Future<List<CameraDescription>> availableCameras() async => hasCamera
      ? const [
          CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 0,
          ),
        ]
      : const [];

  @override
  Future<int> createCameraWithSettings(
      CameraDescription cameraDescription, MediaSettings mediaSettings) async {
    calls.add('create');
    return 1;
  }

  @override
  Future<void> initializeCamera(int cameraId,
      {ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown}) async {
    calls.add('initialize');
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(CameraInitializedEvent(cameraId, 640, 480,
          ExposureMode.auto, false, FocusMode.auto, false));

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) =>
      const Stream.empty();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    calls.add('start');
  }

  @override
  Future<void> pauseVideoRecording(int cameraId) async {
    calls.add('pause');
  }

  @override
  Future<void> resumeVideoRecording(int cameraId) async {
    calls.add('resume');
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    calls.add('stop');
    return XFile('clip.mp4');
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox(key: Key('preview'));

  @override
  Future<void> dispose(int cameraId) async {}
}

void main() {
  late _FakeCamera camera;
  late http.Response Function(http.Request) handler;
  late CameraPlatform original;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
    original = CameraPlatform.instance;
    camera = _FakeCamera();
    CameraPlatform.instance = camera;
    handler = (request) {
      final path = request.url.path;
      if (path.endsWith('/api/checkins/patients/5')) {
        return http.Response('[]', 200);
      }
      if (path.endsWith('/api/checkins/patients/9')) {
        return http.Response(
            jsonEncode([
              {'checkInId': 77, 'patientId': 9},
            ]),
            200);
      }
      if (path.endsWith('/api/checkins/77/questions')) {
        return http.Response(
            jsonEncode([
              {'id': 1, 'prompt': 'How did you sleep?', 'required': true},
              {'id': 2, 'prompt': 'Anything else?', 'type': 'TEXT'},
            ]),
            200);
      }
      return http.Response('[]', 200);
    };
  });

  tearDown(() => CameraPlatform.instance = original);

  Future<void> pumpPage(WidgetTester tester,
      {int id = 9, int? patientId = 5}) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
            mockUser: MockUser(id: id, role: 'PATIENT', patientId: patientId)),
        child: const MaterialApp(home: PatientVirtualCheckIn()),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, () => MockClient((r) async => handler(r)));
  }

  testWidgets('lists the assigned questions of the latest check-in',
      (tester) async {
    await pumpPage(tester);
    expect(find.text('Check-in #77'), findsOneWidget);
    expect(find.textContaining('How did you sleep? (Required'), findsOneWidget);
    expect(find.textContaining('Anything else? (Optional'), findsOneWidget);
  });

  testWidgets('a check-in without questions says so', (tester) async {
    final base = handler;
    handler = (r) => r.url.path.endsWith('/questions')
        ? http.Response('[]', 200)
        : base(r);
    await pumpPage(tester);
    expect(find.text('This check-in has no questions configured.'),
        findsOneWidget);
  });

  testWidgets('no assigned check-in says so', (tester) async {
    await pumpPage(tester, id: 3, patientId: null);
    expect(find.text('No check-in questionnaire has been assigned yet.'),
        findsOneWidget);
  });

  testWidgets('a failing questions call is reported', (tester) async {
    final base = handler;
    handler = (r) => r.url.path.endsWith('/questions')
        ? http.Response('boom', 500)
        : base(r);
    await pumpPage(tester);
    expect(find.textContaining('Failed to load questionnaire'), findsOneWidget);
  });

  testWidgets('choosing a mood enables the mock submit', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Good'));
    await tester.pump();
    await tester.tap(find.text('Submit Check-In'));
    await tester.pump();
    expect(find.text('Check-in submitted (mock)!'), findsOneWidget);
  });

  Future<void> openCamera(WidgetTester tester) async {
    await http.runWithClient(() async {
      await tester.tap(find.byType(FloatingActionButton));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, () => MockClient((r) async => handler(r)));
  }

  testWidgets('the camera records, pauses, resumes and submits',
      (tester) async {
    await pumpPage(tester);
    await openCamera(tester);
    expect(find.text('Discard'), findsOneWidget);

    // Submitting before recording is refused.
    await tester.tap(find.text('Submit'));
    await tester.pump();
    expect(find.text('Cannot submit, no video recorded.'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(camera.calls, containsAll(['start', 'pause', 'resume']));

    await http.runWithClient(() async {
      await tester.tap(find.text('Submit'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }, () => MockClient((r) async => http.Response('', 200)));
    // Snack bars queue: let the earlier "Cannot submit" one time out.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('Video submitted successfully! (placeholder)'),
        findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('the camera view can be discarded', (tester) async {
    await pumpPage(tester);
    await openCamera(tester);
    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(find.text('Video discarded'), findsOneWidget);
  });

  testWidgets('no camera shows the unavailable notice', (tester) async {
    camera.hasCamera = false;
    await pumpPage(tester);
    await openCamera(tester);
    expect(find.text('Camera not available on this device/session.'),
        findsOneWidget);
    expect(find.text('Camera not available - Video recording disabled'),
        findsOneWidget);
  });
}
