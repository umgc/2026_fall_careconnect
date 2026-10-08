import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/config/theme/app_theme.dart';
import 'package:care_connect_app/features/health/health_data/pages/medicare_connect_page.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_connect_service.dart';
import 'package:care_connect_app/features/health/health_data/widgets/medicare_connect_tile.dart';

import 'health_data_test_support.dart';

class _FakeService extends MedicareConnectService {
  _FakeService({
    this.statusResult,
    this.connectError,
    this.connectThrows,
    this.disconnectOk = true,
    this.statusGate,
  });

  MedicareStatus? statusResult;
  MedicareConnectError? connectError;
  Object? connectThrows;
  bool disconnectOk;
  Completer<void>? statusGate;
  Completer<void>? connectGate;
  int connectCalls = 0;
  int disconnectCalls = 0;
  int statusCalls = 0;

  @override
  Future<MedicareStatus?> status() async {
    statusCalls++;
    if (statusGate != null) await statusGate!.future;
    return statusResult;
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    if (connectGate != null) await connectGate!.future;
    if (connectThrows != null) throw connectThrows!;
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
    test('TC-MCR-CONN-001: maps every backend value', () {
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
    test('TC-MCR-CONN-002: ignores unknown or missing values', () {
      expect(MedicareConnectResult.parse('weird'), isNull);
      expect(MedicareConnectResult.parse(null), isNull);
    });
  });

  test('TC-MCR-CONN-003: status accepts either connected:true or status:LINKED',
      () {
    expect(MedicareStatus.fromJson({'connected': true}).connected, isTrue);
    expect(MedicareStatus.fromJson({'status': 'LINKED'}).connected, isTrue);
    expect(MedicareStatus.fromJson({'status': 'UNLINKED'}).connected, isFalse);
  });

  testWidgets('TC-MCR-CONN-004: shows a message for the return result',
      (t) async {
    await t.pumpWidget(_app(
        _FakeService(statusResult: const MedicareStatus(connected: true)),
        result: MedicareConnectResult.linkExpired));
    await t.pumpAndSettle();
    expect(find.textContaining('timed out'), findsOneWidget);
    expect(find.textContaining('Connected'), findsOneWidget);
  });

  testWidgets(
      'TC-MCR-CONN-005: failed status check says so instead of "Not connected"',
      (t) async {
    await t.pumpWidget(_app(_FakeService(statusResult: null)));
    await t.pumpAndSettle();
    expect(find.text('Couldn\'t check the connection'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('TC-MCR-CONN-006: connect error shows a plain-language message',
      (t) async {
    final s = _FakeService(
        statusResult: const MedicareStatus(connected: false),
        connectError: MedicareConnectError.signedOut);
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Connect Medicare Account'));
    await t.pumpAndSettle();
    expect(s.connectCalls, 1);
    expect(find.textContaining('sign-in has expired'), findsOneWidget);
  });

  testWidgets('TC-MCR-CONN-007: disconnect asks first and does nothing if kept',
      (t) async {
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

  // ---- Testing Lead cases (PR #263 review, 2026-10-05) ----

  testWidgets(
      'TC-MCR-CONN-008: every return result has its own announced message, '
      'and dismissing it removes it', (t) async {
    final expected = <MedicareConnectResult, String>{
      MedicareConnectResult.connected: 'Medicare account connected',
      MedicareConnectResult.cancelled: 'didn\'t finish connecting',
      MedicareConnectResult.failed: 'couldn\'t connect to Medicare',
      MedicareConnectResult.linkExpired: 'timed out',
      MedicareConnectResult.alreadyLinked: 'different CareConnect account',
    };
    for (final entry in expected.entries) {
      await t.pumpWidget(_app(
          _FakeService(statusResult: const MedicareStatus(connected: false)),
          result: entry.key));
      await t.pumpAndSettle();
      final text = find.textContaining(entry.value);
      expect(text, findsOneWidget, reason: '${entry.key}');
      // The banner is a live region so a screen reader announces the result.
      final live = find.ancestor(
          of: text,
          matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true));
      expect(live, findsOneWidget, reason: '${entry.key}');
      await t.tap(find.byTooltip('Dismiss message'));
      await t.pumpAndSettle();
      expect(text, findsNothing, reason: '${entry.key}');
      // Fresh tree for the next result.
      await t.pumpWidget(const SizedBox());
    }
    await t.pumpWidget(_app(
        _FakeService(statusResult: const MedicareStatus(connected: false))));
    await t.pumpAndSettle();
    expect(find.byTooltip('Dismiss message'), findsNothing);
  });

  testWidgets(
      'TC-MCR-CONN-009: every connect error, and an unexpected exception, '
      'shows a message and leaves the account Not connected', (t) async {
    final expected = <MedicareConnectError, String>{
      MedicareConnectError.network: 'couldn\'t reach CareConnect',
      MedicareConnectError.notPatient: 'Only the patient can connect',
      MedicareConnectError.server: 'couldn\'t start the Medicare connection',
      MedicareConnectError.launch: 'couldn\'t open the Medicare sign-in page',
    };
    for (final entry in expected.entries) {
      final s = _FakeService(
          statusResult: const MedicareStatus(connected: false),
          connectError: entry.key);
      await t.pumpWidget(_app(s));
      await t.pumpAndSettle();
      await t.tap(find.text('Connect Medicare Account'));
      await t.pumpAndSettle();
      expect(find.textContaining(entry.value), findsOneWidget,
          reason: '${entry.key}');
      expect(find.text('Not connected'), findsOneWidget);
      expect(find.text('Connect Medicare Account'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    }
    final s = _FakeService(
        statusResult: const MedicareStatus(connected: false),
        connectThrows: StateError('boom'));
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Connect Medicare Account'));
    await t.pumpAndSettle();
    expect(find.textContaining('couldn\'t start the Medicare connection'),
        findsOneWidget);
  });

  testWidgets(
      'TC-MCR-CONN-010: a loading indicator shows while the status check and '
      'the connect request are pending, and Connect cannot be pressed twice',
      (t) async {
    final s = _FakeService(
        statusResult: const MedicareStatus(connected: false),
        statusGate: Completer<void>());
    await t.pumpWidget(_app(s));
    await t.pump();
    expect(find.text('Checking…'), findsOneWidget);
    expect(find.bySemanticsLabel('Please wait'), findsOneWidget);
    expect(find.text('Connect Medicare Account'), findsNothing);
    s.statusGate!.complete();
    await t.pumpAndSettle();

    s.connectGate = Completer<void>();
    await t.tap(find.text('Connect Medicare Account'));
    await t.pump();
    expect(find.bySemanticsLabel('Please wait'), findsOneWidget);
    expect(find.text('Connect Medicare Account'), findsNothing);
    expect(s.connectCalls, 1);
    s.connectGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Connect Medicare Account'), findsOneWidget);
    expect(s.connectCalls, 1);
  });

  testWidgets(
      'TC-MCR-CONN-011: a failed disconnect keeps the account Connected and '
      'says so', (t) async {
    final s = _FakeService(
        statusResult: const MedicareStatus(connected: true),
        disconnectOk: false);
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    await t.tap(find.text('Disconnect'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Disconnect').last);
    await t.pumpAndSettle();
    expect(s.disconnectCalls, 1);
    expect(find.textContaining('couldn\'t disconnect Medicare'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets(
      'TC-MCR-CONN-012: Try again re-checks the status and shows the result',
      (t) async {
    final s = _FakeService(statusResult: null);
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    expect(s.statusCalls, 1);
    s.statusResult = MedicareStatus(
        connected: true, connectedAt: DateTime(2026, 9, 30, 12));
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(s.statusCalls, 2);
    expect(find.text('Connected since Sep 30, 2026'), findsOneWidget);
    expect(find.text('Disconnect'), findsOneWidget);
  });

  testWidgets(
      'TC-MCR-CONN-013: a new return result on the same page replaces the '
      'message', (t) async {
    final s = _FakeService(statusResult: const MedicareStatus(connected: false));
    await t.pumpWidget(_app(s, result: MedicareConnectResult.cancelled));
    await t.pumpAndSettle();
    expect(find.textContaining('didn\'t finish connecting'), findsOneWidget);
    await t.pumpWidget(_app(s, result: MedicareConnectResult.failed));
    await t.pumpAndSettle();
    expect(find.textContaining('didn\'t finish connecting'), findsNothing);
    expect(find.textContaining('couldn\'t connect to Medicare'), findsOneWidget);
  });

  // ---- SRS 1.4 text (DEF-MCR-08) ----

  testWidgets(
      'TC-MCR-CONN-021: the connected result shows the SRS confirmation text '
      '"Medicare account connected" (FR-MCR-04, AC-MCR-04-1)', (t) async {
    await t.pumpWidget(_app(
        _FakeService(statusResult: const MedicareStatus(connected: true)),
        result: MedicareConnectResult.connected));
    await t.pumpAndSettle();
    expect(find.textContaining('Medicare account connected'), findsOneWidget);
  });

  testWidgets(
      'TC-MCR-CONN-022: with no network the tile shows ERR-MCR-04 and stays '
      'Not connected (FR-MCR-26, AC-MCR-26-1)', (t) async {
    final s = _FakeService(
        statusResult: const MedicareStatus(connected: false),
        connectError: MedicareConnectError.offline);
    await t.pumpWidget(_app(s));
    await t.pumpAndSettle();
    await t.tap(find.byType(ElevatedButton));
    await t.pumpAndSettle();
    expect(
        find.text(
            'You need an internet connection to connect your Medicare account.'),
        findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
  });

  testWidgets(
      'TC-MCR-CONN-023: the connect control is named "Connect Medicare '
      'Account", before and after a cancelled attempt (AC-MCR-01-1, '
      'AC-MCR-05-1)', (t) async {
    await t.pumpWidget(_app(
        _FakeService(statusResult: const MedicareStatus(connected: false)),
        result: MedicareConnectResult.cancelled));
    await t.pumpAndSettle();
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Connect Medicare Account'),
        findsOneWidget);
  });

  for (final theme in {
    'light': AppTheme.lightTheme,
    'dark': AppTheme.darkTheme,
  }.entries) {
    testWidgets('TC-MCR-CONN-035: every text on the Connect Medicare page has '
        'at least 4.5:1 contrast, in the app\'s ${theme.key} theme (WCAG 2.1 '
        'SC 1.4.3)', (t) async {
      final previous = MedicareConnectService.instance;
      MedicareConnectService.instance =
          _FakeService(statusResult: const MedicareStatus(connected: false));
      addTearDown(() => MedicareConnectService.instance = previous);
      await t.pumpWidget(MaterialApp(
          theme: theme.value,
          home: const MedicareConnectPage(
              result: MedicareConnectResult.cancelled)));
      await t.pumpAndSettle();
      final low = lowContrastText(t, find.byType(Scaffold)).toSet();
      expect(low, isEmpty, reason: low.join('\n'));
    });
  }
}
