// Flow tests for NotetakerConfigurationPage
// (lib/pages/notetaker_configuration_page.dart) with a loaded config:
// caregiver patient selection, PII/keyword editing, save success/failure and
// the Android-only voice-sample storage call. NotetakerConfigService uses package:http
// top-level calls (runWithClient); the caregiver patient list goes through
// the ApiService.debugSetHttpClient seam.

import 'dart:async';
import 'dart:convert';

import 'package:care_connect_app/pages/notetaker_configuration_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

Map<String, dynamic> _config(int patientId) => {
      'id': 9,
      'patientId': patientId,
      'isEnabled': true,
      'permitCaregiverAccess': false,
      'triggerKeywords': [
        {'keyword': 'PII_SSN', 'event_type': 'ALERT'},
        {'keyword': 'fall', 'event_type': 'ALERT'},
        {'keyword': 'pharmacy', 'event_type': 'TASK'},
      ],
    };

class _ConfigBackend {
  int putStatus = 200;
  Map<String, dynamic>? lastPut;

  MockClient client() => MockClient((req) async {
        final id = int.parse(RegExp(r'/(\d+)/config').firstMatch(req.url.path)!
            .group(1)!);
        if (req.method == 'PUT') {
          lastPut = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_config(id)), putStatus);
        }
        return http.Response(jsonEncode(_config(id)), 200);
      });
}

Widget _wrap(UserProvider provider) => ChangeNotifierProvider<UserProvider>.value(
      value: provider,
      child: const MaterialApp(home: NotetakerConfigurationPage()),
    );

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

/// Loading a config always calls getExternalStorageDirectory, which is
/// Android-only and throws UnsupportedError on the VM test host from an
/// un-awaited `void async` method. Run [action] in a zone that collects only
/// those errors so the rest of the page can be exercised.
Future<void> _withAndroidOnlyStorageErrors(
    Future<void> Function() action, List<Object> sink) async {
  await runZonedGuarded(action, (error, stack) {
    if (error is UnsupportedError) {
      sink.add(error);
      return;
    }
    Zone.root.handleUncaughtError(error, stack);
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
  });

  testWidgets('caregiver selects a patient, edits terms and saves',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    _ignoreParentData();

    ApiService.debugSetHttpClient(MockClient((req) async => http.Response(
        jsonEncode([
          {
            'patient': {'id': 31, 'firstName': 'Ana', 'lastName': 'Diaz'},
          },
        ]),
        200)));
    addTearDown(ApiService.debugResetHttpClient);

    final backend = _ConfigBackend();
    await http.runWithClient(() async {
      await tester.pumpWidget(_wrap(MockUserProvider(
        mockUser:
            MockUser(role: 'CAREGIVER', patientId: null, caregiverId: 4),
      )));
      await _settle(tester);
      expect(find.text('Select patient'), findsOneWidget);

      final storageErrors = <Object>[];
      await _withAndroidOnlyStorageErrors(() async {
        // The selection callback runs in the zone that opened the menu.
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ana Diaz').last);
        await _settle(tester);
      }, storageErrors);
      expect(storageErrors, hasLength(1));

      expect(find.text('SSN'), findsOneWidget);
      expect(find.text('fall'), findsOneWidget);
      expect(find.text('pharmacy'), findsOneWidget);

      // Remove the PII term and a keyword.
      await tester.tap(find.byTooltip('delete PII'));
      await tester.pump();
      expect(find.text('SSN'), findsNothing);
      await tester.tap(find.byIcon(Icons.delete).first);
      await tester.pump();
      expect(find.text('fall'), findsNothing);

      // Add a PII term.
      await tester.ensureVisible(find.text('Add PII'));
      await tester.tap(find.text('Add PII'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, 'Passport');
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(find.text('Passport'), findsOneWidget);

      // Add a keyword with an event type.
      await tester.ensureVisible(find.text('Add Keyword'));
      await tester.tap(find.text('Add Keyword'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, 'dizzy');
      await tester.tap(find.text('Select an option').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('ALERT').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(find.text('dizzy'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.text('Notetaker configuration saved successfully!'),
          findsOneWidget);

      ScaffoldMessenger.of(tester.element(find.text('Save')))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();
      backend.putStatus = 500;
      await tester.tap(find.text('Save'));
      await _settle(tester);
      expect(find.textContaining('Failed to save configuration'),
          findsOneWidget);
    }, backend.client);

    final keywords = (backend.lastPut!['triggerKeywords'] as List)
        .map((k) => k['keyword'])
        .toList();
    expect(keywords, containsAll(['PII_Passport', 'pharmacy', 'dizzy']));
    expect(backend.lastPut!['patientId'], 31);
  });

  testWidgets('patient config loads and the access toggles flip',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = _ConfigBackend();
    final storageErrors = <Object>[];
    await http.runWithClient(() async {
      await _withAndroidOnlyStorageErrors(() async {
        await tester.pumpWidget(_wrap(MockUserProvider(
          mockUser: MockUser(role: 'PATIENT', patientId: 1),
        )));
        await _settle(tester);
      }, storageErrors);
      expect(find.text('SSN'), findsOneWidget);
      expect(find.text('Enable Notetaker Assistant'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await _settle(tester);
    }, backend.client);
    expect(storageErrors, hasLength(1));
    expect(backend.lastPut!['isEnabled'], isFalse);
    expect(backend.lastPut!['permitCaregiverAccess'], isTrue);
    expect(backend.lastPut!['patientId'], 1);
  });
}
