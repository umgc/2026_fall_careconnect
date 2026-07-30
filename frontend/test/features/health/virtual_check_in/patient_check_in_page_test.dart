// Tests for PatientVirtualCheckIn
// (lib/features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart).
//
// Camera availability is checked lazily when the FAB is pressed (cameraHandler),
// not in initState. Questionnaire loading uses UserProvider; a logged-out
// provider avoids real HTTP.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:care_connect_app/features/health/virtual_check_in/presentation/pages/patient_check_in_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../../mock_user_provider.dart';

/// Provider that reports no session so questionnaire load exits without HTTP.
class _LoggedOutUserProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}

Widget _wrap() {
  return ChangeNotifierProvider<UserProvider>.value(
    value: _LoggedOutUserProvider(),
    child: const MaterialApp(home: PatientVirtualCheckIn()),
  );
}

Future<void> _pumpSettled(WidgetTester tester) async {
  await tester.pumpWidget(_wrap());
  // Bounded pumps — avoid hanging on asset/network animations.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _triggerCameraCheck(WidgetTester tester) async {
  await tester.tap(find.byType(FloatingActionButton));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      (call) async {
        if (call.method == 'availableCameras') return <dynamic>[];
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/camera'),
      null,
    );
  });

  group('PatientVirtualCheckIn – camera throws', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/camera'),
        (call) async {
          if (call.method == 'availableCameras') {
            throw PlatformException(
              code: 'CAMERA_ERROR',
              message: 'No cameras available',
            );
          }
          return null;
        },
      );
    });

    testWidgets('renders Scaffold when availableCameras throws', (
      tester,
    ) async {
      await _pumpSettled(tester);
      expect(find.byType(Scaffold), findsOneWidget);

      await _triggerCameraCheck(tester);

      expect(find.textContaining('Camera not available'), findsWidgets);
    });
  });

  group('PatientVirtualCheckIn', () {
    testWidgets('renders Scaffold on first pump', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('shows "Daily Check-In" heading after camera check', (
      tester,
    ) async {
      await _pumpSettled(tester);
      expect(find.textContaining('Daily Check-In'), findsOneWidget);
    });

    testWidgets('shows camera-unavailable notice when no camera found', (
      tester,
    ) async {
      await _pumpSettled(tester);
      await _triggerCameraCheck(tester);

      expect(
        find.textContaining('Camera not available'),
        findsWidgets,
      );
    });

    testWidgets('FAB uses videocam_off icon when no camera', (tester) async {
      await _pumpSettled(tester);
      // Before check: video_call icon (optimistic default).
      expect(find.byIcon(Icons.video_call), findsOneWidget);

      await _triggerCameraCheck(tester);

      expect(find.byIcon(Icons.videocam_off), findsOneWidget);
    });

    testWidgets('mood selection emoji options are rendered', (tester) async {
      await _pumpSettled(tester);

      for (final emoji in ['😢', '😞', '😐', '🙂', '😊']) {
        expect(
          find.text(emoji),
          findsOneWidget,
          reason: 'Expected mood emoji $emoji to be present',
        );
      }
    });

    testWidgets('shows "How are you feeling today?" question', (tester) async {
      await _pumpSettled(tester);
      expect(find.text('How are you feeling today?'), findsOneWidget);
    });

    testWidgets('shows "Any symptoms or notes?" heading', (tester) async {
      await _pumpSettled(tester);
      expect(find.text('Any symptoms or notes?'), findsOneWidget);
    });

    testWidgets('shows submit button and mood-required hint initially', (
      tester,
    ) async {
      await _pumpSettled(tester);

      expect(find.text('Submit Check-In'), findsOneWidget);
      expect(
        find.text('Please select your mood to submit your check-in'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a mood emoji selects it and hides hint', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSettled(tester);

      final mood = find.text('Great');
      await tester.ensureVisible(mood);
      await tester.tap(mood);
      await tester.pump();

      expect(
        find.text('Please select your mood to submit your check-in'),
        findsNothing,
      );
    });

    testWidgets('tapping Submit after mood selection shows snack bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await _pumpSettled(tester);

      final mood = find.text('Neutral');
      await tester.ensureVisible(mood);
      await tester.tap(mood);
      await tester.pump();

      await tester.ensureVisible(find.text('Submit Check-In'));
      await tester.tap(find.text('Submit Check-In'));
      await tester.pump();

      expect(find.text('Check-in submitted (mock)!'), findsOneWidget);
    });
  });
}
