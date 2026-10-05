import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/health_data/services/medicare_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/medicare_connect_tile.dart';

class _FakeService extends MedicareConnectService {
  _FakeService({this.statusResult, this.connectError, this.disconnectOk = true});

  MedicareStatus? statusResult;
  MedicareConnectError? connectError;
  bool disconnectOk;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<MedicareStatus?> status() async => statusResult;

  @override
  Future<void> connect() async {
    connectCalls++;
    if (connectError != null) throw MedicareConnectException(connectError!);
  }

  @override
  Future<bool> disconnect() async {
    disconnectCalls++;
    return disconnectOk;
  }
}

Widget _app(_FakeService s, {MedicareConnectResult? result}) => MaterialApp(
      home: Scaffold(body: MedicareConnectTile(service: s, result: result)),
    );

void main() {
  group('MedicareConnectResult.parse', () {
    test('maps every backend value', () {
      expect(MedicareConnectResult.parse('connected'),
          MedicareConnectResult.connected);
      expect(MedicareConnectResult.parse('cancelled'),
          MedicareConnectResult.cancelled);
      expect(MedicareConnectResult.parse('failed'), MedicareConnectResult.failed);
      expect(MedicareConnectResult.parse('link_expired'),
          MedicareConnectResult.linkExpired);
      expect(MedicareConnectResult.parse('already_linked'),
          MedicareConnectResult.alreadyLinked);
    });
    test('ignores unknown or missing values', () {
      expect(MedicareConnectResult.parse('weird'), isNull);
      expect(MedicareConnectResult.parse(null), isNull);
    });
  });

  test('status accepts either connected:true or status:LINKED', () {
    expect(MedicareStatus.fromJson({'connected': true}).connected, isTrue);
    expect(MedicareStatus.fromJson({'status': 'LINKED'}).connected, isTrue);
    expect(MedicareStatus.fromJson({'status': 'UNLINKED'}).connected, isFalse);
  });

  testWidgets('shows a message for the return result', (t) async {
    await t.pumpWidget(_app(
        _FakeService(statusResult: const MedicareStatus(connected: true)),
        result: MedicareConnectResult.linkExpired));
    await t.pumpAndSettle();
    expect(find.textContaining('timed out'), findsOneWidget);
    expect(find.textContaining('Connected'), findsOneWidget);
  });

  testWidgets('failed status check says so instead of "Not connected"',
      (t) async {
    await t.pumpWidget(_app(_FakeService(statusResult: null)));
    await t.pumpAndSettle();
    expect(find.text('Couldn\'t check the connection'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('connect error shows a plain-language message', (t) async {
    final s = _FakeService(
        statusResult: const MedicareStatus(connected: false),
        connectError: MedicareConnectError.signedOut);
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(s.connectCalls, 1);
    expect(find.textContaining('sign-in has expired'), findsOneWidget);
  });

  testWidgets('disconnect asks first and does nothing if kept', (t) async {
    final s = _FakeService(statusResult: const MedicareStatus(connected: true));
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();

    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    expect(find.text('Disconnect Medicare?'), findsOneWidget);
    await t.tap(find.text('Keep connected'));
    await t.pumpAndSettle();
    expect(s.disconnectCalls, 0);

    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Disconnect').last);
    await t.pumpAndSettle();
    expect(s.disconnectCalls, 1);
    expect(find.text('Not connected'), findsOneWidget);
  });
}
