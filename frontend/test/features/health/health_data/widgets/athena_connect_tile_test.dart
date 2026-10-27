// AthenaConnectTile with a fake AthenaConnectService: consent gating,
// link reasons, sync summary, refresh, disconnect, and staying hidden when
// athena is turned off or the user is not a patient.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';

import '../health_data_test_support.dart';

class _FakeService extends AthenaConnectService {
  _FakeService(this.statusResult, {this.connectResult, this.syncResult});

  AthenaStatus? statusResult;
  AthenaStatus? connectResult;
  AthenaSyncResult? syncResult;
  Object? connectError;
  bool disconnectResult = true;
  int connects = 0;
  int disconnects = 0;

  @override
  Future<AthenaStatus?> status() async => statusResult;

  @override
  Future<AthenaStatus> connect() async {
    connects++;
    if (connectError != null) throw connectError!;
    return connectResult!;
  }

  @override
  Future<AthenaSyncResult> sync() async => syncResult!;

  @override
  Future<bool> disconnect() async {
    disconnects++;
    return disconnectResult;
  }
}

const _notConnected = AthenaStatus(
    connected: false, reason: AthenaNotConnectedReason.notConsented);

final _sync = AthenaSyncResult(
  completed: true,
  syncedAt: DateTime(2026, 10, 14),
  types: const [
    AthenaTypeResult(
        resourceType: 'Condition', outcome: AthenaTypeOutcome.stored, count: 3),
    AthenaTypeResult(
        resourceType: 'Coverage', outcome: AthenaTypeOutcome.notGranted),
  ],
);

Future<void> _pump(WidgetTester t, _FakeService s) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: AthenaConnectTile(service: s)),
    ),
  ));
  await t.pumpAndSettle();
}

Finder _connectButton() =>
    find.widgetWithText(ElevatedButton, 'Connect athenahealth');

void main() {
  testWidgets('shows the consent text and keeps Connect off until the '
      'patient agrees', (t) async {
    final s = _FakeService(_notConnected,
        connectResult: AthenaStatus(connected: true, sync: _sync));
    await _pump(t, s);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
    expect(t.widget<ElevatedButton>(_connectButton()).onPressed, isNull);

    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(_connectButton());
    await t.pumpAndSettle();

    expect(s.connects, 1);
    // Connecting never announces athenahealth as connected.
    expect(find.textContaining('Connected'), findsNothing);
    expect(find.textContaining('athenahealth connected'), findsNothing);
    expect(find.textContaining('3 records are now in Health Data'),
        findsOneWidget);
    expect(find.textContaining('doesn\'t share insurance'), findsOneWidget);
    expect(find.text('Refresh records'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets('a chart that cannot be linked says what to fix', (t) async {
    final s = _FakeService(_notConnected,
        connectResult: const AthenaStatus(
            connected: false,
            reason: AthenaNotConnectedReason.incompleteProfile));
    await _pump(t, s);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(_connectButton());
    await t.pumpAndSettle();
    expect(find.textContaining('first name, last name and date of birth'),
        findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('a sync already running is reported, not shown as a failure',
      (t) async {
    final s = _FakeService(_notConnected)
      ..connectError =
          const AthenaConnectException(AthenaConnectError.syncInProgress);
    await _pump(t, s);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(_connectButton());
    await t.pumpAndSettle();
    expect(find.textContaining('already being updated'), findsOneWidget);
  });

  testWidgets('connected: refresh summarizes the sync and disconnect asks '
      'first', (t) async {
    final s = _FakeService(const AthenaStatus(connected: true),
        syncResult: _sync);
    await _pump(t, s);
    expect(find.textContaining('Connected'), findsNothing);
    expect(find.text(AthenaConnectTile.consentText), findsNothing);

    await t.tap(find.text('Refresh records'));
    await t.pumpAndSettle();
    expect(find.textContaining('3 records are now in Health Data'),
        findsOneWidget);

    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    expect(find.text('Disconnect athenahealth?'), findsOneWidget);
    expect(find.text(AthenaConnectTile.disconnectText), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Disconnect').last);
    await t.pumpAndSettle();
    expect(s.disconnects, 1);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.textContaining('athenahealth is disconnected'), findsOneWidget);
  });

  testWidgets('Keep connected cancels the disconnect: nothing is deleted',
      (t) async {
    final s = _FakeService(const AthenaStatus(connected: true));
    await _pump(t, s);
    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep connected'));
    await t.pumpAndSettle();
    expect(s.disconnects, 0);
    expect(find.text('Refresh records'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('a disconnect the backend does not confirm says so and stays '
      'connected', (t) async {
    final s = _FakeService(const AthenaStatus(connected: true))
      ..disconnectResult = false;
    await _pump(t, s);
    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Disconnect').last);
    await t.pumpAndSettle();
    expect(s.disconnects, 1);
    expect(find.text('We couldn\'t disconnect athenahealth. Please try again.'),
        findsOneWidget);
    expect(find.text('Refresh records'), findsOneWidget);
  });

  testWidgets('with athena turned off it still offers Connect, which says '
      'athenahealth isn\'t available (as Epic\'s tile does)', (t) async {
    final s = _FakeService(AthenaStatus.unavailable)
      ..connectError =
          const AthenaConnectException(AthenaConnectError.disabled);
    await _pump(t, s);
    expect(find.text('Not connected'), findsOneWidget);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(_connectButton());
    await t.pumpAndSettle();
    expect(s.connects, 1);
    expect(find.textContaining('athenahealth isn\'t available right now'),
        findsOneWidget);
  });

  testWidgets('hidden when the user is not a patient', (t) async {
    await _pump(t, _FakeService(AthenaStatus.notPatient));
    expect(find.textContaining('athenahealth'), findsNothing);
  });

  // R381-D01: with athena turned off the server answers 500, so the status
  // can't be read. That used to show "Couldn't check the connection" with a
  // Try again that looped.
  testWidgets('a status that cannot be read shows Not connected and the '
      'consent, not a Try again that loops', (t) async {
    final s = _FakeService(null)
      ..connectError =
          const AthenaConnectException(AthenaConnectError.server);
    await _pump(t, s);
    expect(find.text('Couldn\'t check the connection'), findsNothing);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(_connectButton());
    await t.pumpAndSettle();
    expect(s.connects, 1);
    expect(find.textContaining('We couldn\'t complete that'), findsOneWidget);
  });

  testWidgets('every text meets 4.5:1 contrast, before and after a link '
      'problem (NFR-ACC-07)', (t) async {
    final s = _FakeService(_notConnected,
        connectResult: const AthenaStatus(
            connected: false, reason: AthenaNotConnectedReason.notMatched));
    await _pump(t, s);
    expect(lowContrastText(t, find.byType(AthenaConnectTile)), isEmpty);
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(_connectButton());
    await t.pumpAndSettle();
    final low = lowContrastText(t, find.byType(AthenaConnectTile)).toSet();
    expect(low, isEmpty, reason: low.join('\n'));
  });

  // ---- Settings (compact): laid out like EpicConnectTile ----

  Future<void> pumpCompact(WidgetTester t, _FakeService s) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          AthenaConnectTile(service: s, compact: true),
        ]),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('Settings: one card row like Epic\'s, with Connect and no '
      'inline consent', (t) async {
    await pumpCompact(t, _FakeService(_notConnected));
    final tile = find.descendant(
        of: find.byType(Card), matching: find.byType(ListTile));
    expect(tile, findsOneWidget);
    expect(find.descendant(of: tile, matching: find.text('athenahealth')),
        findsOneWidget);
    expect(find.text('Connect to import your clinical records'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(find.text(AthenaConnectTile.consentText), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('Settings: Connect asks for consent first; Cancel connects '
      'nothing', (t) async {
    final s = _FakeService(_notConnected,
        connectResult: AthenaStatus(connected: true, sync: _sync));
    await pumpCompact(t, s);
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await t.pumpAndSettle();
    expect(find.text(AthenaConnectTile.consentText), findsOneWidget);
    final dialogConnect = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect'));
    expect(t.widget<FilledButton>(dialogConnect).onPressed, isNull);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(s.connects, 0);
    expect(find.text('Connect to import your clinical records'), findsOneWidget);
  });

  testWidgets('Settings: agreeing connects, the result shows in a snackbar, '
      'and the row then offers Disconnect', (t) async {
    final s = _FakeService(_notConnected,
        connectResult: AthenaStatus(connected: true, sync: _sync));
    await pumpCompact(t, s);
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect')));
    await t.pumpAndSettle();

    expect(s.connects, 1);
    // Same snackbar and connected line as EpicConnectTile.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('athenahealth connected.'), findsOneWidget);
    expect(find.text('Connected — your records show in Health Data'),
        findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Disconnect'), findsOneWidget);
  });

  testWidgets('Settings: a chart that can\'t be linked says why in a '
      'snackbar and stays not connected', (t) async {
    final s = _FakeService(_notConnected,
        connectResult: const AthenaStatus(
            connected: false,
            reason: AthenaNotConnectedReason.incompleteProfile));
    await pumpCompact(t, s);
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect')));
    await t.pumpAndSettle();
    expect(find.textContaining('first name, last name and date of birth'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('Settings: Disconnect still confirms first, since it deletes '
      'the imported records', (t) async {
    final s = _FakeService(const AthenaStatus(connected: true));
    await pumpCompact(t, s);
    await t.tap(find.widgetWithText(TextButton, 'Disconnect'));
    await t.pumpAndSettle();
    expect(find.text('Disconnect athenahealth?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Disconnect').last);
    await t.pumpAndSettle();
    expect(s.disconnects, 1);
    expect(find.text('Disconnected from athenahealth.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('Settings: with athena turned off the row still shows, like '
      'Epic\'s, and Connect says it isn\'t available', (t) async {
    final s = _FakeService(AthenaStatus.unavailable)
      ..connectError =
          const AthenaConnectException(AthenaConnectError.disabled);
    await pumpCompact(t, s);
    expect(find.text('athenahealth'), findsOneWidget);
    expect(find.text('Connect to import your clinical records'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect')));
    await t.pumpAndSettle();
    expect(find.textContaining('athenahealth isn\'t available right now'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('Settings: hidden when the user isn\'t a patient', (t) async {
    await pumpCompact(t, _FakeService(AthenaStatus.notPatient));
    expect(find.text('athenahealth'), findsNothing);
  });

  testWidgets('Settings: reads like the Epic row in every state', (t) async {
    await pumpCompact(t, _FakeService(_notConnected));
    expect(find.text('Connect to import your clinical records'), findsOneWidget);
    // A status that can't be checked reads as not connected, as Epic's does.
    await t.pumpWidget(const SizedBox());
    await pumpCompact(t, _FakeService(null));
    expect(find.text('Connect to import your clinical records'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    await t.pumpWidget(const SizedBox());
    await pumpCompact(t, _FakeService(const AthenaStatus(connected: true)));
    expect(find.text('Connected — your records show in Health Data'),
        findsOneWidget);
  });
}
