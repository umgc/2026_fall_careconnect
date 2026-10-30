// Gap-filling widget tests for NotetakerConfigurationPage
// (lib/pages/notetaker_configuration_page.dart).
//
// The sibling suites cover rendering, toggles, PII/keyword dialogs and the
// save flow. This file covers the voice-sample recorder (record permission,
// encoder support, start/stop state changes, enabling and using Save File)
// and Cancel navigation.
//
// The microphone is replaced by an in-memory RecordPlatform fake and the
// config endpoint by a MockClient, so no audio hardware and no network are
// used. getExternalStorageDirectory is Android-only and throws
// UnsupportedError on the VM test host; those un-awaited errors are collected
// by a guarded zone exactly as notetaker_configuration_page_flows_test does.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/pages/notetaker_configuration_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

/// In-memory microphone. Every call is recorded so tests can assert on it.
class _FakeRecordPlatform extends RecordPlatform
    with MockPlatformInterfaceMixin {
  bool permission = true;
  bool encoderSupported = true;
  int startStreamCalls = 0;
  int stopCalls = 0;
  final StreamController<RecordState> states =
      StreamController<RecordState>.broadcast();
  StreamController<Uint8List>? data;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permission;

  @override
  Future<bool> isEncoderSupported(
          String recorderId, AudioEncoder encoder) async =>
      encoderSupported;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const <InputDevice>[];

  @override
  Future<Stream<Uint8List>> startStream(
      String recorderId, RecordConfig config) async {
    startStreamCalls++;
    data = StreamController<Uint8List>();
    states.add(RecordState.record);
    return data!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls++;
    await data?.close();
    states.add(RecordState.stop);
    return null;
  }

  @override
  Stream<RecordState> onStateChanged(String recorderId) => states.stream;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Map<String, dynamic> _config(int patientId) => {
      'id': 9,
      'patientId': patientId,
      'isEnabled': true,
      'permitCaregiverAccess': false,
      'triggerKeywords': [
        {'keyword': 'PII_SSN', 'event_type': 'ALERT'},
      ],
    };

MockClient _client() =>
    MockClient((req) async => http.Response(jsonEncode(_config(1)), 200));

late _FakeRecordPlatform _mic;

Widget _app() {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.push('/config'),
              child: const Text('Open config'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/config',
        builder: (_, __) => const NotetakerConfigurationPage(),
      ),
    ],
  );
  return ChangeNotifierProvider<UserProvider>.value(
    value: MockUserProvider(
      mockUser: MockUser(role: 'PATIENT', patientId: 1),
    ),
    child: MaterialApp.router(routerConfig: router),
  );
}

/// The page wraps its SimpleDialogs in Expanded; drop only that report.
void _ignoreParentData() {
  final original = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('ParentDataWidget')) return;
    original?.call(d);
  };
  addTearDown(() => FlutterError.onError = original);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Collects only the Android-only storage UnsupportedErrors.
Future<void> _guarded(Future<void> Function() action, List<Object> sink) async {
  await runZonedGuarded(action, (error, stack) {
    if (error is UnsupportedError) {
      sink.add(error);
      return;
    }
    Zone.root.handleUncaughtError(error, stack);
  });
}

/// Opens the config page from the home route and waits for it to load.
Future<void> _openPage(WidgetTester tester, List<Object> storageErrors) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  _ignoreParentData();
  await http.runWithClient(() async {
    await tester.pumpWidget(_app());
    await _guarded(() async {
      await tester.tap(find.text('Open config'));
      await _settle(tester);
    }, storageErrors);
  }, _client);
}

/// Taps the microphone control and lets the async recorder calls finish.
Future<void> _tapMic(WidgetTester tester) async {
  await tester.ensureVisible(find.byIcon(Icons.mic).last);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.mic).last);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await _settle(tester);
}

/// Unmounts the page and lets AudioRecorder.dispose finish. record serialises
/// platform calls through a process-wide semaphore, so a dispose left pending
/// at the end of one test would block the recorder in every later test.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 3; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
}

/// Registers a widget test whose page is always unmounted cleanly afterwards.
void _test(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await _close(tester);
    }
  });
}

ElevatedButton _saveFileButton(WidgetTester tester) => tester
    .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Save File'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mic = _FakeRecordPlatform();
    RecordPlatform.instance = _mic;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    m.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDown(() async {
    await _mic.states.close();
  });

  _test('Cancel leaves the page and returns to the previous route',
      (tester) async {
    final errors = <Object>[];
    await _openPage(tester, errors);
    expect(find.text('Notetaker Configuration'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await _settle(tester);

    expect(find.text('Notetaker Configuration'), findsNothing);
    expect(find.text('Open config'), findsOneWidget);
  });

  _test('recording starts, shows Stop, and stops again', (tester) async {
    final errors = <Object>[];
    await _openPage(tester, errors);
    expect(find.text('Start'), findsOneWidget);
    expect(_saveFileButton(tester).onPressed, isNull);

    await _tapMic(tester);

    expect(_mic.startStreamCalls, 1);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);

    // Stopping returns the control to its idle state.
    await tester.tap(find.byIcon(Icons.stop));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(_mic.stopCalls, 1);
    expect(find.text('Start'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsWidgets);
  });

  _test('captured audio enables Save File', (tester) async {
    final errors = <Object>[];
    await _openPage(tester, errors);

    await _tapMic(tester);
    _mic.data!.add(Uint8List.fromList(List<int>.filled(64, 3)));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    expect(_saveFileButton(tester).onPressed, isNotNull);
  });

  _test('no microphone permission means nothing is recorded', (tester) async {
    _mic.permission = false;
    final errors = <Object>[];
    await _openPage(tester, errors);

    await _tapMic(tester);

    expect(_mic.startStreamCalls, 0);
    expect(find.text('Start'), findsOneWidget);
    expect(_saveFileButton(tester).onPressed, isNull);
  });

  _test('an unsupported encoder means nothing is recorded', (tester) async {
    _mic.encoderSupported = false;
    final errors = <Object>[];
    await _openPage(tester, errors);

    await _tapMic(tester);

    expect(_mic.startStreamCalls, 0);
    expect(find.text('Start'), findsOneWidget);
    expect(_saveFileButton(tester).onPressed, isNull);
  });

  _test('Save File asks for a name and closes once one is entered',
      (tester) async {
    final errors = <Object>[];
    await _openPage(tester, errors);

    await _tapMic(tester);
    _mic.data!.add(Uint8List.fromList(List<int>.filled(64, 3)));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.tap(find.byIcon(Icons.stop));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);

    await tester.ensureVisible(find.text('Save File'));
    await tester.pump();
    await tester.tap(find.text('Save File'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);

    // An empty name keeps the dialog open.
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);

    await _guarded(() async {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Enter text'), 'Maria');
      await tester.tap(find.text('Add'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _settle(tester);
    }, errors);

    expect(find.text('Enter your name'), findsNothing);
  });
}
