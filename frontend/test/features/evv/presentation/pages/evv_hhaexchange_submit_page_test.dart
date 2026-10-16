// Tests for EvvHhaExchangeSubmitPage widget.
// (lib/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart)
//
// Tests initial render and static structure. HTTP calls are handled
// by the singleton mock pattern (setUpAll + _httpHandler).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:care_connect_app/features/evv/presentation/pages/evv_hhaexchange_submit_page.dart';
import 'package:care_connect_app/services/api_service_offline.dart';

late Future<http.Response> Function(http.Request) _httpHandler;

Future<http.Response> _defaultHandler(http.Request request) async {
  if (request.url.path.contains('/hhaexchange')) {
    return http.Response(jsonEncode([]), 200);
  }
  return http.Response('{}', 200);
}

Widget _wrap() {
  return const MaterialApp(
    home: EvvHhaExchangeSubmitPage(),
  );
}

void main() {
  setUpAll(() {
    _httpHandler = _defaultHandler;
    final delegatingClient =
        MockClient((request) => _httpHandler(request));
    http.runWithClient(() {
      ApiServiceOffline.httpClient;
    }, () => delegatingClient);
  });

  setUp(() {
    _httpHandler = _defaultHandler;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') {
          return <String, String>{'jwt_token': 'mock-jwt-for-test'};
        }
        if (call.method == 'read') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return 'mock-jwt-for-test';
          return null;
        }
        if (call.method == 'containsKey') {
          final key = (call.arguments as Map?)?['key'] as String?;
          if (key == 'jwt_token') return true;
          return false;
        }
        if (call.method == 'write' || call.method == 'delete') return null;
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async {
        if (call.method == 'check') return ['wifi'];
        return null;
      },
    );
  });

  group('EvvHhaExchangeSubmitPage - initial render', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(EvvHhaExchangeSubmitPage), findsOneWidget);
    });

    testWidgets('shows Scaffold', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('shows AppBar with title', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('Submit to HHAExchange'), findsOneWidget);
    });

    testWidgets('shows info banner about VA-state records', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.textContaining('APPROVED visits'), findsOneWidget);
    });

    testWidgets('shows refresh button in AppBar', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byTooltip('Refresh'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('EvvHhaExchangeSubmitPage - empty state', () {
    testWidgets('shows empty state after loading with no eligible records',
        (tester) async {
      _httpHandler = (request) async {
        return http.Response(jsonEncode([]), 200);
      };
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('No eligible visits'), findsOneWidget);
    });

    testWidgets('shows refresh button in empty state', (tester) async {
      _httpHandler = (request) async {
        return http.Response(jsonEncode([]), 200);
      };
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Refresh'), findsOneWidget);
    });

    testWidgets('shows check_circle icon in empty state', (tester) async {
      _httpHandler = (request) async {
        return http.Response(jsonEncode([]), 200);
      };
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    });
  });

  group('EvvHhaExchangeSubmitPage - with records', () {
    testWidgets('shows records after successful load', (tester) async {
      _httpHandler = (request) async {
        if (request.url.path.contains('/hhaexchange') ||
            request.url.path.contains('/evv')) {
          return http.Response(jsonEncode([
            {
              'id': 1,
              'patient': {'id': 10, 'firstName': 'Alice', 'lastName': 'Smith'},
              'serviceType': 'Personal Care',
              'individualName': 'Alice Smith',
              'caregiverId': 1,
              'dateOfService': '2026-03-17',
              'timeIn': '2026-03-17T10:00:00',
              'timeOut': '2026-03-17T12:00:00',
              'status': 'APPROVED',
              'stateCode': 'VA',
              'isOffline': false,
              'eorApprovalRequired': false,
              'isCorrected': false,
              'createdAt': '2026-03-17T08:00:00',
              'updatedAt': '2026-03-17T08:00:00',
            },
          ]), 200);
        }
        return http.Response('{}', 200);
      };
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Alice Smith'), findsOneWidget);
    });

    testWidgets('no FAB shown when no records selected', (tester) async {
      _httpHandler = (request) async {
        return http.Response(jsonEncode([]), 200);
      };
      await tester.pumpWidget(_wrap());
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });
}
