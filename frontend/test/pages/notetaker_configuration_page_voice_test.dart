// Coverage for the voice-sample parts of NotetakerConfigurationPage
// (lib/pages/notetaker_configuration_page.dart): recorder start/stop via a
// fake RecordPlatform, saving a WAV sample, listing/deleting stored samples
// through a fake PathProviderPlatform backed by a temp directory, the dialog
// validators and the Cancel action.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/pages/notetaker_configuration_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _FakePathProvider(this.path);
  final String? path;

  @override
  Future<String?> getExternalStoragePath() async => path;
}

class _FakeRecord extends Fake
    with MockPlatformInterfaceMixin
    implements RecordPlatform {
  bool permission = true;
  bool pcmSupported = true;
  final List<String> calls = [];
  final _state = StreamController<RecordState>.broadcast();
  StreamController<Uint8List>? audio;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) => _state.stream;

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async {
    calls.add('hasPermission');
    return permission;
  }

  @override
  Future<bool> isEncoderSupported(
      String recorderId, AudioEncoder encoder) async {
    calls.add('isEncoderSupported:${encoder.name}');
    if (encoder == AudioEncoder.pcm16bits) return pcmSupported;
    return encoder == AudioEncoder.wav;
  }

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [InputDevice(id: 'mic', label: 'Mic')];

  @override
  Future<Stream<Uint8List>> startStream(
      String recorderId, RecordConfig config) async {
    calls.add('startStream');
    audio = StreamController<Uint8List>();
    _state.add(RecordState.record);
    return audio!.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    calls.add('stop');
    _state.add(RecordState.stop);
    await audio?.close();
    return null;
  }

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<void> dispose(String recorderId) async {}
}

Map<String, dynamic> _config() => {
      'id': 9,
      'patientId': 1,
      'isEnabled': true,
      'permitCaregiverAccess': false,
      'triggerKeywords': [
        {'keyword': 'PII_SSN', 'event_type': 'ALERT'},
      ],
    };

MockClient _configClient() =>
    MockClient((_) async => http.Response(jsonEncode(_config()), 200));

Widget _app(UserProvider provider) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () => context.push('/config'),
            child: const Text('Open Config'),
          ),
        ),
      ),
      GoRoute(
        path: '/config',
        builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
          value: provider,
          child: const NotetakerConfigurationPage(),
        ),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

MockUserProvider _patient() =>
    MockUserProvider(mockUser: MockUser(role: 'PATIENT', patientId: 1));

/// Pumps frames while giving real file-system I/O a chance to complete,
/// until [done] is true (bounded so a failure cannot hang the test).
Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Unmounts the page and flushes its async recorder dispose, which holds the
/// record package's global semaphore until it completes.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _openConfig(WidgetTester tester, UserProvider provider) async {
  await tester.pumpWidget(_app(provider));
  await tester.tap(find.text('Open Config'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmp;
  late PathProviderPlatform originalPath;
  late RecordPlatform originalRecord;
  late _FakeRecord record;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('notetaker_cfg_');
    originalPath = PathProviderPlatform.instance;
    originalRecord = RecordPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
    record = _FakeRecord();
    RecordPlatform.instance = record;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPath;
    RecordPlatform.instance = originalRecord;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      null,
    );
  });

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // The page wraps its SimpleDialogs in Expanded; drop only that report.
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('ParentDataWidget')) return;
      original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  testWidgets('lists stored samples, deletes one and prunes empty folders',
      (tester) async {
    bigScreen(tester);
    final alice = Directory('${tmp.path}/voice_samples/Alice')
      ..createSync(recursive: true);
    File('${alice.path}/a1.wav').writeAsBytesSync([1, 2, 3]);
    final empty = Directory('${tmp.path}/voice_samples/Empty')
      ..createSync(recursive: true);

    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => find.text('Alice').evaluate().isNotEmpty);

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Empty'), findsNothing);
      expect(empty.existsSync(), isFalse);

      // Expand the accordion and delete the only sample.
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();
      expect(find.text('a1.wav'), findsOneWidget);
      await tester.tap(find.byTooltip('delete voice sample'));
      await _pumpUntil(tester, () => !alice.existsSync());

      expect(File('${alice.path}/a1.wav').existsSync(), isFalse);
      expect(alice.existsSync(), isFalse);
      expect(find.text('Alice'), findsNothing);
    }, _configClient);
    await _unmount(tester);
  });

  testWidgets('missing voice sample folder leaves the list empty',
      (tester) async {
    bigScreen(tester);
    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => false);
    }, _configClient);

    expect(find.text('Manage Voice Sample'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    expect(find.byTooltip('delete voice sample'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('records audio, stops, and saves a WAV sample', (tester) async {
    bigScreen(tester);
    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => false);

      final saveButton = find.widgetWithText(ElevatedButton, 'Save File');
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNull);
      expect(find.text('Start'), findsOneWidget);

      // Start recording.
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      expect(record.calls, contains('startStream'));
      record.audio!.add(Uint8List.fromList([10, 20, 30, 40]));
      await tester.pump();
      expect(find.text('Stop'), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsOneWidget);

      // Stop recording.
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      await tester.pump();
      expect(record.calls, contains('stop'));
      expect(find.text('Start'), findsOneWidget);
      expect(tester.widget<ElevatedButton>(saveButton).onPressed, isNotNull);

      // Open the save dialog; empty name does nothing.
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(find.text('Enter your name'), findsOneWidget);
      final nameField =
          tester.widget<TextFormField>(find.byType(TextFormField).last);
      expect(nameField.validator!(''), 'This field is required');
      expect(nameField.validator!('Bob'), isNull);
      await tester.tap(find.text('Add').last);
      await tester.pump();
      expect(find.text('Enter your name'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).last, 'Bob');
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(find.text('Enter your name'), findsNothing);

      final bobDir = Directory('${tmp.path}/voice_samples/Bob');
      await _pumpUntil(
          tester, () => find.text('Bob').evaluate().isNotEmpty);
      final wavs = bobDir.listSync().whereType<File>().toList();
      expect(wavs, hasLength(1));
      final bytes = wavs.single.readAsBytesSync();
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(bytes.sublist(8, 12)), 'WAVE');
      expect(bytes.length, 44 + 4);
      expect(bytes.sublist(44), [10, 20, 30, 40]);
      expect(find.text('Bob'), findsOneWidget);
    }, _configClient);
    await _unmount(tester);
  });

  testWidgets('unsupported encoder stops before streaming', (tester) async {
    bigScreen(tester);
    record.pcmSupported = false;
    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => false);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
    }, _configClient);

    expect(record.calls, contains('isEncoderSupported:pcm16bits'));
    expect(record.calls, contains('isEncoderSupported:wav'));
    expect(record.calls, isNot(contains('startStream')));
    expect(find.text('Start'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('saving without external storage writes nothing',
      (tester) async {
    bigScreen(tester);
    PathProviderPlatform.instance = _FakePathProvider(null);
    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => false);

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      await tester.pump();
      record.audio!.add(Uint8List.fromList([1, 2]));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save File'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Carol');
      await tester.tap(find.text('Add').last);
      await _pumpUntil(tester, () => false);
    }, _configClient);

    expect(find.text('Enter your name'), findsNothing);
    expect(Directory('${tmp.path}/voice_samples').existsSync(), isFalse);
    expect(find.text('Carol'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('no microphone permission does nothing', (tester) async {
    bigScreen(tester);
    record.permission = false;
    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => false);
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
    }, _configClient);

    expect(record.calls, ['hasPermission']);
    await _unmount(tester);
  });

  testWidgets('PII and keyword dialog validators', (tester) async {
    bigScreen(tester);
    await http.runWithClient(() async {
      await _openConfig(tester, _patient());
      await _pumpUntil(tester, () => false);

      await tester.tap(find.text('Add PII'));
      await tester.pumpAndSettle();
      final pii = tester.widget<TextFormField>(find.byType(TextFormField).last);
      expect(pii.validator!(null), 'This field is required');
      expect(pii.validator!('x'), isNull);
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Keyword'));
      await tester.pumpAndSettle();
      final kw = tester.widget<TextFormField>(find.byType(TextFormField).last);
      expect(kw.validator!(''), 'This field is required');
      expect(kw.validator!('fall'), isNull);
      final dd = tester.widget<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>).last);
      expect(dd.validator!(null), 'Please select an option');
      expect(dd.validator!('TASK'), isNull);
    }, _configClient);
    await _unmount(tester);
  });

  testWidgets('caregiver patient validator and Cancel pops the page',
      (tester) async {
    bigScreen(tester);
    ApiService.debugSetHttpClient(MockClient((_) async => http.Response(
        jsonEncode([
          {
            'patient': {'id': 31, 'firstName': 'Ana', 'lastName': 'Diaz'},
          },
        ]),
        200)));
    addTearDown(ApiService.debugResetHttpClient);

    await _openConfig(
      tester,
      MockUserProvider(
        mockUser: MockUser(role: 'CAREGIVER', patientId: null, caregiverId: 4),
      ),
    );
    await _pumpUntil(tester, () => false);

    final dd = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    expect(dd.validator!(null), 'Please select an option');
    expect(dd.validator!('31'), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open Config'), findsOneWidget);
    expect(find.text('Notetaker Configuration'), findsNothing);
    await _unmount(tester);
  });
}
