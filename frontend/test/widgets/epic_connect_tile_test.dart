import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/widgets/epic_connect_tile.dart';

import '../helpers/titled_route_probe.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });
  testWidgets('buttonOnly shows the compact Epic connect action',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EpicConnectTile(buttonOnly: true),
        ),
      ),
    );

    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);

    // The compact version is used when the parent screen already displays
    // the Epic source name and connection status.
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Epic (MyChart)'), findsNothing);
  });
  testWidgets('buttonOnly uses the theme primary color in dark mode',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: EpicConnectTile(buttonOnly: true),
        ),
      ),
    );

    final button = tester.widget<TextButton>(find.byType(TextButton));

    expect(
      button.style?.foregroundColor?.resolve(<WidgetState>{}),
      ThemeData.dark().colorScheme.primary,
    );
  });
  testWidgets('shows disconnected state after Epic status loads',
      (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/api/epic/status'));

      return http.Response(
        jsonEncode({'connected': false}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpicConnectTile(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Epic (MyChart)'), findsOneWidget);
      expect(
        find.text('Connect to import your clinical records'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Connect'),
        findsOneWidget,
      );
      expect(find.text('Disconnect'), findsNothing);
    }, () => client);
  });

  testWidgets('shows connected state after Epic status loads', (tester) async {
    final client = MockClient((request) async {
      expect(request.url.path, endsWith('/api/epic/status'));

      return http.Response(
        jsonEncode({'connected': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpicConnectTile(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Epic (MyChart)'), findsOneWidget);
      expect(
        find.textContaining('Connected'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Disconnect'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Connect'),
        findsNothing,
      );
    }, () => client);
  });
  testWidgets('disconnects Epic and refreshes to disconnected state',
      (tester) async {
    var statusCalls = 0;
    var disconnectCalls = 0;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/epic/status')) {
        statusCalls++;

        return http.Response(
          jsonEncode({
            'connected': statusCalls == 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path.endsWith('/api/epic/disconnect')) {
        disconnectCalls++;

        return http.Response('', 200);
      }

      return http.Response('not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpicConnectTile(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextButton, 'Disconnect'),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(TextButton, 'Disconnect'),
      );
      await tester.pumpAndSettle();

      expect(disconnectCalls, 1);
      expect(statusCalls, 2);

      expect(
        find.text('Disconnected from Epic.'),
        findsOneWidget,
      );

      expect(
        find.widgetWithText(FilledButton, 'Connect'),
        findsOneWidget,
      );
    }, () => client);
  });

  testWidgets('stays connected when Epic disconnect is not successful',
      (tester) async {
    var disconnectCalls = 0;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/epic/status')) {
        return http.Response(
          jsonEncode({'connected': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path.endsWith('/api/epic/disconnect')) {
        disconnectCalls++;

        return http.Response('', 500);
      }

      return http.Response('not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpicConnectTile(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(TextButton, 'Disconnect'),
      );
      await tester.pumpAndSettle();

      expect(disconnectCalls, 1);

      expect(
        find.widgetWithText(TextButton, 'Disconnect'),
        findsOneWidget,
      );
    }, () => client);
  });
  testWidgets('shows an error when Epic connection cannot be started',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/epic/status')) {
        return http.Response(
          jsonEncode({'connected': false}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path.endsWith('/api/epic/authorize')) {
        return http.Response('server error', 500);
      }

      return http.Response('not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpicConnectTile(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Connect'),
        findsOneWidget,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, 'Connect'),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not start Epic connection'),
        findsOneWidget,
      );

      // Busy state should be cleared after the failure.
      expect(
        find.widgetWithText(FilledButton, 'Connect'),
        findsOneWidget,
      );
    }, () => client);
  });
  testWidgets('refreshes Epic status when the app resumes', (tester) async {
    var statusCalls = 0;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/epic/status')) {
        statusCalls++;

        return http.Response(
          jsonEncode({
            'connected': statusCalls > 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('not found', 404);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EpicConnectTile(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(statusCalls, 1);
      expect(
        find.widgetWithText(FilledButton, 'Connect'),
        findsOneWidget,
      );

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );

      await tester.pumpAndSettle();

      expect(statusCalls, 2);
      expect(
        find.widgetWithText(TextButton, 'Disconnect'),
        findsOneWidget,
      );
    }, () => client);
  });

  // VPAT 2.4.2 (Team E): the sign-in page Connect opens has its own title.
  testWidgets('Connect opens the in-app sign-in page titled "Connect Epic"',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/status')) {
        return http.Response(jsonEncode({'connected': false}), 200);
      }
      if (request.url.path.endsWith('/authorize')) {
        return http.Response(
            jsonEncode({'authUrl': 'https://epic.example/authorize'}), 200);
      }
      return http.Response('{}', 404);
    });

    await http.runWithClient(() async {
      final probe = TitledRouteProbe();
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [probe],
        home: const Scaffold(body: EpicConnectTile()),
      ));
      await tester.pumpAndSettle();
      expect(await probe.tapAndReadTitle(tester, find.text('Connect')),
          'Connect Epic');
    }, () => client);
  });
}
