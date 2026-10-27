import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/services/oracle_health_service.dart';
import 'package:care_connect_app/widgets/oracle_health_connect_tile.dart';

class _FakeOracleHealthClient implements OracleHealthConnectionClient {
  OracleHealthConnectionStatus connection = const OracleHealthConnectionStatus(
    connected: false,
    source: 'ORACLE_HEALTH',
  );

  bool failStatus = false;
  bool failConnect = false;
  bool failDisconnect = false;

  Completer<void>? statusGate;
  Completer<void>? connectGate;

  int statusCalls = 0;
  int connectCalls = 0;
  int disconnectCalls = 0;

  @override
  Future<OracleHealthConnectionStatus> status() async {
    statusCalls++;

    if (statusGate != null) {
      await statusGate!.future;
    }

    if (failStatus) {
      throw Exception('Status unavailable');
    }

    return connection;
  }

  @override
  Future<void> connect() async {
    connectCalls++;

    if (connectGate != null) {
      await connectGate!.future;
    }

    if (failConnect) {
      throw Exception('Unable to connect');
    }
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;

    if (failDisconnect) {
      throw Exception('Unable to disconnect');
    }

    connection = const OracleHealthConnectionStatus(
      connected: false,
      source: 'ORACLE_HEALTH',
    );
  }
}

Widget _testApp(_FakeOracleHealthClient client) {
  return MaterialApp(
    home: Scaffold(
      body: OracleHealthConnectTile(client: client),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows disconnected state and Connect action', (tester) async {
    final client = _FakeOracleHealthClient();

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    expect(find.text('Oracle Health (Cerner)'), findsOneWidget);
    expect(
      find.text('Connect to access your Oracle Health records'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(client.statusCalls, 1);
  });

  testWidgets('shows connected state and Disconnect action', (tester) async {
    final client = _FakeOracleHealthClient()
      ..connection = const OracleHealthConnectionStatus(
        connected: true,
        source: 'ORACLE_HEALTH',
        status: 'ACTIVE',
      );

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    expect(find.text('Connected to Oracle Health'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Disconnect'), findsOneWidget);
  });

  testWidgets('shows Retry when status cannot be checked', (tester) async {
    final client = _FakeOracleHealthClient()..failStatus = true;

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to check Oracle Health connection.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

    client.failStatus = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(client.statusCalls, 2);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('shows Reconnect for expired authorization', (tester) async {
    final client = _FakeOracleHealthClient()
      ..connection = const OracleHealthConnectionStatus(
        connected: false,
        source: 'ORACLE_HEALTH',
        status: 'EXPIRED',
      );

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    expect(
      find.text('Authorization expired. Reconnect to continue.'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Reconnect'), findsOneWidget);
  });

  testWidgets('connect action invokes the injected client', (tester) async {
    final client = _FakeOracleHealthClient();

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();

    expect(client.connectCalls, 1);
    expect(client.statusCalls, 2);
  });

  testWidgets('connect failure displays an error message', (tester) async {
    final client = _FakeOracleHealthClient()..failConnect = true;

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect'));
    await tester.pump();

    expect(
      find.text('Unable to start Oracle Health connection.'),
      findsOneWidget,
    );
  });

  testWidgets('disconnect cancellation preserves connection', (tester) async {
    final client = _FakeOracleHealthClient()
      ..connection = const OracleHealthConnectionStatus(
        connected: true,
        source: 'ORACLE_HEALTH',
        status: 'ACTIVE',
      );

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    expect(find.text('Disconnect Oracle Health?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(client.disconnectCalls, 0);
    expect(find.text('Connected to Oracle Health'), findsOneWidget);
  });

  testWidgets('confirmed disconnect updates the connection state',
      (tester) async {
    final client = _FakeOracleHealthClient()
      ..connection = const OracleHealthConnectionStatus(
        connected: true,
        source: 'ORACLE_HEALTH',
        status: 'ACTIVE',
      );

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Disconnect'),
    );
    await tester.pumpAndSettle();

    expect(client.disconnectCalls, 1);
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });

  testWidgets('failed disconnect preserves connected state', (tester) async {
    final client = _FakeOracleHealthClient()
      ..connection = const OracleHealthConnectionStatus(
        connected: true,
        source: 'ORACLE_HEALTH',
        status: 'ACTIVE',
      )
      ..failDisconnect = true;

    await tester.pumpWidget(_testApp(client));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Disconnect'),
    );
    await tester.pump();

    expect(client.disconnectCalls, 1);
    expect(find.text('Connected to Oracle Health'), findsOneWidget);
    expect(
      find.text('Unable to disconnect Oracle Health.'),
      findsOneWidget,
    );
  });

  testWidgets('shows loading indicator while status is pending',
      (tester) async {
    final client = _FakeOracleHealthClient()..statusGate = Completer<void>();

    await tester.pumpWidget(_testApp(client));
    await tester.pump();

    expect(
      find.text('Checking Oracle Health connection...'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    client.statusGate!.complete();
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
  });
}
