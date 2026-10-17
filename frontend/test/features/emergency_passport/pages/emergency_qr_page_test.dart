// CC-12 Increment 2: the patient's emergency QR screen (design screen 2).
// Test Plan §3.27: TC-EMG-281…291 and 454…458 (the pull request's), 305…319,
// 334 and 464…467 (Testing Lead: states, the app's own router, accessibility).

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/router/app_router.dart';
import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/emergency_passport/models/passport_view.dart';
import 'package:care_connect_app/features/emergency_passport/pages/emergency_qr_page.dart';
import 'package:care_connect_app/features/emergency_passport/services/passport_service.dart';
import 'package:care_connect_app/features/emergency_passport/services/qr_code_store.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

import '../passport_test_support.dart';

final _created = DateTime.utc(2026, 10, 15, 17);

PassportView _view({bool withCode = true, DateTime? lastScanned}) => PassportView(
      name: 'Mary Johnson',
      sharing: const {
        PassportField.bloodType: true,
        PassportField.allergies: true,
        PassportField.medications: false,
        PassportField.emergencyContact: true,
        PassportField.chronicConditions: false,
      },
      code: withCode
          ? QrCodeStatus(createdAt: _created, lastScannedAt: lastScanned)
          : null,
      ready: withCode,
    );

class _FakeService extends PassportService {
  _FakeService(
      {required this.view, this.loadError, this.makeError, this.turnOffError})
      : super(headers: () async => {}, refresh: () async => null);

  final PassportView view;
  final PassportError? loadError;
  final PassportError? makeError;
  final PassportError? turnOffError;
  int loads = 0;
  int made = 0;
  int turnedOff = 0;

  @override
  Future<void> turnOffCode() async {
    if (turnOffError != null) throw PassportException(turnOffError!);
    turnedOff++;
  }

  @override
  Future<PassportView> getPassport() async {
    loads++;
    if (loadError != null && loads == 1) throw PassportException(loadError!);
    return view;
  }

  @override
  Future<NewQrCode> makeNewCode() async {
    if (makeError != null) throw PassportException(makeError!);
    made++;
    return NewQrCode(
      token: 'new$made',
      url: 'http://localhost:3000/#/passport/new$made',
      createdAt: DateTime.utc(2026, 10, 16, 9),
    );
  }
}

class _MemoryStore extends QrCodeStore {
  _MemoryStore([this.code]) : super(patientId: () async => 1);
  StoredQrCode? code;

  @override
  Future<StoredQrCode?> read() async => code;

  @override
  Future<void> save(StoredQrCode c) async => code = c;

  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    code = null;
  }
}

class _Saver {
  final calls = <(String, String)>[];
  bool result = true;

  Future<Uint8List> make(String data) async {
    calls.add((data, ''));
    return Uint8List.fromList([1, 2, 3]);
  }

  Future<bool> save(Uint8List png, String fileName) async {
    calls.add(('', fileName));
    return result;
  }
}

Future<void> _open(WidgetTester t, _FakeService service, _MemoryStore store,
    {_Saver? saver}) async {
  await t.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final s = saver ?? _Saver();
  await t.pumpWidget(MaterialApp(
    home: EmergencyQrPage(
      service: service,
      store: store,
      makeImage: s.make,
      saveImage: s.save,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('Turn off QR code', () {
    StoredQrCode kept() => StoredQrCode(
        url: 'http://localhost:3000/#/passport/kept', createdAt: _created);

    testWidgets('TC-EMG-454: after confirming, the code is turned off and forgotten here',
        (t) async {
      final service = _FakeService(view: _view());
      final store = _MemoryStore(kept());
      await _open(t, service, store);

      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      expect(find.text('Turn off your QR code?'), findsOneWidget);
      await t.tap(find.text('Turn off'));
      await t.pumpAndSettle();

      expect(service.turnedOff, 1);
      expect(store.clears, 1);
      expect(store.code, isNull);
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);
      expect(find.text('Your QR code is turned off.'), findsOneWidget);
      expect(find.text('Turn off QR code'), findsNothing);
    });

    testWidgets('TC-EMG-455: Cancel leaves the code on', (t) async {
      final service = _FakeService(view: _view());
      final store = _MemoryStore(kept());
      await _open(t, service, store);

      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      expect(service.turnedOff, 0);
      expect(store.clears, 0);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('TC-EMG-456: also offered when the code is not kept on this device',
        (t) async {
      final service = _FakeService(view: _view());
      await _open(t, service, _MemoryStore());
      expect(find.text('Your QR isn\'t saved on this device'), findsOneWidget);

      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Turn off'));
      await t.pumpAndSettle();

      expect(service.turnedOff, 1);
      expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);
    });

    testWidgets('TC-EMG-457: a failure keeps the code and says so', (t) async {
      final service =
          _FakeService(view: _view(), turnOffError: PassportError.server);
      final store = _MemoryStore(kept());
      await _open(t, service, store);

      await t.tap(find.text('Turn off QR code'));
      await t.pumpAndSettle();
      await t.tap(find.text('Turn off'));
      await t.pumpAndSettle();

      expect(store.clears, 0);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.textContaining('couldn\'t turn off'), findsOneWidget);
    });

    testWidgets('TC-EMG-458: not offered when there is no code', (t) async {
      await _open(t, _FakeService(view: _view(withCode: false)), _MemoryStore());
      expect(find.text('Turn off QR code'), findsNothing);
    });
  });

  testWidgets('TC-EMG-281: no code yet: Create my emergency QR makes one, shows and keeps it',
      (t) async {
    final service = _FakeService(view: _view(withCode: false));
    final store = _MemoryStore();
    await _open(t, service, store);

    expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);

    await t.tap(find.text('Create my emergency QR'));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing); // nothing to replace
    expect(service.made, 1);
    expect(store.code!.url, 'http://localhost:3000/#/passport/new1');
    final qr = t.widget<QrImageView>(find.byType(QrImageView));
    expect(qr, isNotNull);
    expect(find.text('Active · created Oct 16, 2026'), findsOneWidget);
    expect(find.text('Last scanned: never'), findsOneWidget);
  });

  testWidgets('TC-EMG-282: a code kept on this device is shown with its status',
      (t) async {
    final store = _MemoryStore(StoredQrCode(
        url: 'http://localhost:3000/#/passport/kept', createdAt: _created));
    await _open(
        t,
        _FakeService(view: _view(lastScanned: DateTime.utc(2026, 10, 17, 12))),
        store);

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.bySemanticsLabel('Your emergency QR code'), findsOneWidget);
    expect(find.text('Mary Johnson'), findsOneWidget);
    expect(find.text('Active · created Oct 15, 2026'), findsOneWidget);
    expect(find.text('Last scanned: Oct 17, 2026'), findsOneWidget);
    expect(find.text('Save QR image'), findsOneWidget);
    expect(find.text('Make a new code'), findsOneWidget);
  });

  testWidgets('TC-EMG-283: an active code not kept here: make a new one after confirming',
      (t) async {
    final service = _FakeService(view: _view());
    final store = _MemoryStore(); // e.g. a new phone
    await _open(t, service, store);

    expect(find.text('Your QR isn\'t saved on this device'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);

    await t.tap(find.text('Make a new code'));
    await t.pumpAndSettle();
    expect(find.text('Make a new code?'), findsOneWidget);
    await t.tap(find.text('Make new code'));
    await t.pumpAndSettle();

    expect(service.made, 1);
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('TC-EMG-284: a code kept from an older code is not shown', (t) async {
    final store = _MemoryStore(StoredQrCode(
        url: 'http://localhost:3000/#/passport/old',
        createdAt: DateTime.utc(2026, 10, 1)));
    await _open(t, _FakeService(view: _view()), store);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Your QR isn\'t saved on this device'), findsOneWidget);
  });

  testWidgets('TC-EMG-285: Cancel keeps the current code', (t) async {
    final service = _FakeService(view: _view());
    final store = _MemoryStore(StoredQrCode(
        url: 'http://localhost:3000/#/passport/kept', createdAt: _created));
    await _open(t, service, store);

    await t.tap(find.text('Make a new code'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(service.made, 0);
    expect(store.code!.url, endsWith('/kept'));
  });

  testWidgets('TC-EMG-286: Save QR image draws the code and saves the picture', (t) async {
    final saver = _Saver();
    final store = _MemoryStore(StoredQrCode(
        url: 'http://localhost:3000/#/passport/kept', createdAt: _created));
    await _open(t, _FakeService(view: _view()), store, saver: saver);

    await t.tap(find.text('Save QR image'));
    await t.pumpAndSettle();

    expect(saver.calls, [
      ('http://localhost:3000/#/passport/kept', ''),
      ('', 'careconnect-emergency-qr.png'),
    ]);
    expect(find.text('QR image ready. Save it to your photos.'), findsOneWidget);
  });

  testWidgets('TC-EMG-287: when saving fails the patient is told to take a screenshot',
      (t) async {
    final saver = _Saver()..result = false;
    final store = _MemoryStore(StoredQrCode(
        url: 'http://localhost:3000/#/passport/kept', createdAt: _created));
    await _open(t, _FakeService(view: _view()), store, saver: saver);

    await t.tap(find.text('Save QR image'));
    await t.pumpAndSettle();
    expect(find.textContaining('take a screenshot'), findsOneWidget);
  });

  testWidgets('TC-EMG-288: What a scan shows lists every section as Shown or Hidden',
      (t) async {
    await _open(t, _FakeService(view: _view(withCode: false)), _MemoryStore());
    expect(find.text('WHAT A SCAN SHOWS'), findsOneWidget);
    expect(find.bySemanticsLabel('Name and age: Always shown'), findsOneWidget);
    expect(find.bySemanticsLabel('Blood type: Shown'), findsOneWidget);
    expect(find.bySemanticsLabel('Allergies: Shown'), findsOneWidget);
    expect(find.bySemanticsLabel('Medications: Hidden'), findsOneWidget);
    expect(find.bySemanticsLabel('Emergency contact: Shown'), findsOneWidget);
    expect(find.bySemanticsLabel('Chronic conditions: Hidden'), findsOneWidget);
    expect(find.text('Change what\'s shared'), findsNothing);
  });

  testWidgets('TC-EMG-289: a failed new code keeps the screen and says so', (t) async {
    final service =
        _FakeService(view: _view(withCode: false), makeError: PassportError.server);
    await _open(t, service, _MemoryStore());
    await t.tap(find.text('Create my emergency QR'));
    await t.pumpAndSettle();
    expect(find.textContaining('couldn\'t make a new code'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('TC-EMG-290: no connection: a message and Try again loads again', (t) async {
    final service =
        _FakeService(view: _view(withCode: false), loadError: PassportError.network);
    await _open(t, service, _MemoryStore());
    expect(find.text('We couldn\'t load your emergency QR'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(service.loads, 2);
    expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);
  });

  testWidgets('TC-EMG-291: a non-patient account is told the QR is for patients only',
      (t) async {
    await _open(
        t,
        _FakeService(
            view: _view(), loadError: PassportError.notPatient),
        _MemoryStore());
    expect(find.text('Only for patients'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  // ---------- Testing Lead: states ----------

  testWidgets(
      'TC-EMG-305: while the passport loads the page shows a spinner announced '
      'as "Loading your emergency QR", then the loaded state', (t) async {
    final handle = t.ensureSemantics();
    final s = _Scripted()..loadGate = Completer();
    await t.pumpWidget(MaterialApp(
        home: EmergencyQrPage(service: s, store: _MemoryStore())));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(t.getSemantics(find.bySemanticsLabel('Loading your emergency QR')),
        isSemantics(label: 'Loading your emergency QR', isLiveRegion: true));
    expect(find.text('WHAT A SCAN SHOWS'), findsNothing);

    s.loadGate!.complete(_view(withCode: false));
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-306: a server error says so and Try again recovers; an ended '
      'session offers Sign in, which opens the login page, and no Try again',
      (t) async {
    final failing = _Scripted(
        view: _view(withCode: false), loadError: PassportError.server);
    await _openThemed(t, failing, _MemoryStore());
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    failing.loadError = null;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(failing.loads, 2);
    expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);

    final router = GoRouter(initialLocation: '/emergency-qr', routes: [
      GoRoute(
          path: '/emergency-qr',
          builder: (_, __) => EmergencyQrPage(
              service: _Scripted(loadError: PassportError.signedOut),
              store: _MemoryStore())),
      GoRoute(path: '/login', builder: (_, __) => const Text('login page')),
    ]);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    expect(find.text('Please sign in again'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await t.tap(find.text('Sign in'));
    await t.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets(
      'TC-EMG-307: while a code is being made its button says so and is off, '
      'so a second tap makes no second code', (t) async {
    final s = _Scripted(view: _view(withCode: false))..makeGate = Completer();
    final store = _MemoryStore();
    await _openThemed(t, s, store);
    await t.tap(find.text('Create my emergency QR'));
    await t.pump();
    expect(find.text('Making your code…'), findsOneWidget);
    expect(_enabled(t, 'Making your code…'), isFalse);
    await t.tap(find.text('Making your code…'), warnIfMissed: false);
    await t.pump();
    expect(s.made, 1);

    s.makeGate!.complete(NewQrCode(
        token: 'n1',
        url: 'http://localhost:3000/#/passport/n1',
        createdAt: DateTime.utc(2026, 10, 16, 9)));
    await t.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(store.code!.url, 'http://localhost:3000/#/passport/n1');
    expect(_enabled(t, 'Make a new code'), isTrue);
  });

  testWidgets(
      'TC-EMG-308: while the picture is being saved the button says "Saving…" '
      'and is off, so it is saved once', (t) async {
    final gate = Completer<bool>();
    var saves = 0;
    await t.binding.setSurfaceSize(const Size(420, 2000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: EmergencyQrPage(
        service: _Scripted(),
        store: _MemoryStore(_kept()),
        makeImage: (_) async => Uint8List(0),
        saveImage: (_, __) {
          saves++;
          return gate.future;
        },
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Save QR image'));
    await t.pump();
    expect(find.text('Saving…'), findsOneWidget);
    expect(_enabled(t, 'Saving…'), isFalse);
    await t.tap(find.text('Saving…'), warnIfMissed: false);
    await t.pump();
    expect(saves, 1);
    gate.complete(true);
    await t.pumpAndSettle();
    expect(find.text('Save QR image'), findsOneWidget);
    expect(find.text('QR image ready. Save it to your photos.'), findsOneWidget);
  });

  testWidgets(
      'TC-EMG-309: the code kept here is shown only when its creation time is '
      'within a second of the server\'s active code', (t) async {
    for (final c in <Duration, bool>{
      const Duration(milliseconds: 999): true,
      const Duration(milliseconds: -999): true,
      const Duration(milliseconds: 1000): false,
      const Duration(milliseconds: -1000): false,
    }.entries) {
      await _openThemed(
          t, _Scripted(), _MemoryStore(_kept(_created.add(c.key))));
      expect(find.byType(QrImageView), c.value ? findsOneWidget : findsNothing,
          reason: '${c.key}');
    }
  });

  testWidgets(
      'TC-EMG-310: leaving the page while it loads or makes a code is safe: '
      'the late answer changes nothing on screen and raises no error',
      (t) async {
    final loading = _Scripted()..loadGate = Completer();
    await t.pumpWidget(MaterialApp(
        home: EmergencyQrPage(service: loading, store: _MemoryStore())));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    loading.loadGate!.complete(_view());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);

    final making = _Scripted(view: _view(withCode: false))
      ..makeGate = Completer();
    final store = _MemoryStore();
    await _openThemed(t, making, store);
    await t.tap(find.text('Create my emergency QR'));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    making.makeGate!.complete(NewQrCode(
        token: 'n1',
        url: 'http://localhost:3000/#/passport/n1',
        createdAt: DateTime.utc(2026, 10, 16, 9)));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    // The code was still kept, so the patient sees it next time.
    expect(store.code!.url, 'http://localhost:3000/#/passport/n1');

    final failing = _Scripted(view: _view(withCode: false))
      ..makeGate = Completer();
    await _openThemed(t, failing, _MemoryStore());
    await t.tap(find.text('Create my emergency QR'));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    failing.makeGate!
        .completeError(const PassportException(PassportError.server));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets(
      'TC-EMG-311: Back returns to the screen that opened the page, or to the '
      'start when the page was opened directly', (t) async {
    final router = GoRouter(initialLocation: '/', routes: [
      GoRoute(
          path: '/',
          builder: (c, __) => Scaffold(
              body: TextButton(
                  onPressed: () => c.push('/emergency-qr'),
                  child: const Text('start')))),
      GoRoute(
          path: '/emergency-qr',
          builder: (_, __) => EmergencyQrPage(
              service: _Scripted(view: _view(withCode: false)),
              store: _MemoryStore())),
    ]);
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.tap(find.text('start'));
    await t.pumpAndSettle();
    expect(find.byType(EmergencyQrPage), findsOneWidget);
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('start'), findsOneWidget);

    router.go('/emergency-qr');
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(router.state.uri.path, '/');
    expect(find.text('start'), findsOneWidget);
  });

  testWidgets(
      'TC-EMG-312: replacing a shown code paints the new link (not the old '
      'one), keeps it, and resets the status to created now, never scanned',
      (t) async {
    final store = _MemoryStore(_kept());
    await _openThemed(t,
        _Scripted(view: _view(lastScanned: DateTime.utc(2026, 10, 17, 12))), store);
    expect(await _qrHolds(t, _keptUrl), isTrue);
    expect(find.text('Last scanned: Oct 17, 2026'), findsOneWidget);

    await t.tap(find.text('Make a new code'));
    await t.pumpAndSettle();
    await t.tap(find.text('Make new code'));
    await t.pumpAndSettle();

    const fresh = 'http://localhost:3000/#/passport/n1';
    expect(store.code!.url, fresh);
    expect(store.code!.createdAt, DateTime.utc(2026, 10, 16, 9));
    expect(await _qrHolds(t, fresh), isTrue);
    expect(await _qrHolds(t, _keptUrl), isFalse);
    expect(find.text('Active · created Oct 16, 2026'), findsOneWidget);
    expect(find.text('Last scanned: never'), findsOneWidget);
    expect(
        find.text(
            'Your new QR code is ready. Save it so you have it with you.'),
        findsOneWidget);
  });

  testWidgets(
      'TC-EMG-334: when the server has no active code (turned off, or never '
      'made), a code still kept on the device is not shown: the page offers '
      'a new one', (t) async {
    final service = _Scripted(view: _view(withCode: false));
    await _openThemed(t, service, _MemoryStore(_kept()));
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text("You don't have an emergency QR yet"), findsOneWidget);
    expect(find.text('Save QR image'), findsNothing);
    expect(find.textContaining('Active'), findsNothing);
  });

  testWidgets(
      'TC-EMG-464: while a code is being turned off its button says '
      '"Turning off…" and both buttons are off, so a second tap sends nothing '
      'more; nothing says a new code is being made', (t) async {
    final s = _Scripted()..turnOffGate = Completer();
    final store = _MemoryStore(_kept());
    await _openThemed(t, s, store);
    await t.tap(find.text('Turn off QR code'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pump();

    expect(find.text('Turning off…'), findsOneWidget);
    expect(_enabled(t, 'Turning off…'), isFalse);
    expect(find.text('Making a new code…'), findsNothing);
    expect(_enabled(t, 'Make a new code'), isFalse);
    await t.tap(find.text('Turning off…'), warnIfMissed: false);
    await t.tap(find.text('Make a new code'), warnIfMissed: false);
    await t.pump();
    expect(s.turnedOff, 1);
    expect(s.made, 0);

    s.turnOffGate!.complete();
    await t.pumpAndSettle();
    expect(store.code, isNull);
    expect(find.text('You don\'t have an emergency QR yet'), findsOneWidget);
    expect(_enabled(t, 'Create my emergency QR'), isTrue);
  });

  testWidgets(
      'TC-EMG-465: leaving the page while a code is being turned off is safe: '
      'the code is still forgotten on this device, and a late failure raises '
      'no error and keeps it', (t) async {
    final ok = _Scripted()..turnOffGate = Completer();
    final store = _MemoryStore(_kept());
    await _openThemed(t, ok, store);
    await t.tap(find.text('Turn off QR code'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    ok.turnOffGate!.complete();
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(store.code, isNull);

    final failing = _Scripted()..turnOffGate = Completer();
    final kept = _MemoryStore(_kept());
    await _openThemed(t, failing, kept);
    await t.tap(find.text('Turn off QR code'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pump();
    await t.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    failing.turnOffGate!
        .completeError(const PassportException(PassportError.server));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(kept.code, isNotNull, reason: 'still on at the server, so kept');
  });

  // ---------- Testing Lead: the app's own router, end to end in process ----------

  group('the app router, the real service and HTTP', () {
    late Map<String, String> secure;
    late List<http.Request> sent;
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.synthetic.signature';

    setUp(() {
      sent = [];
      secure = {'jwt_token': jwt, 'token_expiry': '4102444800'};
      SharedPreferences.setMockInitialValues({'telemetry_opted_out': true});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, (call) async {
        final args = (call.arguments as Map?) ?? const {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return secure[key];
          case 'write':
            secure[key!] = args['value'] as String;
            return null;
          case 'delete':
            secure.remove(key);
            return null;
          case 'readAll':
            return Map<String, String>.of(secure);
          case 'containsKey':
            return secure.containsKey(key);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_secure, null);
    });

    // The app makes other calls of its own (a backend health check); only
    // the passport's are this page's.
    List<String> passportCalls() => [
          for (final r in sent)
            if (r.url.path.startsWith('/v1/api/passport'))
              '${r.method} ${r.url.path}'
        ];

    Future<void> settle(WidgetTester t) async {
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> run(WidgetTester t, Future<void> Function() body,
        {int getStatus = 200}) async {
      await t.binding.setSurfaceSize(const Size(420, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      Map<String, Object?> current = passportJson;
      await http.runWithClient(body, () => MockClient((req) async {
            sent.add(req);
            if (req.method == 'GET' && req.url.path == '/v1/api/passport') {
              return getStatus == 200
                  ? http.Response(jsonEncode(current), 200)
                  : http.Response('{"error":"Patients only"}', getStatus);
            }
            if (req.method == 'POST' &&
                req.url.path == '/v1/api/passport/token') {
              current = {
                ...current,
                'token': {
                  'active': true,
                  'createdAt': '2026-10-16T09:00:00.123456Z',
                  'lastScannedAt': null,
                },
              };
              return http.Response(
                  jsonEncode({
                    'token': 'Q3k9xZ2v',
                    'url': 'http://localhost:3000/#/passport/Q3k9xZ2v',
                    'createdAt': '2026-10-16T09:00:00.123456Z',
                  }),
                  201);
            }
            if (req.method == 'DELETE' &&
                req.url.path == '/v1/api/passport/token') {
              current = {...current, 'token': null};
              return http.Response('', 204);
            }
            return http.Response('{}', 404);
          }));
    }

    testWidgets(
        'TC-EMG-313: a signed-in patient opens /emergency-qr through the '
        'app\'s own router; GET and POST carry the stored sign-in; the new '
        'code is kept on the device under that patient and shown again on the '
        'next visit without making another', (t) async {
      await t.runAsync(() => UserRoleStorageService.instance
          .setUserData(role: 'PATIENT', userId: 70, patientId: 7));
      addTearDown(
          () => t.runAsync(UserRoleStorageService.instance.clearUserData));

      await run(t, () async {
        appRouter.go('/emergency-qr');
        await t.pumpWidget(MaterialApp.router(routerConfig: appRouter));
        await settle(t);
        expect(appRouter.state.uri.path, '/emergency-qr');
        expect(
            find.text('Your QR isn\'t saved on this device'), findsOneWidget);

        await t.tap(find.text('Make a new code'));
        await t.pumpAndSettle();
        await t.tap(find.text('Make new code'));
        await settle(t);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(await _qrHolds(t, 'http://localhost:3000/#/passport/Q3k9xZ2v'),
            isTrue);

        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(MaterialApp.router(routerConfig: appRouter));
        await settle(t);
        expect(find.byType(QrImageView), findsOneWidget);
      });

      expect(passportCalls(), [
        'GET /v1/api/passport',
        'POST /v1/api/passport/token',
        'GET /v1/api/passport',
      ]);
      for (final r in sent.where(
          (r) => r.url.path.startsWith('/v1/api/passport'))) {
        expect(r.headers['Authorization'], 'Bearer $jwt');
      }
      final kept = jsonDecode(secure['cc12_emergency_qr_7']!) as Map;
      expect(kept['url'], 'http://localhost:3000/#/passport/Q3k9xZ2v');
      expect(secure.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
          ['cc12_emergency_qr_7']);
      await t.pumpWidget(const SizedBox());
      appRouter.go('/');
    });

    testWidgets(
        'TC-EMG-314: a signed-in caregiver who opens /emergency-qr is told it '
        'is for patients only (403), with no way to make a code', (t) async {
      await t.runAsync(() => UserRoleStorageService.instance
          .setUserData(role: 'CAREGIVER', userId: 90, caregiverId: 9));
      addTearDown(
          () => t.runAsync(UserRoleStorageService.instance.clearUserData));

      await run(t, () async {
        appRouter.go('/emergency-qr');
        await t.pumpWidget(MaterialApp.router(routerConfig: appRouter));
        await settle(t);
        expect(find.text('Only for patients'), findsOneWidget);
        expect(find.text('Make a new code'), findsNothing);
        expect(find.text('Create my emergency QR'), findsNothing);
        expect(find.text('Try again'), findsNothing);
      }, getStatus: 403);

      expect(passportCalls(), ['GET /v1/api/passport']);
      expect(secure.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
          isEmpty);
      await t.pumpWidget(const SizedBox());
      appRouter.go('/');
    });

    testWidgets(
        'TC-EMG-466: through the app\'s own router, Turn off sends DELETE '
        '/v1/api/passport/token with the stored sign-in, removes the code '
        'kept under that patient, and the next visit offers a new code',
        (t) async {
      await t.runAsync(() => UserRoleStorageService.instance
          .setUserData(role: 'PATIENT', userId: 70, patientId: 7));
      addTearDown(
          () => t.runAsync(UserRoleStorageService.instance.clearUserData));

      await run(t, () async {
        appRouter.go('/emergency-qr');
        await t.pumpWidget(MaterialApp.router(routerConfig: appRouter));
        await settle(t);
        await t.tap(find.text('Make a new code'));
        await t.pumpAndSettle();
        await t.tap(find.text('Make new code'));
        await settle(t);
        expect(secure.containsKey('cc12_emergency_qr_7'), isTrue);

        await t.tap(find.text('Turn off QR code'));
        await t.pumpAndSettle();
        await t.tap(find.text('Turn off'));
        await settle(t);
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('Your QR code is turned off.'), findsOneWidget);

        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(MaterialApp.router(routerConfig: appRouter));
        await settle(t);
        expect(
            find.text('You don\'t have an emergency QR yet'), findsOneWidget);
      });

      expect(passportCalls(), [
        'GET /v1/api/passport',
        'POST /v1/api/passport/token',
        'DELETE /v1/api/passport/token',
        'GET /v1/api/passport',
      ]);
      final delete = sent.singleWhere((r) => r.method == 'DELETE');
      expect(delete.headers['Authorization'], 'Bearer $jwt');
      expect(secure.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
          isEmpty);
      await t.pumpWidget(const SizedBox());
      appRouter.go('/');
    });
  });

  // ---------- Testing Lead: accessibility (WCAG 2.1 AA) ----------

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets(
        'TC-EMG-315: every text on every state, the confirm dialog and the '
        'messages is at least 4.5:1 against what is behind it (SC 1.4.3), app '
        '${theme.key} theme', (t) async {
      final failures = <String>[];
      for (final s in _states().entries) {
        await _openThemed(t, s.value.$1, s.value.$2, theme: theme.value);
        failures.addAll(lowContrastText(t).map((f) => '${s.key}: $f'));
      }
      await _openThemed(t, _Scripted(), _MemoryStore(_kept()),
          theme: theme.value);
      await t.tap(find.text('Make a new code'));
      await t.pumpAndSettle();
      failures.addAll(lowContrastText(t).map((f) => 'dialog: $f'));
      await t.tap(find.text('Make new code'));
      await t.pumpAndSettle();
      failures.addAll(lowContrastText(t).map((f) => 'new code message: $f'));
      expect(failures, isEmpty);
    });

    testWidgets(
        'TC-EMG-467: the Turn off button, its confirm dialog and both of its '
        'messages are at least 4.5:1 against what is behind them (SC 1.4.3), '
        'app ${theme.key} theme', (t) async {
      final failures = <String>[];
      for (final fails in [false, true]) {
        final s = _Scripted()
          ..turnOffError = fails ? PassportError.server : null;
        await _openThemed(t, s, _MemoryStore(_kept()), theme: theme.value);
        failures.addAll(lowContrastText(t)
            .where((f) => f.contains('Turn off'))
            .map((f) => 'button: $f'));
        await t.tap(find.text('Turn off QR code'));
        await t.pumpAndSettle();
        expect(find.text('Turn off your QR code?'), findsOneWidget);
        failures.addAll(lowContrastText(t).map((f) => 'dialog: $f'));
        await t.tap(find.text('Turn off'));
        await t.pumpAndSettle();
        expect(
            find.text(fails
                ? 'We couldn\'t turn off your code. Please try again.'
                : 'Your QR code is turned off.'),
            findsOneWidget);
        failures.addAll(lowContrastText(t)
            .map((f) => '${fails ? 'failure' : 'done'} message: $f'));
      }
      expect(failures, isEmpty);
    });
  }

  testWidgets(
      'TC-EMG-316: at 200% text on a 320 x 640 phone every state lays out '
      'without clipping or overflow (SC 1.4.4, 1.4.10)', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final problems = <String>[];
    for (final s in _states().entries) {
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: EmergencyQrPage(
            key: UniqueKey(), service: s.value.$1, store: s.value.$2),
      ));
      await t.pumpAndSettle();
      final e = t.takeException();
      if (e != null) problems.add('${s.key}: $e');
      // Text in a box too short for it is cut off without any layout error:
      // its paragraph is squeezed to the box, so compare the height the text
      // needs at its width with the height it was given.
      for (final p in find.byType(RichText).evaluate()) {
        final para = p.renderObject! as RenderParagraph;
        final needed = para.getMaxIntrinsicHeight(para.size.width);
        if (needed > para.size.height + 0.5) {
          problems.add('${s.key}: "${para.text.toPlainText()}" needs '
              '${needed.toStringAsFixed(0)} px but has '
              '${para.size.height.toStringAsFixed(0)} px');
        }
      }
      // A label taller than its button is painted outside it (cut off on
      // screen) without any layout error, so measure it.
      for (final button in find.bySubtype<ButtonStyleButton>().evaluate()) {
        final box = button.renderObject! as RenderBox;
        for (final text in find
            .descendant(
                of: find.byWidget(button.widget), matching: find.byType(Text))
            .evaluate()) {
          final label = (text.widget as Text).data;
          final textBox = text.renderObject! as RenderBox;
          final top = textBox.localToGlobal(Offset.zero).dy -
              box.localToGlobal(Offset.zero).dy;
          if (top < 0 || top + textBox.size.height > box.size.height) {
            problems.add('${s.key}: "$label" is '
                '${textBox.size.height.toStringAsFixed(0)} px tall in a '
                '${box.size.height.toStringAsFixed(0)} px button');
          }
        }
      }
    }
    expect(problems, isEmpty);
  });

  testWidgets(
      'TC-EMG-317: each card title and "What a scan shows" is a heading, and '
      'the title of each problem state is a heading and a live region',
      (t) async {
    final handle = t.ensureSemantics();
    for (final s in {
      'no code yet': 'You don\'t have an emergency QR yet',
      'not on this device': 'Your QR isn\'t saved on this device',
    }.entries) {
      final st = _states()[s.key]!;
      await _openThemed(t, st.$1, st.$2);
      expect(t.getSemantics(find.text(s.value)), isSemantics(isHeader: true),
          reason: s.value);
      expect(t.getSemantics(find.text('WHAT A SCAN SHOWS')),
          isSemantics(isHeader: true));
    }
    for (final s in {
      "couldn't load": 'We couldn\'t load your emergency QR',
      'something went wrong': 'Something went wrong',
      'signed out': 'Please sign in again',
      'only for patients': 'Only for patients',
    }.entries) {
      final st = _states()[s.key]!;
      await _openThemed(t, st.$1, st.$2);
      expect(t.getSemantics(find.text(s.value)),
          isSemantics(isLiveRegion: true, isHeader: true),
          reason: s.value);
    }
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-318: every button on every state is at least 48 x 48 and '
      'labelled (Android and iOS tap-target guidelines, SC 2.5.5 advisory)',
      (t) async {
    final handle = t.ensureSemantics();
    for (final s in _states().entries) {
      await _openThemed(t, s.value.$1, s.value.$2,
          theme: AppTheme.lightTheme);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline),
          reason: s.key);
      await expectLater(t, meetsGuideline(iOSTapTargetGuideline),
          reason: s.key);
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline),
          reason: s.key);
    }
    handle.dispose();
  });

  testWidgets(
      'TC-EMG-319: a screen reader meets the QR as one image named "Your '
      'emergency QR code" (never the link), each sharing row as one '
      '"section: Shown/Hidden" phrase, and every button by its label',
      (t) async {
    final handle = t.ensureSemantics();
    await _openThemed(t, _Scripted(), _MemoryStore(_kept()));
    final qr = find.bySemanticsLabel('Your emergency QR code');
    expect(qr, findsOneWidget);
    expect(t.getSemantics(qr), isSemantics(isImage: true));
    expect(find.bySemanticsLabel(RegExp('passport/kept')), findsNothing);
    for (final f in PassportField.values) {
      final value = _view().isShared(f) ? 'Shown' : 'Hidden';
      expect(find.bySemanticsLabel('${f.label}: $value'), findsOneWidget);
      expect(find.bySemanticsLabel(f.label), findsNothing,
          reason: '${f.label} is read once, with its value');
    }
    for (final label in ['Save QR image', 'Make a new code']) {
      expect(t.getSemantics(find.bySemanticsLabel(label)),
          isSemantics(
              label: label,
              isButton: true,
              hasTapAction: true,
              hasEnabledState: true,
              isEnabled: true,
              isFocusable: true),
          reason: label);
    }
    expect(t.getSemantics(find.byTooltip('Back')),
        isSemantics(tooltip: 'Back', isButton: true, hasTapAction: true));
    handle.dispose();
  });
}

// ---------- Testing Lead: helpers ----------

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _keptUrl = 'http://localhost:3000/#/passport/kept';
StoredQrCode _kept([DateTime? at]) =>
    StoredQrCode(url: _keptUrl, createdAt: at ?? _created);

/// A service whose answers a test can hold back (a [Completer]) or change.
class _Scripted extends PassportService {
  _Scripted({PassportView? view, this.loadError})
      : view = view ?? _view(),
        super(headers: () async => {}, refresh: () async => null);

  PassportView view;
  PassportError? loadError;
  Completer<PassportView>? loadGate;
  Completer<NewQrCode>? makeGate;
  Completer<void>? turnOffGate;
  PassportError? turnOffError;
  int loads = 0;
  int made = 0;
  int turnedOff = 0;

  @override
  Future<void> turnOffCode() {
    turnedOff++;
    if (turnOffGate != null) return turnOffGate!.future;
    if (turnOffError != null) {
      return Future.error(PassportException(turnOffError!));
    }
    view = _view(withCode: false);
    return Future.value();
  }

  @override
  Future<PassportView> getPassport() async {
    loads++;
    if (loadGate != null) return loadGate!.future;
    if (loadError != null) throw PassportException(loadError!);
    return view;
  }

  @override
  Future<NewQrCode> makeNewCode() {
    made++;
    if (makeGate != null) return makeGate!.future;
    return Future.value(NewQrCode(
      token: 'n$made',
      url: 'http://localhost:3000/#/passport/n$made',
      createdAt: DateTime.utc(2026, 10, 16, 9),
    ));
  }
}

/// Every state the page can show once loaded.
Map<String, (_Scripted, _MemoryStore)> _states() => {
      'no code yet': (_Scripted(view: _view(withCode: false)), _MemoryStore()),
      'QR shown': (
        _Scripted(view: _view(lastScanned: DateTime.utc(2026, 10, 17, 12))),
        _MemoryStore(_kept())
      ),
      'not on this device': (_Scripted(), _MemoryStore()),
      "couldn't load": (
        _Scripted(loadError: PassportError.network),
        _MemoryStore()
      ),
      'something went wrong': (
        _Scripted(loadError: PassportError.server),
        _MemoryStore()
      ),
      'signed out': (
        _Scripted(loadError: PassportError.signedOut),
        _MemoryStore()
      ),
      'only for patients': (
        _Scripted(loadError: PassportError.notPatient),
        _MemoryStore()
      ),
    };

Future<void> _openThemed(
    WidgetTester t, _Scripted service, _MemoryStore store,
    {ThemeData? theme}) async {
  await t.binding.setSurfaceSize(const Size(420, 2000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(
    theme: theme,
    home: EmergencyQrPage(
      key: UniqueKey(),
      service: service,
      store: store,
      makeImage: (_) async => Uint8List(0),
      saveImage: (_, __) async => true,
    ),
  ));
  await t.pumpAndSettle();
}

Finder _button(String label) => find.ancestor(
    of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());

bool _enabled(WidgetTester t, String label) =>
    t.widget<ButtonStyleButton>(_button(label)).enabled;

/// True when the QR the page paints holds [data]: its painter's picture is
/// sampled at every module of the code for [data] (QrImageView's defaults:
/// error correction L, gapless).
Future<bool> _qrHolds(WidgetTester t, String data) async {
  final painter = t
      .widget<CustomPaint>(find.descendant(
          of: find.byType(QrImageView), matching: find.byType(CustomPaint)))
      .painter! as QrPainter;
  final qr = QrImage(
      QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.L));
  final n = qr.moduleCount;
  final size = n * 10.0;
  final bytes = (await t.runAsync(
      () => painter.toImageData(size, format: ImageByteFormat.rawRgba)))!;
  final px = ((size / n) * 2).roundToDouble() / 2;
  final inset = (size - px * n) / 2;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      final x = (inset + (c + 0.5) * px).floor();
      final y = (inset + (r + 0.5) * px).floor();
      final alpha = bytes.getUint8((y * size.toInt() + x) * 4 + 3);
      if ((alpha > 128) != qr.isDark(r, c)) return false;
    }
  }
  return true;
}
