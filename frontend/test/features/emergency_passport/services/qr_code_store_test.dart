// CC-12 Increment 2: keeping the QR code on the device. Test Plan §3.27:
// TC-EMG-272…275 and 462, 463 (the pull request's), 299…301 (Testing Lead:
// the signed-in patient's id, what is stored, and sign-out), 484, 485 (#365's
// clearAll), 486…488 (Testing Lead: sign-out when the server fails, and
// DEF-EMG-29: a session that ends without a sign-out), 492, 493 (Testing Lead:
// a session that is still valid keeps the code).

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/emergency_passport/services/qr_code_store.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/auth_service.dart';
import 'package:care_connect_app/services/user_role_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final memory = <String, String>{};
  // Keys whose writes fail, as storage that is unavailable would (TC-EMG-488).
  final failWrites = <String>{};

  setUp(() {
    memory.clear();
    failWrites.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          if (failWrites.contains(key)) {
            throw PlatformException(code: 'unavailable');
          }
          memory[key!] = args['value'] as String;
          return null;
        case 'read':
          return memory[key];
        case 'delete':
          memory.remove(key);
          return null;
        case 'deleteAll':
          memory.clear();
          return null;
        case 'readAll':
          return Map<String, String>.of(memory);
        case 'containsKey':
          return memory.containsKey(key);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('TC-EMG-272: keeps one code per patient', () async {
    final a = QrCodeStore(patientId: () async => 1);
    final b = QrCodeStore(patientId: () async => 2);
    await a.save(StoredQrCode(
        url: 'http://x/#/passport/a', createdAt: DateTime.utc(2026, 10, 15)));
    final readA = await a.read();
    expect(readA!.url, 'http://x/#/passport/a');
    expect(readA.createdAt, DateTime.utc(2026, 10, 15));
    expect(await b.read(), isNull);
  });

  test('TC-EMG-273: no patient id: nothing is kept or read', () async {
    final s = QrCodeStore(patientId: () async => null);
    await s.save(StoredQrCode(url: 'u', createdAt: DateTime.utc(2026)));
    expect(memory, isEmpty);
    expect(await s.read(), isNull);
  });

  test('TC-EMG-274: a damaged or incomplete entry reads as nothing kept',
      () async {
    final s = QrCodeStore(patientId: () async => 3);
    memory['cc12_emergency_qr_3'] = 'not json';
    expect(await s.read(), isNull);
    memory['cc12_emergency_qr_3'] = '{"url":"","createdAt":"2026-10-15T00:00:00Z"}';
    expect(await s.read(), isNull);
    memory['cc12_emergency_qr_3'] = '{"url":"u","createdAt":"not a date"}';
    expect(await s.read(), isNull);
  });

  test('TC-EMG-275: storage that fails to write does not break the screen',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    final s = QrCodeStore(patientId: () async => 4);
    await s.save(StoredQrCode(url: 'u', createdAt: DateTime.utc(2026)));
    expect(await s.read(), isNull);
  });

  // ---------- Testing Lead ----------

  test(
      'TC-EMG-299: by default the store keys on the signed-in patient\'s id, '
      'so a caregiver or another patient on the same device reads nothing',
      () async {
    SharedPreferences.setMockInitialValues({});
    await UserRoleStorageService.instance.clearUserData();
    await UserRoleStorageService.instance
        .setUserData(role: 'PATIENT', userId: 70, patientId: 7);
    addTearDown(UserRoleStorageService.instance.clearUserData);

    await QrCodeStore().save(StoredQrCode(
        url: 'http://x/#/passport/seven', createdAt: DateTime.utc(2026, 10, 16)));
    expect(memory.keys, ['cc12_emergency_qr_7']);
    expect((await QrCodeStore().read())!.url, 'http://x/#/passport/seven');

    await UserRoleStorageService.instance
        .setUserData(role: 'PATIENT', userId: 80, patientId: 8);
    expect(await QrCodeStore().read(), isNull);

    await UserRoleStorageService.instance.clearUserData();
    await UserRoleStorageService.instance
        .setUserData(role: 'CAREGIVER', userId: 90, caregiverId: 9);
    expect(await QrCodeStore().read(), isNull);
  });

  test(
      'TC-EMG-300: what is kept is only the link and its creation time, in '
      'UTC to the microsecond, whatever time zone the date came in', () async {
    final s = QrCodeStore(patientId: () async => 5);
    final created = DateTime.utc(2026, 10, 15, 17, 11, 34, 932, 728);
    await s.save(StoredQrCode(
        url: 'http://x/#/passport/five', createdAt: created.toLocal()));
    final stored = jsonDecode(memory['cc12_emergency_qr_5']!) as Map;
    expect(stored, {
      'url': 'http://x/#/passport/five',
      'createdAt': '2026-10-15T17:11:34.932728Z',
    });
    final read = await s.read();
    expect(read!.createdAt, created);
    expect(read.createdAt.isUtc, isTrue);
  });

  for (final signOut in <String, Future<void> Function()>{
    'AuthService.logout': () => http.runWithClient(AuthService.logout,
        () => MockClient((_) async => http.Response('{}', 200))),
    "UserProvider.clearUser (the drawer's Logout)": () =>
        UserProvider().clearUser(),
  }.entries) {
    test(
        'TC-EMG-301: signing out (${signOut.key}) removes every QR code kept on '
        'the device (DEF-EMG-11: the code is the only credential for the '
        'passport)', () async {
      SharedPreferences.setMockInitialValues({});
      // UserProvider checks the connection when it is made.
      const connectivity =
          MethodChannel('dev.fluttercommunity.plus/connectivity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(connectivity,
              (call) async => call.method == 'check' ? ['wifi'] : null);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(connectivity, null));
      // ...and listens for connection changes; without a stream handler that
      // listen fails after the test ends and is reported against a later test.
      const connectivityStatus =
          EventChannel('dev.fluttercommunity.plus/connectivity_status');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(connectivityStatus,
              MockStreamHandler.inline(onListen: (_, __) {}));
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockStreamHandler(connectivityStatus, null));
      await UserRoleStorageService.instance
          .setUserData(role: 'PATIENT', userId: 70, patientId: 7);
      await QrCodeStore().save(StoredQrCode(
          url: 'http://x/#/passport/seven',
          createdAt: DateTime.utc(2026, 10, 16)));
      // Another patient's code left on this shared device, and a key that
      // isn't a QR code.
      await QrCodeStore(patientId: () async => 8).save(StoredQrCode(
          url: 'http://x/#/passport/eight',
          createdAt: DateTime.utc(2026, 10, 16)));
      memory['other_key'] = 'kept';
      memory['jwt_token'] = 'synthetic.jwt.value';
      expect(memory.keys,
          containsAll(['cc12_emergency_qr_7', 'cc12_emergency_qr_8']));

      await signOut.value();

      expect(memory.containsKey('jwt_token'), isFalse,
          reason: 'sign-out ran: the session token is gone');
      expect(memory.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
          isEmpty);
      expect(memory['other_key'], 'kept');
    });
  }

  // Shared set-up for a code kept for patient 7 while signed in.
  Future<void> keepSevensCode() async {
    SharedPreferences.setMockInitialValues({});
    await UserRoleStorageService.instance
        .setUserData(role: 'PATIENT', userId: 70, patientId: 7);
    await QrCodeStore().save(StoredQrCode(
        url: 'http://x/#/passport/seven',
        createdAt: DateTime.utc(2026, 10, 16)));
    memory['jwt_token'] = 'synthetic.jwt.value';
  }

  // A session that is still valid: its expiry an hour away, and the user it
  // belongs to (synthetic).
  void keepValidSession() {
    memory['token_expiry'] =
        '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}';
    memory['user_session'] = jsonEncode({
      'id': 70,
      'email': 'patient70@example.test',
      'role': 'PATIENT',
      'token': 'synthetic.jwt.value',
      'patientId': 7,
      'name': 'Synthetic Patient',
    });
  }

  // UserProvider checks the connection when it is made, and listens for
  // changes (see TC-EMG-301).
  void fakeConnectivity() {
    const connectivity =
        MethodChannel('dev.fluttercommunity.plus/connectivity');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivity,
            (call) async => call.method == 'check' ? ['wifi'] : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivity, null));
    const connectivityStatus =
        EventChannel('dev.fluttercommunity.plus/connectivity_status');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(connectivityStatus,
            MockStreamHandler.inline(onListen: (_, __) {}));
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockStreamHandler(connectivityStatus, null));
  }

  test(
      'TC-EMG-486: signing out while the server is unreachable still removes '
      'the kept QR code (the error still reaches the caller)', () async {
    await keepSevensCode();

    await expectLater(
        http.runWithClient(
            AuthService.logout,
            () => MockClient(
                (_) async => throw http.ClientException('unreachable'))),
        throwsA(isA<http.ClientException>()));

    expect(memory.containsKey('jwt_token'), isFalse);
    expect(memory.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
        isEmpty);
  });

  test(
      'TC-EMG-487: signing out when the server answers 500 still removes the '
      'kept QR code', () async {
    await keepSevensCode();

    await http.runWithClient(AuthService.logout,
        () => MockClient((_) async => http.Response('{}', 500)));

    expect(memory.containsKey('jwt_token'), isFalse);
    expect(memory.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
        isEmpty);
  });

  for (final sessionEnd in <String, Future<void> Function()>{
    'the app starts with an expired session (UserProvider.initializeUser)':
        () async {
      // Expired an hour ago, so restoring the session clears it.
      memory['token_expiry'] =
          '${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600}';
      await UserProvider().initializeUser();
    },
    'a token refresh is refused (AuthService.forceRefreshToken)': () async {
      // A token that is still valid, so the refresh is actually sent.
      memory['token_expiry'] =
          '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}';
      expect(
          await http.runWithClient(AuthService.forceRefreshToken,
              () => MockClient((_) async => http.Response('{}', 401))),
          isNull);
    },
    'a token refresh fails with an error (AuthService.forceRefreshToken)':
        () async {
      memory['token_expiry'] =
          '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}';
      expect(
          await http.runWithClient(
              AuthService.forceRefreshToken,
              () => MockClient(
                  (_) async => throw http.ClientException('unreachable'))),
          isNull);
    },
    'the app starts with a damaged stored session '
        '(UserProvider.initializeUser)': () async {
      // The token is valid but the stored user can't be read back.
      keepValidSession();
      memory['user_session'] = '{}';
      await UserProvider().initializeUser();
    },
    'the app starts after an hour without activity and the new activity '
        'time cannot be stored (UserProvider.initializeUser)': () async {
      keepValidSession();
      memory['last_activity'] =
          '${DateTime.now().millisecondsSinceEpoch ~/ 1000 - 7200}';
      failWrites.add('last_activity');
      await UserProvider().initializeUser();
    },
  }.entries) {
    test(
        'TC-EMG-488: when ${sessionEnd.key}, the session ends and the kept QR '
        'code goes with it (DEF-EMG-29)', () async {
      fakeConnectivity();
      await keepSevensCode();

      await sessionEnd.value();

      expect(memory.containsKey('jwt_token'), isFalse,
          reason: 'the session ended: the session token is gone');
      expect(memory.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
          isEmpty);
    });
  }

  test(
      'TC-EMG-492: the app starting with a valid session keeps the session '
      'and the kept QR code', () async {
    fakeConnectivity();
    await keepSevensCode();
    keepValidSession();

    await http.runWithClient(UserProvider().initializeUser,
        () => MockClient((_) async => http.Response('{}', 404)));

    expect(memory['jwt_token'], 'synthetic.jwt.value');
    expect(memory.keys, contains('cc12_emergency_qr_7'));
  });

  test('TC-EMG-493: a token refresh that succeeds keeps the kept QR code',
      () async {
    await keepSevensCode();
    keepValidSession();

    final refreshed = await http.runWithClient(
        AuthService.forceRefreshToken,
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'id': 70,
              'email': 'patient70@example.test',
              'role': 'PATIENT',
              'token': 'synthetic.jwt.refreshed',
              'patientId': 7,
            }),
            200)));

    expect(refreshed, isNotNull);
    expect(memory['jwt_token'], 'synthetic.jwt.refreshed');
    expect(memory.keys, contains('cc12_emergency_qr_7'));
  });

  test('TC-EMG-462: clear forgets only this patient\'s code', () async {
    final a = QrCodeStore(patientId: () async => 1);
    final b = QrCodeStore(patientId: () async => 2);
    await a.save(StoredQrCode(url: 'a', createdAt: DateTime.utc(2026)));
    await b.save(StoredQrCode(url: 'b', createdAt: DateTime.utc(2026)));
    await a.clear();
    expect(await a.read(), isNull);
    expect((await b.read())!.url, 'b');
  });

  test('TC-EMG-463: clear with no patient id or failing storage does not throw',
      () async {
    await QrCodeStore(patientId: () async => null).clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    await QrCodeStore(patientId: () async => 5).clear();
  });

  test(
      'TC-EMG-484: clearAll removes every kept QR code and leaves other keys '
      'alone', () async {
    await QrCodeStore(patientId: () async => 1)
        .save(StoredQrCode(url: 'a', createdAt: DateTime.utc(2026)));
    await QrCodeStore(patientId: () async => 2)
        .save(StoredQrCode(url: 'b', createdAt: DateTime.utc(2026)));
    memory['other_key'] = 'kept';

    await QrCodeStore.clearAll();

    expect(memory.keys.where((k) => k.startsWith('cc12_emergency_qr_')),
        isEmpty);
    expect(memory['other_key'], 'kept');
  });

  test('TC-EMG-485: clearAll with failing storage does not throw', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'unavailable');
    });
    await QrCodeStore.clearAll();
  });
}
