// Additional coverage for CommunicationService: Android phone-permission
// flow, error handlers, and the full startVideoCall flow. url_launcher and
// permission_handler are driven through mocked platform channels.

import 'package:care_connect_app/services/communication_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _urlChannels = [
  'plugins.flutter.io/url_launcher',
  'plugins.flutter.io/url_launcher_android',
  'plugins.flutter.io/url_launcher_ios',
  'plugins.flutter.io/url_launcher_linux',
  'plugins.flutter.io/url_launcher_macos',
  'plugins.flutter.io/url_launcher_windows',
];

const _permissionChannel =
    MethodChannel('flutter.baseflow.com/permissions/methods');

// permission_handler PermissionStatus indexes.
const _denied = 0;
const _granted = 1;

/// Mutable mock state shared by the handlers.
bool _canLaunch = true;
bool _throwOnCanLaunch = false;
int _statusResult = _granted;
int _requestResult = _granted;
final List<String> _launched = [];
final List<String> _permissionCalls = [];

void _install() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _urlChannels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
      if (call.method == 'canLaunch') {
        if (_throwOnCanLaunch) {
          throw PlatformException(code: 'boom', message: 'no launcher');
        }
        return _canLaunch;
      }
      if (call.method == 'launch' || call.method == 'launchUrl') {
        final args = call.arguments;
        if (args is Map) _launched.add(args['url'].toString());
        return true;
      }
      return null;
    });
  }
  messenger.setMockMethodCallHandler(_permissionChannel, (call) async {
    _permissionCalls.add(call.method);
    if (call.method == 'checkPermissionStatus') return _statusResult;
    if (call.method == 'requestPermissions') {
      final perms = (call.arguments as List).cast<int>();
      return {for (final p in perms) p: _requestResult};
    }
    return null;
  });
}

void _uninstall() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in _urlChannels) {
    messenger.setMockMethodCallHandler(MethodChannel(name), null);
  }
  messenger.setMockMethodCallHandler(_permissionChannel, null);
}

/// Pumps a scaffold and returns a context under it.
Future<BuildContext> _pumpHost(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ),
    ),
  );
  return ctx;
}

void main() {
  setUp(() {
    _canLaunch = true;
    _throwOnCanLaunch = false;
    _statusResult = _granted;
    _requestResult = _granted;
    _launched.clear();
    _permissionCalls.clear();
    _install();
  });

  tearDown(_uninstall);

  group('makePhoneCall on Android', () {
    testWidgets('granted permission launches tel: uri', (tester) async {
      final ctx = await _pumpHost(tester, platform: TargetPlatform.android);
      await CommunicationService.makePhoneCall('(555) 123-4567', ctx);
      await tester.pump();
      expect(_permissionCalls, contains('checkPermissionStatus'));
      expect(_permissionCalls, isNot(contains('requestPermissions')));
      expect(_launched.single, 'tel:5551234567');
    });

    testWidgets('requests permission when not granted and proceeds',
        (tester) async {
      _statusResult = _denied;
      final ctx = await _pumpHost(tester, platform: TargetPlatform.android);
      await CommunicationService.makePhoneCall('555', ctx);
      await tester.pump();
      expect(_permissionCalls, contains('requestPermissions'));
      expect(_launched.single, 'tel:555');
    });

    testWidgets('shows error when permission is denied', (tester) async {
      _statusResult = _denied;
      _requestResult = _denied;
      final ctx = await _pumpHost(tester, platform: TargetPlatform.android);
      await CommunicationService.makePhoneCall('555', ctx);
      await tester.pump();
      expect(find.text('Call permission denied'), findsOneWidget);
      expect(_launched, isEmpty);
    });
  });

  group('error handlers', () {
    testWidgets('makePhoneCall shows failure when launcher throws',
        (tester) async {
      _throwOnCanLaunch = true;
      final ctx = await _pumpHost(tester);
      await CommunicationService.makePhoneCall('555', ctx);
      await tester.pump();
      expect(find.textContaining('Failed to make call'), findsOneWidget);
    });

    testWidgets('sendSMS shows failure when launcher throws', (tester) async {
      _throwOnCanLaunch = true;
      final ctx = await _pumpHost(tester);
      await CommunicationService.sendSMS('555', ctx, message: 'hi');
      await tester.pump();
      expect(find.textContaining('Failed to send SMS'), findsOneWidget);
    });
  });

  group('startVideoCall', () {
    testWidgets('launches a jitsi meeting when permissions are granted',
        (tester) async {
      final ctx = await _pumpHost(tester);
      await CommunicationService.startVideoCall('p1', 'Pat', ctx);
      await tester.pump();
      expect(find.text('Starting video call with Pat'), findsOneWidget);
      expect(_launched.single, startsWith('https://meet.jit.si/careconnect-p1-'));
    });

    testWidgets('requests camera and mic when not granted', (tester) async {
      _statusResult = _denied;
      final ctx = await _pumpHost(tester);
      await CommunicationService.startVideoCall('p1', 'Pat', ctx);
      await tester.pump();
      expect(
        _permissionCalls.where((m) => m == 'requestPermissions').length,
        2,
      );
      expect(_launched, hasLength(1));
    });

    testWidgets('shows permission error when request is denied',
        (tester) async {
      _statusResult = _denied;
      _requestResult = _denied;
      final ctx = await _pumpHost(tester);
      await CommunicationService.startVideoCall('p1', 'Pat', ctx);
      await tester.pump();
      expect(
        find.text(
            'Camera and microphone permissions are required for video calls'),
        findsOneWidget,
      );
      expect(_launched, isEmpty);
    });

    testWidgets('shows error when the url cannot be launched',
        (tester) async {
      _canLaunch = false;
      final ctx = await _pumpHost(tester);
      await CommunicationService.startVideoCall('p1', 'Pat', ctx);
      await tester.pump();
      expect(find.text('Cannot launch video call'), findsOneWidget);
    });

    testWidgets('shows failure when the launcher throws', (tester) async {
      _throwOnCanLaunch = true;
      final ctx = await _pumpHost(tester);
      await CommunicationService.startVideoCall('p1', 'Pat', ctx);
      await tester.pump();
      expect(find.textContaining('Failed to start video call'),
          findsOneWidget);
    });
  });
}
