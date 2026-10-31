// Gap coverage for CommunicationService: Android call-permission flow, SMS
// body encoding, video-call permission and launch flows, and the error
// snackbars. The permission_handler and url_launcher platform channels are
// replaced with recording fakes, so nothing is launched on the host.
import 'package:care_connect_app/services/communication_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
const _launcherChannel = MethodChannel('plugins.flutter.io/url_launcher');

// permission_handler status codes: 0 denied, 1 granted.
const _denied = 0;
const _granted = 1;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int currentStatus;
  late int statusAfterRequest;
  late int requestCalls;
  late bool canLaunch;
  late bool launcherThrows;
  late List<MethodCall> launched;

  setUp(() {
    currentStatus = _granted;
    statusAfterRequest = _granted;
    requestCalls = 0;
    canLaunch = true;
    launcherThrows = false;
    launched = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_permChannel, (call) async {
      if (call.method == 'checkPermissionStatus') return currentStatus;
      if (call.method == 'requestPermissions') {
        requestCalls++;
        final ids = (call.arguments as List).cast<int>();
        return {for (final id in ids) id: statusAfterRequest};
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_launcherChannel, (call) async {
      if (launcherThrows) {
        throw PlatformException(code: 'BOOM', message: 'launcher exploded');
      }
      if (call.method == 'canLaunch') return canLaunch;
      if (call.method == 'launch') {
        launched.add(call);
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_permChannel, null);
    messenger.setMockMethodCallHandler(_launcherChannel, null);
  });

  Future<void> pumpAndTap(
    WidgetTester tester,
    Future<void> Function(BuildContext) action, {
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => action(context),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  group('makePhoneCall on Android', () {
    testWidgets('asks for permission and dials once it is granted',
        (tester) async {
      currentStatus = _denied;
      statusAfterRequest = _granted;

      await pumpAndTap(
        tester,
        (c) => CommunicationService.makePhoneCall('(555) 010-2030', c),
      );

      expect(requestCalls, 1);
      expect(launched.single.arguments['url'], 'tel:5550102030');
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('shows an error and does not dial when permission is denied',
        (tester) async {
      currentStatus = _denied;
      statusAfterRequest = _denied;

      await pumpAndTap(
        tester,
        (c) => CommunicationService.makePhoneCall('555', c),
      );

      expect(find.text('Call permission denied'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('dials without prompting when already permitted',
        (tester) async {
      await pumpAndTap(
        tester,
        (c) => CommunicationService.makePhoneCall('+1 555 0100', c),
      );

      expect(requestCalls, 0);
      expect(launched.single.arguments['url'], 'tel:+15550100');
    });
  });

  group('makePhoneCall launch problems', () {
    testWidgets('reports when no phone app can handle the number',
        (tester) async {
      canLaunch = false;
      await pumpAndTap(
        tester,
        (c) => CommunicationService.makePhoneCall('555', c),
        platform: TargetPlatform.iOS,
      );

      expect(find.text('Cannot launch phone app'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('reports a launcher exception', (tester) async {
      launcherThrows = true;
      await pumpAndTap(
        tester,
        (c) => CommunicationService.makePhoneCall('555', c),
        platform: TargetPlatform.iOS,
      );

      expect(find.textContaining('Failed to make call'), findsOneWidget);
    });
  });

  group('sendSMS', () {
    testWidgets('opens the SMS app with a URL-encoded body', (tester) async {
      await pumpAndTap(
        tester,
        (c) => CommunicationService.sendSMS(
          '(555) 123-4567',
          c,
          message: 'Hi there & welcome',
        ),
      );

      expect(
        launched.single.arguments['url'],
        'sms:5551234567?body=Hi%20there%20%26%20welcome',
      );
    });

    testWidgets('omits the body when the message is empty', (tester) async {
      await pumpAndTap(
        tester,
        (c) => CommunicationService.sendSMS('555', c, message: ''),
      );

      expect(launched.single.arguments['url'], 'sms:555');
    });

    testWidgets('reports when no SMS app is available', (tester) async {
      canLaunch = false;
      await pumpAndTap(tester, (c) => CommunicationService.sendSMS('555', c));

      expect(find.text('Cannot launch SMS app'), findsOneWidget);
    });

    testWidgets('reports a launcher exception', (tester) async {
      launcherThrows = true;
      await pumpAndTap(tester, (c) => CommunicationService.sendSMS('555', c));

      expect(find.textContaining('Failed to send SMS'), findsOneWidget);
    });
  });

  group('startVideoCall', () {
    testWidgets('requests missing permissions, announces and launches Jitsi',
        (tester) async {
      currentStatus = _denied;
      statusAfterRequest = _granted;

      await pumpAndTap(
        tester,
        (c) => CommunicationService.startVideoCall('p9', 'Pat', c),
      );

      expect(requestCalls, 2, reason: 'camera and microphone');
      expect(find.text('Starting video call with Pat'), findsOneWidget);
      final url = launched.single.arguments['url'] as String;
      expect(url, startsWith('https://meet.jit.si/careconnect-p9-'));
    });

    testWidgets('does not launch when permissions stay denied', (tester) async {
      currentStatus = _denied;
      statusAfterRequest = _denied;

      await pumpAndTap(
        tester,
        (c) => CommunicationService.startVideoCall('p9', 'Pat', c),
      );

      expect(
        find.text(
          'Camera and microphone permissions are required for video calls',
        ),
        findsOneWidget,
      );
      expect(launched, isEmpty);
    });

    testWidgets('reports when the call link cannot be opened', (tester) async {
      canLaunch = false;
      await pumpAndTap(
        tester,
        (c) => CommunicationService.startVideoCall('p9', 'Pat', c),
      );

      expect(find.text('Cannot launch video call'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('reports a launcher exception', (tester) async {
      launcherThrows = true;
      await pumpAndTap(
        tester,
        (c) => CommunicationService.startVideoCall('p9', 'Pat', c),
      );

      expect(find.textContaining('Failed to start video call'), findsOneWidget);
    });
  });
}
