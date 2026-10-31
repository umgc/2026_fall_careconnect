// Additional AthenaConnectTile coverage: every not-connected reason message,
// sync failures and type lists, unexpected errors, the dismiss button, and
// the banner (buttonOnly) busy state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/health/health_data/services/athena_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/athena_connect_tile.dart';

class _FakeService extends AthenaConnectService {
  _FakeService(this.statusResult);

  AthenaStatus? statusResult;
  AthenaStatus? connectResult;
  Object? connectError;
  Completer<AthenaStatus>? connectGate;
  AthenaSyncResult? syncResult;
  Object? syncError;
  int connects = 0;

  @override
  Future<AthenaStatus?> status() async => statusResult;

  @override
  Future<AthenaStatus> connect() async {
    connects++;
    if (connectGate != null) return connectGate!.future;
    if (connectError != null) throw connectError!;
    return connectResult!;
  }

  @override
  Future<AthenaSyncResult> sync() async {
    if (syncError != null) throw syncError!;
    return syncResult!;
  }

  @override
  Future<bool> disconnect() async => true;
}

const _notConnected = AthenaStatus(
    connected: false, reason: AthenaNotConnectedReason.notConsented);

Future<void> _pump(WidgetTester t, _FakeService s,
    {bool buttonOnly = false}) async {
  t.view.physicalSize = const Size(1000, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
          child: AthenaConnectTile(service: s, buttonOnly: buttonOnly)),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _agreeAndConnect(WidgetTester t) async {
  await t.tap(find.byType(Checkbox));
  await t.pump();
  await t.tap(find.widgetWithText(ElevatedButton, 'Connect athenahealth'));
  await t.pumpAndSettle();
}

void main() {
  final reasonTexts = <AthenaNotConnectedReason, String>{
    AthenaNotConnectedReason.noPatientProfile: 'We need your patient profile',
    AthenaNotConnectedReason.incompleteProfile:
        'Your profile needs your first name',
    AthenaNotConnectedReason.notMatched: 'We couldn\'t find an athenahealth',
    AthenaNotConnectedReason.ambiguousMatch: 'More than one athenahealth chart',
    AthenaNotConnectedReason.linkConflict: 'already connected to a different',
    AthenaNotConnectedReason.sourceUnavailable:
        'We couldn\'t reach athenahealth',
    AthenaNotConnectedReason.notLinked: 'isn\'t linked yet',
    AthenaNotConnectedReason.notConsented: 'We couldn\'t connect athenahealth',
    AthenaNotConnectedReason.unknown: 'We couldn\'t connect athenahealth',
  };

  for (final entry in reasonTexts.entries) {
    testWidgets('connect result ${entry.key.name} explains what to do',
        (t) async {
      final s = _FakeService(_notConnected)
        ..connectResult = AthenaStatus(connected: false, reason: entry.key);
      await _pump(t, s);
      await _agreeAndConnect(t);
      expect(s.connects, 1);
      expect(find.textContaining(entry.value), findsOneWidget);
    });
  }

  testWidgets('a not-linked status shows its message on load and can be '
      'dismissed', (t) async {
    final s = _FakeService(const AthenaStatus(
        connected: false, reason: AthenaNotConnectedReason.notLinked));
    await _pump(t, s);
    expect(find.textContaining('isn\'t linked yet'), findsOneWidget);

    await t.tap(find.byTooltip('Dismiss message'));
    await t.pumpAndSettle();
    expect(find.textContaining('isn\'t linked yet'), findsNothing);
  });

  testWidgets('an unexpected connect error reads as a server problem',
      (t) async {
    final s = _FakeService(_notConnected)..connectError = StateError('boom');
    await _pump(t, s);
    await _agreeAndConnect(t);
    expect(find.textContaining('We couldn\'t complete that'), findsOneWidget);
  });

  testWidgets('refresh that finds athena disconnected flips to Not connected',
      (t) async {
    final s = _FakeService(const AthenaStatus(connected: true))
      ..syncError =
          const AthenaConnectException(AthenaConnectError.notConnected);
    await _pump(t, s);
    await t.tap(find.text('Refresh records'));
    await t.pumpAndSettle();
    expect(find.textContaining('isn\'t connected anymore'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets('refresh with an unexpected error reads as a server problem',
      (t) async {
    final s = _FakeService(const AthenaStatus(connected: true))
      ..syncError = Exception('nope');
    await _pump(t, s);
    await t.tap(find.text('Refresh records'));
    await t.pumpAndSettle();
    expect(find.textContaining('We couldn\'t complete that'), findsOneWidget);
  });

  testWidgets('refresh summary lists failed and unshared types', (t) async {
    final s = _FakeService(const AthenaStatus(connected: true))
      ..syncResult = AthenaSyncResult(
        completed: true,
        syncedAt: DateTime(2026, 10, 14),
        types: const [
          AthenaTypeResult(
              resourceType: 'Condition',
              outcome: AthenaTypeOutcome.stored,
              count: 1),
          AthenaTypeResult(
              resourceType: 'Device', outcome: AthenaTypeOutcome.failed),
          AthenaTypeResult(
              resourceType: 'Goal', outcome: AthenaTypeOutcome.unavailable),
          AthenaTypeResult(
              resourceType: 'Coverage', outcome: AthenaTypeOutcome.notGranted),
        ],
      );
    await _pump(t, s);
    await t.tap(find.text('Refresh records'));
    await t.pumpAndSettle();
    expect(find.textContaining('1 record is now in Health Data.'),
        findsOneWidget);
    expect(find.textContaining('We couldn\'t get devices and goals'),
        findsOneWidget);
    expect(find.textContaining('doesn\'t share insurance'), findsOneWidget);
  });

  testWidgets('banner button shows Please wait while connecting', (t) async {
    final gate = Completer<AthenaStatus>();
    final s = _FakeService(_notConnected)..connectGate = gate;
    await _pump(t, s, buttonOnly: true);

    await t.tap(find.widgetWithText(TextButton, 'Connect'));
    await t.pumpAndSettle();
    await t.tap(find.byType(Checkbox));
    await t.pump();
    await t.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));

    expect(find.bySemanticsLabel('Please wait'), findsOneWidget);

    gate.complete(const AthenaStatus(connected: true));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Connect'), findsNothing);
  });
}
