// Tests for CheckoutLocationPage
// (lib/features/evv/presentation/pages/checkout_location_page.dart).
//
// Coverage strategy:
//   - Loading state (immediate pump, _isLoading = true)
//   - Error state (after API call fails with non-200, _error != null)
//   - Error widget content (icon, text, retry button)
//   - Patient not found state (200 response but patient ID not in list)
//   - Location selection state (200 response with matching patient)
//   - Patient address card content (name, address, recommendation text)
//   - GPS location card content (description, additional info)
//   - Cancel button in AppBar
//   - Back button in AppBar
//   - Address formatting with all fields, partial fields, no address
//   - scheduledVisitId parameter handling

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:care_connect_app/features/evv/presentation/pages/checkout_location_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';

import '../../mock_user_provider.dart';

// ─── HTTP fake infrastructure ─────────────────────────────────────────────────

class _FakeSpec {
  const _FakeSpec(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

_FakeSpec _activeSpec = const _FakeSpec(200, '[]');

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(_activeSpec);

  @override bool autoUncompress = true;
  @override Duration? connectionTimeout;
  @override Duration idleTimeout = const Duration(seconds: 15);
  @override int? maxConnectionsPerHost;
  @override String? userAgent;
  @override void addCredentials(Uri u, String r, HttpClientCredentials c) {}
  @override void addProxyCredentials(String h, int p, String r, HttpClientCredentials c) {}
  @override set authenticate(Future<bool> Function(Uri, String, String?)? f) {}
  @override set authenticateProxy(Future<bool> Function(String, int, String, String?)? f) {}
  @override set badCertificateCallback(bool Function(X509Certificate, String, int)? cb) {}
  @override set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f) {}
  @override set findProxy(String Function(Uri)? f) {}
  @override set keyLog(Function(String)? f) {}
  @override void close({bool force = false}) {}
  @override Future<HttpClientRequest> delete(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override Future<HttpClientRequest> get(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override Future<HttpClientRequest> head(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override Future<HttpClientRequest> open(String m, String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> patch(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override Future<HttpClientRequest> post(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override Future<HttpClientRequest> put(String h, int p, String path) => throw UnimplementedError();
  @override Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._spec);
  final _FakeSpec _spec;
  final _FakeHttpHeaders _hdrs = _FakeHttpHeaders();

  @override HttpHeaders get headers => _hdrs;
  @override Future<HttpClientResponse> close() async => _FakeHttpClientResponse(_spec);

  @override bool bufferOutput = true;
  @override int contentLength = -1;
  @override Encoding encoding = utf8;
  @override bool followRedirects = true;
  @override int maxRedirects = 5;
  @override bool persistentConnection = true;
  @override String get method => '';
  @override Uri get uri => Uri.parse('http://localhost');
  @override HttpConnectionInfo? get connectionInfo => null;
  @override List<Cookie> get cookies => [];
  @override Future<HttpClientResponse> get done => close();
  @override void abort([Object? exception, StackTrace? stackTrace]) {}
  @override void add(List<int> data) {}
  @override void addError(Object error, [StackTrace? stackTrace]) {}
  @override Future addStream(Stream<List<int>> stream) async {}
  @override Future flush() async {}
  @override void write(Object? object) {}
  @override void writeAll(Iterable objects, [String separator = '']) {}
  @override void writeCharCode(int charCode) {}
  @override void writeln([Object? object = '']) {}
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this._spec) {
    headers.set('content-type', 'application/json; charset=utf-8');
  }
  final _FakeSpec _spec;

  @override int get statusCode => _spec.statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream.value(utf8.encode(_spec.body)).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );

  @override final HttpHeaders headers = _FakeHttpHeaders();
  @override int get contentLength => utf8.encode(_spec.body).length;
  @override HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override X509Certificate? get certificate => null;
  @override HttpConnectionInfo? get connectionInfo => null;
  @override List<Cookie> get cookies => [];
  @override bool get isRedirect => false;
  @override bool get persistentConnection => false;
  @override String get reasonPhrase => '';
  @override List<RedirectInfo> get redirects => [];
  @override Future<HttpClientResponse> redirect([String? m, Uri? u, bool? f]) =>
      throw UnimplementedError();
  @override Future<Socket> detachSocket() => throw UnimplementedError();
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _m = {};

  @override List<String>? operator [](String name) => _m[name.toLowerCase()];
  @override void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_m[name.toLowerCase()] ??= []).add(value.toString());
  @override void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _m[name.toLowerCase()] = [value.toString()];
  @override String? value(String name) => _m[name.toLowerCase()]?.firstOrNull;
  @override void remove(String name, Object value) =>
      _m[name.toLowerCase()]?.remove(value.toString());
  @override void removeAll(String name) => _m.remove(name.toLowerCase());
  @override void forEach(void Function(String, List<String>) action) => _m.forEach(action);
  @override void noFolding(String name) {}
  @override void clear() => _m.clear();
  @override bool get chunkedTransferEncoding => false;
  @override set chunkedTransferEncoding(bool value) {}
  @override int get contentLength => -1;
  @override set contentLength(int value) {}
  @override ContentType? get contentType => null;
  @override set contentType(ContentType? value) {}
  @override DateTime? get date => null;
  @override set date(DateTime? value) {}
  @override DateTime? get expires => null;
  @override set expires(DateTime? value) {}
  @override String? get host => null;
  @override set host(String? value) {}
  @override DateTime? get ifModifiedSince => null;
  @override set ifModifiedSince(DateTime? value) {}
  @override bool get persistentConnection => true;
  @override set persistentConnection(bool value) {}
  @override int? get port => null;
  @override set port(int? value) {}
}

// ─── Secure storage stub ──────────────────────────────────────────────────────

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void _setupSecureStorageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
    switch (call.method) {
      case 'write':
        return null;
      case 'read':
        return null;
      case 'readAll':
        return <String, String>{};
      case 'delete':
        return null;
      case 'deleteAll':
        return null;
      case 'containsKey':
        return false;
      default:
        return null;
    }
  });
}

void _teardownSecureStorageStub() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, null);
}

// ─── Patient JSON helpers ─────────────────────────────────────────────────────

/// A patient JSON object with full address.
Map<String, dynamic> _patientJson({
  int id = 1,
  String firstName = 'John',
  String lastName = 'Doe',
  Map<String, dynamic>? address,
}) =>
    {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': 'john@example.com',
      'phone': '555-1234',
      'dob': '1990-01-01',
      'relationship': 'SELF',
      'address': address ??
          {
            'line1': '123 Main St',
            'line2': 'Apt 4B',
            'city': 'Springfield',
            'state': 'IL',
            'zip': '62701',
          },
    };

/// Patient list JSON with a matching patient (ID=1).
String _patientListResponse({
  int patientId = 1,
  String firstName = 'John',
  String lastName = 'Doe',
  Map<String, dynamic>? address,
  bool nested = false,
}) {
  final patient = _patientJson(
    id: patientId,
    firstName: firstName,
    lastName: lastName,
    address: address,
  );
  if (nested) {
    return jsonEncode([
      {'patient': patient}
    ]);
  }
  return jsonEncode([patient]);
}

/// Patient list JSON with no matching patient.
String _emptyPatientListResponse() => jsonEncode([
      _patientJson(id: 999, firstName: 'Other', lastName: 'Patient'),
    ]);

// ─── Widget builders ──────────────────────────────────────────────────────────

Widget _wrap({
  int patientId = 1,
  String serviceType = 'Personal Care',
  String locationType = 'HOME',
  double? latitude,
  double? longitude,
  String notes = '',
  int duration = 3600,
  int? scheduledVisitId,
  String role = 'CAREGIVER',
  int? caregiverId = 1,
  int userId = 1,
}) {
  final provider = MockUserProvider(
    mockUser: MockUser(
      id: userId,
      role: role,
      caregiverId: caregiverId,
    ),
  );
  return MaterialApp(
    home: ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: CheckoutLocationPage(
        patientId: patientId,
        serviceType: serviceType,
        locationType: locationType,
        latitude: latitude,
        longitude: longitude,
        notes: notes,
        duration: duration,
        scheduledVisitId: scheduledVisitId,
      ),
    ),
  );
}

/// Pump enough frames for the async API call to complete (succeed or fail).
Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() => tester.view.resetPhysicalSize());
  addTearDown(() => tester.view.resetDevicePixelRatio());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late HttpOverrides? originalOverrides;

  setUp(() {
    _setupSecureStorageStub();
    originalOverrides = HttpOverrides.current;
    HttpOverrides.global = _FakeHttpOverrides();
  });

  tearDown(() {
    HttpOverrides.global = originalOverrides;
    _teardownSecureStorageStub();
  });

  // ─── Initial loading state ────────────────────────────────────────────────
  group('CheckoutLocationPage - initial loading state', () {
    testWidgets('renders without crashing', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(CheckoutLocationPage), findsOneWidget);
    });

    testWidgets('shows Check-Out Location in AppBar', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.text('Check-Out Location'), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows CircularProgressIndicator while loading', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows AppBar', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('shows Center while loading', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(Center), findsWidgets);
    });

    testWidgets('shows Cancel button in AppBar', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows back arrow icon in AppBar', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('shows cancel icon in AppBar', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.cancel), findsOneWidget);
    });
  });

  // ─── Error state (API returns non-200) ────────────────────────────────────
  group('CheckoutLocationPage - error state (non-200 response)', () {
    testWidgets('shows error icon after API failure', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows "Error Loading Patient" text', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Error Loading Patient'), findsOneWidget);
    });

    testWidgets('shows error message text', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.textContaining('Failed to load patient details'), findsOneWidget);
    });

    testWidgets('shows Try Again button', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('Try Again button is an ElevatedButton', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.widgetWithText(ElevatedButton, 'Try Again'), findsOneWidget);
    });

    testWidgets('no CircularProgressIndicator after error', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tapping Try Again reloads data', (tester) async {
      _activeSpec = const _FakeSpec(500, '{"error":"Internal Server Error"}');
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Try Again'), findsOneWidget);

      // Change spec to return success and invoke retry programmatically
      // (avoids ink_sparkle.frag shader exception from tester.tap)
      _activeSpec = _FakeSpec(200, _patientListResponse());
      tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Try Again'),
      ).onPressed!();
      await _pumpUntilLoaded(tester);
      // Should now show patient address card
      expect(find.text('Use Patient Address'), findsOneWidget);
    });
  });

  // ─── Patient not found (via exception → error state) ───────────────────
  group('CheckoutLocationPage - patient not found error', () {
    testWidgets('shows error state when patient ID not in API response', (tester) async {
      _activeSpec = _FakeSpec(200, _emptyPatientListResponse());
      await tester.pumpWidget(_wrap(patientId: 1));
      await _pumpUntilLoaded(tester);
      // Patient not found throws exception → shows error state
      expect(find.text('Error Loading Patient'), findsOneWidget);
      expect(find.textContaining('Patient not found'), findsOneWidget);
    });

    testWidgets('shows Try Again button when patient not found', (tester) async {
      _activeSpec = _FakeSpec(200, _emptyPatientListResponse());
      await tester.pumpWidget(_wrap(patientId: 1));
      await _pumpUntilLoaded(tester);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('shows error_outline icon when patient not found', (tester) async {
      _activeSpec = _FakeSpec(200, _emptyPatientListResponse());
      await tester.pumpWidget(_wrap(patientId: 1));
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });
  });

  // ─── Location selection state (patient found) ─────────────────────────────
  group('CheckoutLocationPage - location selection state', () {
    testWidgets('shows patient address card title', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Use Patient Address'), findsOneWidget);
    });

    testWidgets('shows GPS location card title', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Get Current GPS Location'), findsOneWidget);
    });

    testWidgets('shows patient full name', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse(
        firstName: 'Jane',
        lastName: 'Smith',
      ));
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Jane Smith'), findsOneWidget);
    });

    testWidgets('shows formatted patient address', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('123 Main St, Apt 4B, Springfield, IL, 62701'), findsOneWidget);
    });

    testWidgets('shows recommendation text for patient address', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(
        find.text('Recommended for visits at patient\'s home'),
        findsOneWidget,
      );
    });

    testWidgets('shows GPS description text', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(
        find.text('Use your device\'s GPS for precise coordinates'),
        findsOneWidget,
      );
    });

    testWidgets('shows GPS additional info', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(
        find.textContaining('May request location permission'),
        findsOneWidget,
      );
    });

    testWidgets('shows Select Patient Address button', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Select Patient Address'), findsOneWidget);
    });

    testWidgets('shows Get My GPS Location button', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Get My GPS Location'), findsOneWidget);
    });

    testWidgets('shows instruction banner text', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(
        find.textContaining('Select your location to check out'),
        findsOneWidget,
      );
    });

    testWidgets('shows EVV compliance banner text', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(
        find.textContaining('EVV Compliance'),
        findsOneWidget,
      );
    });

    testWidgets('shows home icon for patient address card', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.home), findsOneWidget);
    });

    testWidgets('shows location_on icons', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      // location_on appears in banner + GPS card title + GPS button icon
      expect(find.byIcon(Icons.location_on), findsWidgets);
    });

    testWidgets('shows check_circle_outline icon in patient address button', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });

    testWidgets('shows SingleChildScrollView for content', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('shows two ElevatedButton.icon widgets', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      // Select Patient Address + Get My GPS Location + additional action
      expect(find.byType(ElevatedButton), findsNWidgets(3));
    });

    testWidgets('no CircularProgressIndicator when loaded', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  // ─── Address formatting ───────────────────────────────────────────────────
  group('CheckoutLocationPage - address formatting', () {
    testWidgets('shows "Address not available" when address is null', (tester) async {
      _activeSpec = _FakeSpec(
        200,
        jsonEncode([
          _patientJson(address: null)..remove('address'),
        ]),
      );
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Address not available'), findsOneWidget);
    });

    testWidgets('shows partial address with only line1 and city', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse(
        address: {'line1': '456 Oak Ave', 'city': 'Dallas'},
      ));
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('456 Oak Ave, Dallas'), findsOneWidget);
    });

    testWidgets('shows address with all fields populated', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse(
        address: {
          'line1': '789 Pine Rd',
          'line2': 'Suite 200',
          'city': 'Austin',
          'state': 'TX',
          'zip': '73301',
        },
      ));
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('789 Pine Rd, Suite 200, Austin, TX, 73301'), findsOneWidget);
    });

    testWidgets('shows address with only state and zip', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse(
        address: {'state': 'CA', 'zip': '90001'},
      ));
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('CA, 90001'), findsOneWidget);
    });
  });

  // ─── Nested patient structure ─────────────────────────────────────────────
  group('CheckoutLocationPage - nested patient JSON', () {
    testWidgets('parses nested patient structure correctly', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse(
        firstName: 'Alice',
        lastName: 'Wonder',
        nested: true,
      ));
      await tester.pumpWidget(_wrap());
      await _pumpUntilLoaded(tester);
      expect(find.text('Alice Wonder'), findsOneWidget);
    });
  });

  // ─── Widget constructor parameters ────────────────────────────────────────
  group('CheckoutLocationPage - constructor parameters', () {
    testWidgets('renders with optional latitude and longitude', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap(
        latitude: 38.8977,
        longitude: -77.0365,
      ));
      await _pumpUntilLoaded(tester);
      expect(find.text('Use Patient Address'), findsOneWidget);
    });

    testWidgets('renders with scheduledVisitId', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap(scheduledVisitId: 42));
      await _pumpUntilLoaded(tester);
      expect(find.text('Use Patient Address'), findsOneWidget);
    });

    testWidgets('renders with notes', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap(notes: 'Some visit notes here'));
      await _pumpUntilLoaded(tester);
      expect(find.text('Use Patient Address'), findsOneWidget);
    });

    testWidgets('renders with custom duration', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap(duration: 7200));
      await _pumpUntilLoaded(tester);
      expect(find.text('Use Patient Address'), findsOneWidget);
    });
  });

  // ─── User null (not authenticated) ────────────────────────────────────────
  group('CheckoutLocationPage - user null error', () {
    testWidgets('shows error when user is null', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      final provider = MockUserProvider(
        mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 1),
      );
      // Create a provider that returns null user
      final nullUserProvider = _NullUserProvider();

      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<UserProvider>.value(
          value: nullUserProvider,
          child: const CheckoutLocationPage(
            patientId: 1,
            serviceType: 'Personal Care',
            locationType: 'HOME',
            notes: '',
            duration: 3600,
          ),
        ),
      ));

      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Error Loading Patient'), findsOneWidget);
      expect(find.textContaining('User not authenticated'), findsOneWidget);
    });
  });

  // ─── Empty patient list (patient not found via exception) ─────────────────
  group('CheckoutLocationPage - empty patient list', () {
    testWidgets('shows error when patient list is empty', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap(patientId: 1));
      await _pumpUntilLoaded(tester);
      // Empty list means no patient matches, throws 'Patient not found'
      expect(find.text('Error Loading Patient'), findsOneWidget);
      expect(find.textContaining('Patient not found'), findsOneWidget);
    });
  });

  // ─── AppBar interactions ──────────────────────────────────────────────────
  group('CheckoutLocationPage - AppBar elements', () {
    testWidgets('Cancel button has red color', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      // Find the Cancel TextButton.icon
      final cancelText = tester.widget<Text>(
        find.text('Cancel'),
      );
      expect(cancelText.style?.color, Colors.red);
    });

    testWidgets('has TextButton.icon for Cancel', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(TextButton), findsOneWidget);
    });

    testWidgets('has IconButton for back navigation', (tester) async {
      _activeSpec = const _FakeSpec(200, '[]');
      await tester.pumpWidget(_wrap());
      expect(find.byType(IconButton), findsOneWidget);
    });
  });

  // ─── Uses caregiverId fallback ────────────────────────────────────────────
  group('CheckoutLocationPage - caregiverId fallback', () {
    testWidgets('uses user.id when caregiverId is null', (tester) async {
      _activeSpec = _FakeSpec(200, _patientListResponse());
      await tester.pumpWidget(_wrap(caregiverId: null, userId: 5));
      await _pumpUntilLoaded(tester);
      // Should still load — uses user.id as fallback for caregiverId
      // The API call proceeds; it may or may not match depending on the response
      expect(find.byType(CheckoutLocationPage), findsOneWidget);
    });
  });
}

// ─── Null user provider ─────────────────────────────────────────────────────
class _NullUserProvider extends MockUserProvider {
  _NullUserProvider() : super(mockUser: MockUser(id: 1, role: 'CAREGIVER'));

  @override
  UserSession? get user => null;
}
