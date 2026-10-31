// Coverage-focused widget tests for error/edge paths (group I).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/evv/presentation/pages/evv_corrections.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_input_form.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_tab.dart';
import 'package:care_connect_app/features/health/symptom-tracker/widgets/allergies_card.dart';
import 'package:care_connect_app/features/social/presentation/pages/new_post_screen.dart';
import 'package:care_connect_app/features/summary/summary_confirmation_card.dart';
import 'package:care_connect_app/features/tasks/presentation/tasks_screen.dart';
import 'package:care_connect_app/providers/confirmation_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/api_service_offline.dart';

import '../mock_user_provider.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _connectivity = MethodChannel('dev.fluttercommunity.plus/connectivity');

class _MockConfirmation extends Mock implements ConfirmationProvider {}

void _bigView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final expiry =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400).toString();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secure, (call) async {
      final key = (call.arguments as Map?)?['key'];
      if (call.method == 'read') {
        if (key == 'jwt_token') return 'test-jwt';
        if (key == 'token_expiry') return expiry;
      }
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });
    m.setMockMethodCallHandler(
        _connectivity, (call) async => call.method == 'check' ? ['wifi'] : null);
    m.setMockStreamHandler(
      const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(_secure, null);
    m.setMockMethodCallHandler(_connectivity, null);
  });

  group('AllergiesTab', () {
    testWidgets('adding without a patient id shows snackbar', (tester) async {
      _bigView(tester);
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response('{"data":[]}', 200)));
      addTearDown(ApiService.debugResetHttpClient);
      final provider = UserProvider()
        ..setUser(UserSession(
            id: 1, email: 'p@x.com', role: 'PATIENT', token: 't', patientId: 12));
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: const MaterialApp(
            home: Scaffold(body: AllergiesTab(patientId: '12'))),
      ));
      await _settle(tester);
      expect(find.text('No allergies recorded yet'), findsOneWidget);
      provider.setUser(UserSession(
          id: 1, email: 'p@x.com', role: 'CAREGIVER', token: 't'));
      tester
          .widget<AllergyInputForm>(find.byType(AllergyInputForm))
          .onAllergyAdded!({'allergen': 'Dust'});
      await _settle(tester);
      expect(find.text('Patient ID not found'), findsOneWidget);
    });

    testWidgets('add and delete failures show error snackbars',
        (tester) async {
      _bigView(tester);
      final client = MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
              jsonEncode({
                'data': [
                  {'id': 1, 'allergen': 'Penicillin', 'severity': 'SEVERE'}
                ]
              }),
              200);
        }
        throw http.ClientException('offline');
      });
      ApiService.debugSetHttpClient(client);
      addTearDown(ApiService.debugResetHttpClient);
      await http.runWithClient(() async {
        await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(
              mockUser: MockUser(id: 1, role: 'PATIENT', patientId: 12)),
          child: const MaterialApp(
              home: Scaffold(body: AllergiesTab(patientId: '12'))),
        ));
        await _settle(tester);
        expect(find.text('Penicillin'), findsOneWidget);

        tester
            .widget<AllergyInputForm>(find.byType(AllergyInputForm))
            .onAllergyAdded!({'allergen': 'Dust'});
        await _settle(tester);
        expect(find.textContaining('Failed to add allergy'), findsOneWidget);

        tester.widget<AllergyCard>(find.byType(AllergyCard)).onDelete();
        await _settle(tester);
        expect(find.text('Penicillin'), findsOneWidget);
      }, () => client);
    });
  });

  group('SummaryConfirmationCard', () {
    Map<String, dynamic> item() => {
          'id': 5,
          'sourceType': 'SUMMARY',
          'status': 'PENDING',
          'payload': '{"headline":"Took aspirin","type":"ACTION_ITEM"}',
        };

    testWidgets('confirm error, busy spinner, dismiss failure and error',
        (tester) async {
      final provider = _MockConfirmation();
      final gate = Completer<bool>();
      when(() => provider.confirmItem(any(), note: any(named: 'note')))
          .thenAnswer((_) => gate.future);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SummaryConfirmationCard(item: item(), provider: provider))));
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      gate.completeError(Exception('boom'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Could not confirm item: '), findsOneWidget);

      when(() => provider.dismissItem(any(), note: any(named: 'note')))
          .thenAnswer((_) async => false);
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();
      expect(find.text('Took aspirin'),
          findsOneWidget);

      when(() => provider.dismissItem(any(), note: any(named: 'note')))
          .thenThrow(Exception('nope'));
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Dismiss'));
      await tester.pumpAndSettle();
      verify(() => provider.dismissItem(5, note: any(named: 'note'))).called(2);
    });
  });

  group('EvvCorrectionsPage approvals', () {
    Map<String, dynamic> rec(int id) => {
          'id': id,
          'serviceType': 'Personal Care',
          'individualName': 'Mary Johnson',
          'caregiverId': 1,
          'status': 'COMPLETED',
          'stateCode': 'VA',
          'dateOfService': '2026-08-01T09:00:00.000',
          'timeIn': '2026-08-01T09:00:00.000',
          'timeOut': '2026-08-01T10:00:00.000',
          'createdAt': '2026-08-01T10:00:00.000',
          'updatedAt': '2026-08-01T10:00:00.000',
        };
    Map<String, dynamic> corr(int id) => {
          'id': id,
          'originalRecord': rec(1),
          'correctedRecord': rec(1),
          'reasonCode': 'SCHEDULE_CHANGE',
          'explanation': 'Adjusted check-in time',
          'correctedBy': 7,
          'correctedAt': '2026-08-01T11:00:00.000',
          'approvalRequired': true,
          'originalValues': {'timeIn': '09:00'},
          'correctedValues': {'timeIn': '09:15'},
        };

    testWidgets('cancel and failing approve for correction and EOR',
        (tester) async {
      _bigView(tester);
      ApiServiceOffline.debugOverrideHttpClient(MockClient((req) async {
        final url = req.url.toString();
        if (req.method == 'GET' && url.contains('/corrections/pending')) {
          return http.Response(jsonEncode([corr(1)]), 200);
        }
        if (req.method == 'GET' &&
            url.contains('/records/pending-eor-approvals')) {
          return http.Response(jsonEncode([rec(5)]), 200);
        }
        return http.Response('{"error":"denied"}', 500);
      }));
      addTearDown(() => ApiServiceOffline.debugOverrideHttpClient(null));
      await tester.pumpWidget(const MaterialApp(home: EvvCorrectionsPage()));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Error approving correction'), findsOneWidget);

      await tester.tap(find.text('EOR Approvals (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('EOR Approvals (1)'), findsOneWidget);
    });
  });

  group('NewPostScreen', () {
    Widget host(UserProvider p) => ChangeNotifierProvider<UserProvider>.value(
          value: p,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NewPostScreen())),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('logged-out back button pops', (tester) async {
      await tester.pumpWidget(host(UserProvider()));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('User not logged in'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('network exception shows snackbar, then back pops',
        (tester) async {
      await http.runWithClient(() async {
        await tester.pumpWidget(host(MockUserProvider(
            mockUser: MockUser(id: 3, role: 'PATIENT', patientId: 3))));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Hello world');
        await tester.tap(find.text('Post'));
        await _settle(tester);
        expect(find.textContaining('Exception:'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.text('Open'), findsOneWidget);
      }, () => MockClient((_) async => throw Exception('offline')));
    });
  });

  group('TasksScreen', () {
    testWidgets('error on fetch and refetch on widget update', (tester) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => throw Exception('server unreachable')));
      addTearDown(ApiService.debugResetHttpClient);
      final provider = UserProvider()
        ..setUser(UserSession(
          id: 1,
          email: 'caregiver@test.com',
          role: 'caregiver',
          token: 'test-token',
          caregiverId: 1,
        ));
      Widget app(int id) => ChangeNotifierProvider<UserProvider>.value(
            value: provider,
            child: MaterialApp(
                home: TasksScreen(patientId: id, patientName: 'Pat $id')),
          );
      await tester.pumpWidget(app(1));
      await _settle(tester);
      expect(find.textContaining('Error: '), findsOneWidget);
      await tester.pumpWidget(app(2));
      await _settle(tester);
      expect(find.textContaining('Error: '), findsOneWidget);
    });
  });
}
