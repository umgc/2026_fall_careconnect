// Extra AIChat coverage: legacy mode without a user id, path-based file
// uploads (UTF-8, Latin-1 fallback, truncation) and sending without a
// signed-in user, and the local edge (Colibri) answer path.
//
// ColibriService talks to its local gateway through Dio, which builds a
// dart:io HttpClient. An HttpOverrides installed for this file serves that
// client from memory (no network); when [_EdgeGateway.up] is false the gateway
// answers 404 and AIChat falls back to the cloud endpoint, which is mocked
// with package:http's MockClient as usual.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/tts_engine.dart';
import 'package:care_connect_app/widgets/ai_chat_improved.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

/// In-memory stand-in for the local Colibri gateway.
class _EdgeGateway {
  static bool up = false;
  static List<String> models = const ['olmoe-colibri'];
  static final List<String> paths = <String>[];

  static (int, Object) respond(Uri url) {
    paths.add(url.path);
    if (!up) return (404, {'error': 'offline'});
    if (url.path.endsWith('/models')) {
      return (
        200,
        {
          'data': [
            for (final id in models) {'id': id},
          ],
        },
      );
    }
    if (url.path.endsWith('/chat/completions')) {
      return (
        200,
        {
          'choices': [
            {
              'message': {'content': 'Edge says hello.'},
            },
          ],
          'usage': {'total_tokens': 12},
        },
      );
    }
    return (404, {});
  }
}

class _GatewayHeaders implements HttpHeaders {
  final Map<String, List<String>> values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = ['$value'];
  }

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      values.forEach(action);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.isSetter ? null : super.noSuchMethod(invocation);
}

class _GatewayResponse extends Stream<List<int>> implements HttpClientResponse {
  _GatewayResponse(this.statusCode, Object body)
      : _bytes = utf8.encode(jsonEncode(body)) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }

  final List<int> _bytes;

  @override
  final int statusCode;

  @override
  final _GatewayHeaders headers = _GatewayHeaders();

  @override
  bool get isRedirect => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  String get reasonPhrase => statusCode == 200 ? 'OK' : 'Not Found';

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([Uint8List.fromList(_bytes)]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _GatewayRequest implements HttpClientRequest {
  _GatewayRequest(this.uri);

  @override
  final Uri uri;

  @override
  final _GatewayHeaders headers = _GatewayHeaders();

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() async {
    final (status, body) = _EdgeGateway.respond(uri);
    return _GatewayResponse(status, body);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.isSetter ? null : super.noSuchMethod(invocation);
}

class _GatewayClient implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _GatewayRequest(url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.isSetter ? null : super.noSuchMethod(invocation);
}

class _GatewayOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _GatewayClient();
}

class _Tts implements TtsEngine {
  @override
  Future<dynamic> setLanguage(String language) async => 1;
  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;
  @override
  Future<dynamic> setVolume(double volume) async => 1;
  @override
  Future<dynamic> setPitch(double pitch) async => 1;
  @override
  Future<dynamic> awaitSpeakCompletion(bool awaitCompletion) async => null;
  @override
  Future<dynamic> speak(String text) async => 1;
  @override
  Future<dynamic> stop() async => 1;
}

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

class _SignedOutProvider extends MockUserProvider {
  @override
  UserSession? get user => null;
}

Widget _chat({
  required AiChatMode mode,
  int? patientId,
  int? userId,
  UserProvider? provider,
}) {
  return ChangeNotifierProvider<UserProvider>.value(
    value: provider ?? MockUserProvider(mockUser: MockUser(id: 1)),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: AIChat(
          role: 'PATIENT',
          mode: mode,
          patientId: patientId,
          userId: userId,
          ttsEngine: _Tts(),
          hitlMaxPollAttempts: 1,
          hitlPollInterval: const Duration(milliseconds: 100),
        ),
      ),
    ),
  );
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  tester
      .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
      .onPressed!();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void _chatTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      original?.call(details);
    };
    try {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    } finally {
      FlutterError.onError = original;
    }
  });
}

void main() {
  late Directory tmp;
  late _FakeFilePicker picker;

  HttpOverrides? previousOverrides;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('ai_chat_cov_');
    previousOverrides = HttpOverrides.current;
    HttpOverrides.global = _GatewayOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = previousOverrides;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _FakeFilePicker();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _secureStorage,
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _connectivity,
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_connectivity, null);
    _EdgeGateway.up = false;
    _EdgeGateway.models = const ['olmoe-colibri'];
  });

  for (final models in [
    const ['olmoe-colibri', 'other'],
    const ['tiny-edge'],
  ]) {
    _chatTest('legacy question answered by the local edge model $models',
        (tester) async {
      _EdgeGateway.up = true;
      _EdgeGateway.models = models;
      var cloudCalls = 0;
      await http.runWithClient(() async {
        await tester
            .pumpWidget(_chat(mode: AiChatMode.legacyGeneral, userId: 1));
        await tester.pump(const Duration(seconds: 1));
        await _send(tester, 'What time is my walk today?');
        await tester.pump(const Duration(seconds: 1));
        expect(
            find.text('Edge says hello.', skipOffstage: false), findsOneWidget);
      },
          () => MockClient((request) async {
                if (request.url.path.endsWith('/chat')) cloudCalls++;
                return http.Response(jsonEncode({'messages': []}), 200);
              }));
      expect(cloudCalls, 0);
      expect(_EdgeGateway.paths.last, endsWith('/chat/completions'));
    });
  }

  _chatTest('legacy chat without any user id cannot send', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(_chat(
        mode: AiChatMode.legacyGeneral,
        provider: _SignedOutProvider(),
      ));
      await tester.pump(const Duration(seconds: 1));
      await _send(tester, 'Hello?');
      expect(
        find.text(
            'Authentication error: Please log in to use the chat feature.',
            skipOffstage: false),
        findsOneWidget,
      );
    }, () => MockClient((_) async => http.Response('{}', 200)));
  });

  _chatTest('files picked from disk are read and uploaded', (tester) async {
    final utf8File = File('${tmp.path}/notes.txt')
      ..writeAsStringSync('Blood pressure log');
    final latinFile = File('${tmp.path}/legacy.csv')
      ..writeAsBytesSync([0x63, 0x61, 0x66, 0xE9]); // "café" in Latin-1
    final bigFile = File('${tmp.path}/big.txt')..writeAsStringSync('a' * 50010);
    picker.result = FilePickerResult([
      PlatformFile(name: 'notes.txt', size: 18, path: utf8File.path),
      PlatformFile(name: 'legacy.csv', size: 4, path: latinFile.path),
      PlatformFile(name: 'big.txt', size: 50010, path: bigFile.path),
    ]);
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/chat')) {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'success': true, 'aiResponse': 'Read your files.'}),
          200,
        );
      }
      return http.Response(jsonEncode({'messages': []}), 200);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(_chat(mode: AiChatMode.legacyGeneral, userId: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Attach file'));
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(
          find.text('Files to upload:', skipOffstage: false), findsOneWidget);
      expect(find.text('notes.txt', skipOffstage: false), findsOneWidget);
      expect(find.text('legacy.csv', skipOffstage: false), findsOneWidget);
      expect(find.text('big.txt', skipOffstage: false), findsOneWidget);

      await tester.runAsync(() async {
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
            .onPressed!();
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
          find.text('Read your files.', skipOffstage: false), findsOneWidget);
    }, () => client);
    final files =
        (sentBody!['uploadedFiles'] as List).cast<Map<String, dynamic>>();
    expect(files, hasLength(3));
  });
}
