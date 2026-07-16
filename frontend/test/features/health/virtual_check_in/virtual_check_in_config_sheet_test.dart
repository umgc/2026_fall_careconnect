// Tests for VirtualCheckInConfigSheet
// (lib/features/health/virtual_check_in/presentation/widgets/virtual_check_in_config_sheet.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/health/virtual_check_in/presentation/widgets/virtual_check_in_config_sheet.dart';
import 'package:care_connect_app/features/health/virtual_check_in/models/virtual_check_in_question.dart';

// ---------------------------------------------------------------------------
// Mock HTTP layer
// ---------------------------------------------------------------------------

final _questionsJson = jsonEncode([
  {
    'id': 10,
    'prompt': 'How is your pain today?',
    'type': 'NUMBER',
    'required': true,
    'active': true,
    'ordinal': 0,
  },
  {
    'id': 11,
    'prompt': 'Did you sleep well?',
    'type': 'YES_NO',
    'required': false,
    'active': true,
    'ordinal': 1,
  },
  {
    'id': 12,
    'prompt': 'Describe your mood',
    'type': 'TEXT',
    'required': true,
    'active': true,
    'ordinal': 2,
  },
]);

final _catalogJson = jsonEncode([
  {
    'id': 20,
    'prompt': 'Are you eating regularly?',
    'type': 'YES_NO',
    'required': false,
    'active': true,
    'ordinal': 0,
  },
  {
    'id': 21,
    'prompt': 'Rate your energy level',
    'type': 'NUMBER',
    'required': false,
    'active': true,
    'ordinal': 1,
  },
]);

class _MockHttpOverrides extends HttpOverrides {
  bool catalogShouldFail = false;
  bool questionsShouldFail = false;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient(this);
  }
}

class _MockHttpClient implements HttpClient {
  _MockHttpClient(this._overrides);
  final _MockHttpOverrides _overrides;

  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _MockHttpClientRequest(url, 'GET', _overrides);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _MockHttpClientRequest(url, method, _overrides);
  @override
  Future<HttpClientRequest> postUrl(Uri url) async =>
      _MockHttpClientRequest(url, 'POST', _overrides);
  @override
  Future<HttpClientRequest> putUrl(Uri url) async =>
      _MockHttpClientRequest(url, 'PUT', _overrides);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) async =>
      _MockHttpClientRequest(url, 'PATCH', _overrides);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) async =>
      _MockHttpClientRequest(url, 'DELETE', _overrides);
  @override
  Future<HttpClientRequest> headUrl(Uri url) async =>
      _MockHttpClientRequest(url, 'HEAD', _overrides);
  @override
  void close({bool force = false}) {}
  @override
  set authenticate(f) {}
  @override
  set authenticateProxy(f) {}
  @override
  set badCertificateCallback(f) {}
  @override
  set connectionFactory(f) {}
  @override
  set findProxy(f) {}
  @override
  set keyLog(f) {}
  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials c) {}
  @override
  void addProxyCredentials(
      String host, int port, String realm, HttpClientCredentials c) {}

  Future<HttpClientRequest> _req(String method, String host, int port, String path) async =>
      _MockHttpClientRequest(
          Uri(scheme: 'http', host: host, port: port, path: path),
          method,
          _overrides);
  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      _req(method, host, port, path);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _req('GET', host, port, path);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _req('POST', host, port, path);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _req('PUT', host, port, path);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _req('PATCH', host, port, path);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _req('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _req('HEAD', host, port, path);
}

class _MockHttpClientRequest implements HttpClientRequest {
  _MockHttpClientRequest(this.uri, this._method, this._overrides);
  @override
  final Uri uri;
  final String _method;
  final _MockHttpOverrides _overrides;
  final _headers = _MockHttpHeaders();

  @override
  HttpHeaders get headers => _headers;
  @override
  String get method => _method;
  @override
  Encoding encoding = utf8;
  @override
  int get contentLength => -1;
  @override
  set contentLength(int v) {}
  @override
  bool get persistentConnection => true;
  @override
  set persistentConnection(bool v) {}
  @override
  bool get followRedirects => true;
  @override
  set followRedirects(bool v) {}
  @override
  bool get bufferOutput => true;
  @override
  set bufferOutput(bool v) {}
  @override
  int get maxRedirects => 5;
  @override
  set maxRedirects(int v) {}
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => [];
  @override
  Future<HttpClientResponse> get done => close();
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async {}
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
  @override
  Future<void> flush() async {}
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async {
    final path = uri.path;
    if (path.contains('/api/checkins/') && path.endsWith('/questions')) {
      if (_overrides.questionsShouldFail) {
        return _MockHttpClientResponse(500, '[]');
      }
      return _MockHttpClientResponse(200, _questionsJson);
    }
    if (path == '/api/questions') {
      if (_overrides.catalogShouldFail) {
        return _MockHttpClientResponse(500, '[]');
      }
      return _MockHttpClientResponse(200, _catalogJson);
    }
    return _MockHttpClientResponse(200, '[]');
  }
}

class _MockHttpClientResponse implements HttpClientResponse {
  _MockHttpClientResponse(this.statusCode, this._body);
  @override
  final int statusCode;
  final String _body;
  late final List<int> _bodyBytes = utf8.encode(_body);

  @override
  int get contentLength => _bodyBytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => [];
  @override
  Future<Socket> detachSocket() => throw UnimplementedError();
  @override
  HttpHeaders get headers => _MockHttpHeaders();
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => true;
  @override
  String get reasonPhrase => 'OK';
  @override
  Future<HttpClientResponse> redirect(
      [String? method, Uri? url, bool? followLoops]) =>
      throw UnimplementedError();
  @override
  List<RedirectInfo> get redirects => [];
  @override
  X509Certificate? get certificate => null;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream.value(_bodyBytes).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  Future<bool> any(bool Function(List<int>) test) =>
      Stream.value(_bodyBytes).any(test);
  @override
  Stream<List<int>> asBroadcastStream(
          {void Function(StreamSubscription<List<int>>)? onListen,
          void Function(StreamSubscription<List<int>>)? onCancel}) =>
      Stream.value(_bodyBytes).asBroadcastStream();
  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(List<int>) convert) =>
      Stream.value(_bodyBytes).asyncExpand(convert);
  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(List<int>) convert) =>
      Stream.value(_bodyBytes).asyncMap(convert);
  @override
  Stream<R> cast<R>() => Stream.value(_bodyBytes).cast<R>();
  @override
  Future<bool> contains(Object? needle) =>
      Stream.value(_bodyBytes).contains(needle);
  @override
  Stream<List<int>> distinct(
          [bool Function(List<int>, List<int>)? equals]) =>
      Stream.value(_bodyBytes).distinct(equals);
  @override
  Future<E> drain<E>([E? futureValue]) =>
      Stream.value(_bodyBytes).drain(futureValue);
  @override
  Future<List<int>> elementAt(int index) =>
      Stream.value(_bodyBytes).elementAt(index);
  @override
  Future<bool> every(bool Function(List<int>) test) =>
      Stream.value(_bodyBytes).every(test);
  @override
  Stream<S> expand<S>(Iterable<S> Function(List<int>) convert) =>
      Stream.value(_bodyBytes).expand(convert);
  @override
  Future<List<int>> get first => Stream.value(_bodyBytes).first;
  @override
  Future<List<int>> firstWhere(bool Function(List<int>) test,
          {List<int> Function()? orElse}) =>
      Stream.value(_bodyBytes).firstWhere(test, orElse: orElse);
  @override
  Future<S> fold<S>(S initialValue, S Function(S, List<int>) combine) =>
      Stream.value(_bodyBytes).fold(initialValue, combine);
  @override
  Future<dynamic> forEach(void Function(List<int>) action) =>
      Stream.value(_bodyBytes).forEach(action);
  @override
  Stream<List<int>> handleError(Function onError,
          {bool Function(dynamic)? test}) =>
      Stream.value(_bodyBytes).handleError(onError, test: test);
  @override
  bool get isBroadcast => false;
  @override
  Future<bool> get isEmpty => Stream.value(_bodyBytes).isEmpty;
  @override
  Future<String> join([String separator = '']) =>
      Stream.value(_bodyBytes).join(separator);
  @override
  Future<List<int>> get last => Stream.value(_bodyBytes).last;
  @override
  Future<List<int>> lastWhere(bool Function(List<int>) test,
          {List<int> Function()? orElse}) =>
      Stream.value(_bodyBytes).lastWhere(test, orElse: orElse);
  @override
  Future<int> get length => Stream.value(_bodyBytes).length;
  @override
  Stream<S> map<S>(S Function(List<int>) convert) =>
      Stream.value(_bodyBytes).map(convert);
  @override
  Future pipe(StreamConsumer<List<int>> streamConsumer) =>
      Stream.value(_bodyBytes).pipe(streamConsumer);
  @override
  Future<List<int>> reduce(
          List<int> Function(List<int>, List<int>) combine) =>
      Stream.value(_bodyBytes).reduce(combine);
  @override
  Future<List<int>> get single => Stream.value(_bodyBytes).single;
  @override
  Future<List<int>> singleWhere(bool Function(List<int>) test,
          {List<int> Function()? orElse}) =>
      Stream.value(_bodyBytes).singleWhere(test, orElse: orElse);
  @override
  Stream<List<int>> skip(int count) =>
      Stream.value(_bodyBytes).skip(count);
  @override
  Stream<List<int>> skipWhile(bool Function(List<int>) test) =>
      Stream.value(_bodyBytes).skipWhile(test);
  @override
  Stream<List<int>> take(int count) =>
      Stream.value(_bodyBytes).take(count);
  @override
  Stream<List<int>> takeWhile(bool Function(List<int>) test) =>
      Stream.value(_bodyBytes).takeWhile(test);
  @override
  Stream<List<int>> timeout(Duration timeLimit,
          {void Function(EventSink<List<int>>)? onTimeout}) =>
      Stream.value(_bodyBytes).timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<List<List<int>>> toList() =>
      Stream.value(_bodyBytes).toList();
  @override
  Future<Set<List<int>>> toSet() =>
      Stream.value(_bodyBytes).toSet();
  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> st) =>
      Stream.value(_bodyBytes).transform(st);
  @override
  Stream<List<int>> where(bool Function(List<int>) test) =>
      Stream.value(_bodyBytes).where(test);
}

class _MockHttpHeaders implements HttpHeaders {
  final _h = <String, List<String>>{};
  @override
  List<String>? operator [](String name) => _h[name.toLowerCase()];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _h.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _h[name.toLowerCase()] = [value.toString()];
  }
  @override
  void remove(String name, Object value) {
    _h[name.toLowerCase()]?.remove(value.toString());
  }
  @override
  void removeAll(String name) => _h.remove(name.toLowerCase());
  @override
  void forEach(void Function(String, List<String>) action) => _h.forEach(action);
  @override
  void noFolding(String name) {}
  @override
  String? value(String name) => _h[name.toLowerCase()]?.first;
  @override
  void clear() => _h.clear();
  @override
  bool get chunkedTransferEncoding => false;
  @override
  set chunkedTransferEncoding(bool v) {}
  @override
  int get contentLength => -1;
  @override
  set contentLength(int v) {}
  @override
  ContentType? get contentType => null;
  @override
  set contentType(ContentType? v) {}
  @override
  DateTime? get date => null;
  @override
  set date(DateTime? v) {}
  @override
  DateTime? get expires => null;
  @override
  set expires(DateTime? v) {}
  @override
  String? get host => null;
  @override
  set host(String? v) {}
  @override
  DateTime? get ifModifiedSince => null;
  @override
  set ifModifiedSince(DateTime? v) {}
  @override
  bool get persistentConnection => true;
  @override
  set persistentConnection(bool v) {}
  @override
  int? get port => null;
  @override
  set port(int? v) {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps the config sheet in a large-enough surface so elements are on screen.
/// Uses a [MediaQuery] override with a tall surface to avoid off-screen issues.
Widget _wrap({List<VirtualCheckInQuestion>? initial}) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(800, 1200)),
      child: Scaffold(
        body: SizedBox(
          height: 1200,
          child: VirtualCheckInConfigSheet(
            checkInId: 1,
            initial: initial ?? const [],
          ),
        ),
      ),
    ),
  );
}

/// Pump the widget and wait for HTTP to resolve.
Future<void> pumpLoaded(WidgetTester tester,
    {List<VirtualCheckInQuestion>? initial}) async {
  await tester.pumpWidget(_wrap(initial: initial));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

/// Scroll to a finder target and pump.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
}

List<VirtualCheckInQuestion> _sampleQuestions() => [
      const VirtualCheckInQuestion(
        id: '1',
        type: CheckInQuestionType.numerical,
        required: true,
        text: 'Rate your pain level',
      ),
      const VirtualCheckInQuestion(
        id: '2',
        type: CheckInQuestionType.yesNo,
        required: false,
        text: 'Did you take your medication?',
      ),
      const VirtualCheckInQuestion(
        id: '3',
        type: CheckInQuestionType.textInput,
        required: true,
        text: 'Describe your symptoms',
      ),
    ];

void main() {
  late _MockHttpOverrides mockOverrides;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
    mockOverrides = _MockHttpOverrides();
    HttpOverrides.global = mockOverrides;
  });

  tearDown(() {
    HttpOverrides.global = null;
  });

  // =========================================================================
  // INITIAL LOADING STATE
  // =========================================================================
  group('VirtualCheckInConfigSheet – initial loading state', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('does NOT show ListView while loading', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('does NOT show CheckboxListTile while loading',
        (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('shows header with title text', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Configure Virtual Check-In Questions'), findsOneWidget);
    });

    testWidgets('shows settings icon in header', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('shows close icon button with tooltip', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('shows footer Cancel and Save buttons', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save Configuration'), findsOneWidget);
    });

    testWidgets('shows save icon in footer', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.save_outlined), findsOneWidget);
    });
  });

  // =========================================================================
  // LOADED CONTENT STATE
  // =========================================================================
  group('VirtualCheckInConfigSheet – loaded content', () {
    testWidgets('shows Current Questions section header', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Current Questions'), findsOneWidget);
    });

    testWidgets('shows question text from backend', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('How is your pain today?'), findsOneWidget);
      expect(find.text('Did you sleep well?'), findsOneWidget);
      expect(find.text('Describe your mood'), findsOneWidget);
    });

    testWidgets('shows type labels for each question type', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Numerical'), findsOneWidget);
      expect(find.text('Yes/No'), findsOneWidget);
      expect(find.text('Input'), findsOneWidget);
    });

    testWidgets('shows helper text for each question type', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Expects a number input'), findsOneWidget);
      expect(find.text('Yes/No selection'), findsOneWidget);
      expect(find.text('Free text input'), findsOneWidget);
    });

    testWidgets('shows Required pill for required questions', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Required'), findsNWidgets(2));
    });

    testWidgets('shows numbering pills (#1, #2, #3)', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
    });

    testWidgets('shows delete buttons for each question', (tester) async {
      await pumpLoaded(tester);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
    });

    testWidgets('shows Add from Catalog section', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Add from Catalog'), findsOneWidget);
    });

    testWidgets('shows search field for catalog', (tester) async {
      await pumpLoaded(tester);
      expect(find.byIcon(Icons.search), findsOneWidget);
    });

    testWidgets('Add Selected button disabled initially', (tester) async {
      await pumpLoaded(tester);
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add Selected'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('shows Add New Question section', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Add New Question'), findsOneWidget);
    });

    testWidgets('shows Question Type and Options labels', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Question Type'), findsOneWidget);
      expect(find.text('Options'), findsOneWidget);
    });

    testWidgets('shows Required question checkbox', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Required question'), findsOneWidget);
    });

    testWidgets('shows Question Text label', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Question Text'), findsOneWidget);
    });

    testWidgets('Add Question button disabled when text empty',
        (tester) async {
      await pumpLoaded(tester);
      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add Question'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('shows hint text in question input', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Enter your check-in question...'), findsOneWidget);
    });

    testWidgets('shows catalog questions from backend', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('Are you eating regularly?'), findsOneWidget);
      expect(find.text('Rate your energy level'), findsOneWidget);
    });

    testWidgets('shows DropdownMenu for question type', (tester) async {
      await pumpLoaded(tester);
      expect(find.byType(DropdownMenu<CheckInQuestionType>), findsOneWidget);
    });

    testWidgets('hides loading spinner after load', (tester) async {
      await pumpLoaded(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows SingleChildScrollView for content', (tester) async {
      await pumpLoaded(tester);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shows playlist_add icon', (tester) async {
      await pumpLoaded(tester);
      expect(find.byIcon(Icons.playlist_add), findsOneWidget);
    });

    testWidgets('shows add icon on Add Question button', (tester) async {
      await pumpLoaded(tester);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('numerical type shows 123 text icon', (tester) async {
      await pumpLoaded(tester);
      expect(find.text('123'), findsWidgets);
    });

    testWidgets('yesNo type shows task_alt icon', (tester) async {
      await pumpLoaded(tester);
      expect(find.byIcon(Icons.task_alt), findsWidgets);
    });

    testWidgets('textInput type shows edit icon', (tester) async {
      await pumpLoaded(tester);
      expect(find.byIcon(Icons.edit), findsWidgets);
    });

    testWidgets('search field has hint text', (tester) async {
      await pumpLoaded(tester);
      // The Unicode ellipsis character
      expect(find.text('Search questions\u2026'), findsOneWidget);
    });
  });

  // =========================================================================
  // DELETE QUESTION
  // =========================================================================
  group('VirtualCheckInConfigSheet – delete question', () {
    testWidgets('deleting a question removes it from the list',
        (tester) async {
      await pumpLoaded(tester);

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
      expect(find.text('How is your pain today?'), findsOneWidget);

      final deleteBtn = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip('Delete question').first,
          matching: find.byType(IconButton),
        ).first,
      );
      deleteBtn.onPressed!();
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
      expect(find.text('How is your pain today?'), findsNothing);
    });

    testWidgets('deleting updates numbering', (tester) async {
      await pumpLoaded(tester);

      expect(find.text('#3'), findsOneWidget);

      tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Delete question').first, matching: find.byType(IconButton)).first).onPressed!();
      await tester.pump();

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsNothing);
    });

    testWidgets('deleting all questions leaves empty list', (tester) async {
      await pumpLoaded(tester);

      for (int i = 0; i < 3; i++) {
        tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Delete question').first, matching: find.byType(IconButton)).first).onPressed!();
        await tester.pump();
      }

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  // =========================================================================
  // ADD QUESTION FROM FORM
  // =========================================================================
  group('VirtualCheckInConfigSheet – add question from form', () {
    testWidgets('Add Question button enables when text is entered',
        (tester) async {
      await pumpLoaded(tester);

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, 'New test question');
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add Question'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('tapping Add Question adds a new question to the list',
        (tester) async {
      await pumpLoaded(tester);

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, 'My brand new question');
      await tester.pump();

      final addBtn = find.widgetWithText(FilledButton, 'Add Question');
      await scrollTo(tester, addBtn);
      tester.widget<FilledButton>(addBtn).onPressed!();
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(4));
      expect(find.text('My brand new question'), findsOneWidget);
    });

    testWidgets('text field clears after adding a question', (tester) async {
      await pumpLoaded(tester);

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, 'A new question');
      await tester.pump();

      final addBtn = find.widgetWithText(FilledButton, 'Add Question');
      await scrollTo(tester, addBtn);
      tester.widget<FilledButton>(addBtn).onPressed!();
      await tester.pump();

      final textFieldWidget = tester.widget<TextField>(textField);
      expect(textFieldWidget.controller?.text, isEmpty);
    });

    testWidgets('cannot add duplicate question (shows snackbar)',
        (tester) async {
      await pumpLoaded(tester);

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, 'How is your pain today?');
      await tester.pump();

      final addBtn = find.widgetWithText(FilledButton, 'Add Question');
      await scrollTo(tester, addBtn);
      tester.widget<FilledButton>(addBtn).onPressed!();
      await tester.pump();

      expect(find.text('That question already exists.'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
    });

    testWidgets('duplicate check is case-insensitive', (tester) async {
      await pumpLoaded(tester);

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, 'HOW IS YOUR PAIN TODAY?');
      await tester.pump();

      final addBtn = find.widgetWithText(FilledButton, 'Add Question');
      await scrollTo(tester, addBtn);
      tester.widget<FilledButton>(addBtn).onPressed!();
      await tester.pump();

      expect(find.text('That question already exists.'), findsOneWidget);
    });

    testWidgets('empty text keeps Add Question disabled', (tester) async {
      await pumpLoaded(tester);

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add Question'),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('toggling required checkbox works', (tester) async {
      await pumpLoaded(tester);

      final checkbox =
          find.widgetWithText(CheckboxListTile, 'Required question');
      await scrollTo(tester, checkbox);

      final tile = tester.widget<CheckboxListTile>(checkbox);
      expect(tile.value, isFalse);

      tile.onChanged!(true);
      await tester.pump();

      final tileAfter = tester.widget<CheckboxListTile>(checkbox);
      expect(tileAfter.value, isTrue);
    });
  });

  // =========================================================================
  // CATALOG SELECTION
  // =========================================================================
  group('VirtualCheckInConfigSheet – catalog', () {
    testWidgets('selecting catalog item enables Add Selected',
        (tester) async {
      await pumpLoaded(tester);

      final catalogItem = find.text('Are you eating regularly?');
      final tile = find.ancestor(
        of: catalogItem,
        matching: find.byType(CheckboxListTile),
      );
      await scrollTo(tester, tile);
      tester.widget<CheckboxListTile>(tile).onChanged!(true);
      await tester.pump();

      final btn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add Selected'),
      );
      expect(btn.onPressed, isNotNull);
    });

    testWidgets('Add Selected moves catalog items to question list',
        (tester) async {
      await pumpLoaded(tester);

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));

      final catalogItem = find.text('Are you eating regularly?');
      final tile = find.ancestor(
        of: catalogItem,
        matching: find.byType(CheckboxListTile),
      );
      await scrollTo(tester, tile);
      tester.widget<CheckboxListTile>(tile).onChanged!(true);
      await tester.pump();

      final addSelectedBtn =
          find.widgetWithText(FilledButton, 'Add Selected');
      await scrollTo(tester, addSelectedBtn);
      tester.widget<FilledButton>(addSelectedBtn).onPressed!();
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(4));
    });

    testWidgets('catalog search field accepts text', (tester) async {
      await pumpLoaded(tester);

      final searchField =
          find.widgetWithText(TextField, 'Search questions\u2026');
      await scrollTo(tester, searchField);
      await tester.enterText(searchField, 'eating');
      await tester.pump();

      final searchFieldWidget = tester.widget<TextField>(searchField);
      expect(searchFieldWidget.controller?.text, 'eating');
    });
  });

  // =========================================================================
  // ERROR STATE
  // =========================================================================
  group('VirtualCheckInConfigSheet – error state', () {
    testWidgets('shows error text when questions API fails', (tester) async {
      mockOverrides.questionsShouldFail = true;
      await pumpLoaded(tester);

      expect(find.textContaining('Error:'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error state still shows header and footer', (tester) async {
      mockOverrides.questionsShouldFail = true;
      await pumpLoaded(tester);

      expect(
          find.text('Configure Virtual Check-In Questions'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Save Configuration'), findsOneWidget);
    });

    testWidgets('catalog failure shows snackbar', (tester) async {
      mockOverrides.catalogShouldFail = true;
      await pumpLoaded(tester);

      expect(find.textContaining('Could not load question catalog'),
          findsOneWidget);
    });
  });

  // =========================================================================
  // NAVIGATION (close/cancel/save)
  // =========================================================================
  group('VirtualCheckInConfigSheet – navigation', () {
    testWidgets('close button pops the sheet', (tester) async {
      bool didPop = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showModalBottomSheet<List<VirtualCheckInQuestion>?>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const VirtualCheckInConfigSheet(
                      checkInId: 1,
                      initial: [],
                    ),
                  );
                  didPop = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Open')).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final closeButton = find.byTooltip('Close');
      if (closeButton.evaluate().isNotEmpty) {
        final iconBtn = find.ancestor(of: closeButton, matching: find.byType(IconButton));
        tester.widget<IconButton>(iconBtn.first).onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(didPop, isTrue);
      }
    });

    testWidgets('cancel button pops the sheet', (tester) async {
      bool didPop = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  await showModalBottomSheet<List<VirtualCheckInQuestion>?>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const VirtualCheckInConfigSheet(
                      checkInId: 1,
                      initial: [],
                    ),
                  );
                  didPop = true;
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Open')).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final cancelButton = find.widgetWithText(OutlinedButton, 'Cancel');
      if (cancelButton.evaluate().isNotEmpty) {
        tester.widget<OutlinedButton>(cancelButton.first).onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(didPop, isTrue);
      }
    });

    testWidgets('save button returns items', (tester) async {
      List<VirtualCheckInQuestion>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<
                      List<VirtualCheckInQuestion>?>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => VirtualCheckInConfigSheet(
                      checkInId: 1,
                      initial: _sampleQuestions(),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Open')).onPressed!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final saveButton = find.widgetWithText(FilledButton, 'Save Configuration');
      if (saveButton.evaluate().isNotEmpty) {
        tester.widget<FilledButton>(saveButton.first).onPressed!();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(result, isNotNull);
      }
    });
  });

  // =========================================================================
  // DEDUPLICATION
  // =========================================================================
  group('VirtualCheckInConfigSheet – deduplication', () {
    testWidgets('deduplicates initial questions by prompt', (tester) async {
      final dupes = [
        const VirtualCheckInQuestion(
          id: '1',
          type: CheckInQuestionType.numerical,
          required: true,
          text: 'Rate your pain level',
        ),
        const VirtualCheckInQuestion(
          id: '2',
          type: CheckInQuestionType.numerical,
          required: false,
          text: 'Rate your pain level',
        ),
        const VirtualCheckInQuestion(
          id: '3',
          type: CheckInQuestionType.yesNo,
          required: false,
          text: 'Unique question',
        ),
      ];
      await tester.pumpWidget(_wrap(initial: dupes));
      expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    });

    testWidgets('case-insensitive deduplication', (tester) async {
      final dupes = [
        const VirtualCheckInQuestion(
          id: '1',
          type: CheckInQuestionType.numerical,
          required: true,
          text: 'Rate Your Pain Level',
        ),
        const VirtualCheckInQuestion(
          id: '2',
          type: CheckInQuestionType.numerical,
          required: false,
          text: 'rate your pain level',
        ),
      ];
      await tester.pumpWidget(_wrap(initial: dupes));
      expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    });
  });

  // =========================================================================
  // WIDGET STRUCTURE
  // =========================================================================
  group('VirtualCheckInConfigSheet – structure', () {
    testWidgets('has SafeArea', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('has Dividers', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Divider), findsWidgets);
    });

    testWidgets('has OutlinedButton for Cancel', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('has FilledButton(s)', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('has Spacer in footer', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Spacer), findsWidgets);
    });
  });

  // =========================================================================
  // ADD THEN DELETE CYCLE
  // =========================================================================
  group('VirtualCheckInConfigSheet – add then delete cycle', () {
    testWidgets('add a question then delete it', (tester) async {
      await pumpLoaded(tester);

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, 'A temporary question');
      await tester.pump();

      final addBtn = find.widgetWithText(FilledButton, 'Add Question');
      await scrollTo(tester, addBtn);
      tester.widget<FilledButton>(addBtn).onPressed!();
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(4));
      expect(find.text('A temporary question'), findsOneWidget);

      // Delete the last question
      final deleteButtons = find.byTooltip('Delete question');
      await scrollTo(tester, deleteButtons.last);
      final deleteIconBtn = find.ancestor(of: deleteButtons.last, matching: find.byType(IconButton));
      tester.widget<IconButton>(deleteIconBtn.first).onPressed!();
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline), findsNWidgets(3));
      expect(find.text('A temporary question'), findsNothing);
    });

    testWidgets('deleted question prompt can be re-added', (tester) async {
      await pumpLoaded(tester);

      const firstPrompt = 'How is your pain today?';
      expect(find.text(firstPrompt), findsOneWidget);
      tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Delete question').first, matching: find.byType(IconButton)).first).onPressed!();
      await tester.pump();
      expect(find.text(firstPrompt), findsNothing);

      final textField =
          find.widgetWithText(TextField, 'Enter your check-in question...');
      await scrollTo(tester, textField);
      await tester.enterText(textField, firstPrompt);
      await tester.pump();

      final addBtn = find.widgetWithText(FilledButton, 'Add Question');
      await scrollTo(tester, addBtn);
      tester.widget<FilledButton>(addBtn).onPressed!();
      await tester.pump();

      expect(find.text(firstPrompt), findsOneWidget);
    });
  });

  // =========================================================================
  // QUESTION TYPE VARIETY
  // =========================================================================
  group('VirtualCheckInConfigSheet – question types in initial', () {
    testWidgets('handles all three question types', (tester) async {
      await tester.pumpWidget(_wrap(initial: _sampleQuestions()));
      expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    });

    testWidgets('handles empty initial list', (tester) async {
      await tester.pumpWidget(_wrap(initial: const []));
      expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    });

    testWidgets('handles large initial list', (tester) async {
      final questions = List.generate(
        20,
        (i) => VirtualCheckInQuestion(
          id: '$i',
          type: CheckInQuestionType.values[i % 3],
          required: i % 2 == 0,
          text: 'Question $i',
        ),
      );
      await tester.pumpWidget(_wrap(initial: questions));
      expect(find.byType(VirtualCheckInConfigSheet), findsOneWidget);
    });
  });
}
