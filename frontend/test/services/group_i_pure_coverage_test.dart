// Coverage-focused tests for small pure helpers and HTTP error paths (group I).
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/config/app_config.dart';
import 'package:care_connect_app/config/theme/color_utils.dart';
import 'package:care_connect_app/config/theme/sentiment_colors.dart';
import 'package:care_connect_app/features/admin_analytics/data/admin_analytics_api.dart';
import 'package:care_connect_app/features/admin_analytics/presentation/widgets/admin_analytics_item_descriptions.dart';
import 'package:care_connect_app/features/ai/presentation/pages/voice_command_web_speech_stub.dart';
import 'package:care_connect_app/features/dashboard/models/patient_model.dart';
import 'package:care_connect_app/features/dashboard/presentation/pages/patient_parser.dart';
import 'package:care_connect_app/features/dashboard/utils/link_debugger.dart';
import 'package:care_connect_app/features/health/health_data/services/ehr_data_service.dart';
import 'package:care_connect_app/features/health/health_data/services/medicare_data_service.dart';
import 'package:care_connect_app/features/profile/models/profile_model.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/models/hiring_form_models.dart';
import 'package:care_connect_app/providers/shortcut_provider.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/api_client.dart';
import 'package:care_connect_app/services/api_service.dart';
import 'package:care_connect_app/services/confirmation_api_service.dart';
import 'package:care_connect_app/services/document_compliance_service.dart';

import '../features/health/health_data/health_data_test_support.dart';
import '../mock_user_provider.dart';

const MethodChannel _secure =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure,
            (call) async => call.method == 'readAll' ? <String, String>{} : null);
  });

  group('theme/config helpers', () {
    test('ColorUtils getters and lighter shades', () {
      expect(ColorUtils.backgroundSecondary, isA<Color>());
      expect(ColorUtils.cardBackground, isA<Color>());
      expect(ColorUtils.getWarningLighter(), const Color(0xFFFEF3C7));
      expect(ColorUtils.getErrorLighter(), const Color(0xFFFECACA));
    });

    test('SentimentColors channel and band fill', () {
      expect(SentimentColors.forChannel('text', isDark: false), isA<Color>());
      expect(SentimentColors.forChannel('TEXT', isDark: true), isA<Color>());
      expect(SentimentColors.bandFill(0.5, isDark: true), isA<Color>());
      expect(SentimentColors.bandFill(-0.5, isDark: false), isA<Color>());
    });

    test('AppConfig merchant ids and places flag', () {
      expect(AppConfig.getAppleMerchantId(), isA<String>());
      expect(AppConfig.getGooglePayMerchantId(), isA<String>());
      expect(AppConfig.isGooglePlacesConfigured(), isA<bool>());
    });

    test('VoiceCommandWebSpeechController stub is inert', () async {
      final c = VoiceCommandWebSpeechController();
      expect(c.lastRecognizedWords, '');
      expect(await c.initialize(), isFalse);
      expect(
          await c.listen(
            localeId: 'en_US',
            onStatus: (_) {},
            onError: (_) {},
            onResult: (_, __) {},
          ),
          isFalse);
      await c.stop();
    });
  });

  group('models', () {
    test('ValidationRule.summary covers all types', () {
      String s(String type, [Object? v]) =>
          ValidationRule(type: type, value: v).summary;
      expect(s('MIN_LENGTH', 2), 'min length 2');
      expect(s('MAX', 9), 'max 9');
      expect(s('AGE_MIN', 18), 'min age 18');
      expect(s('DATE_RANGE'), 'valid date');
      expect(s('CUSTOM_THING'), 'custom_thing');
    });

    test('Caregiver and patient profile copyWith keep fields', () {
      final cg = CaregiverProfile(
          id: 1, name: 'A', email: 'a@x.com', specialization: 'RN',
          license: 'L1');
      final cg2 = cg.copyWith(name: 'B');
      expect(cg2.specialization, 'RN');
      expect(cg2.license, 'L1');
      expect(cg.copyWith(specialization: 'MD', license: 'L2').license, 'L2');

      final p = PatientProfile(
          id: 2, name: 'P', email: 'p@x.com', gender: 'F', allergies: 'nuts');
      final p2 = p.copyWith(name: 'Q');
      expect(p2.gender, 'F');
      expect(p2.allergies, 'nuts');
    });

    test('ShortcutDef.localizedLabel maps every key', () {
      final t = lookupAppLocalizations(const Locale('en'));
      for (final key in [
        'dashboard',
        'invoiceAssistant',
        'calendarAssistant',
        'socialFeed',
        'medicationManagement',
        'evv',
        'wearables',
        'fileManagement',
        'gamification',
        'unknownKey',
      ]) {
        final def = ShortcutDef(
          key: key,
          icon: Icons.star,
          label: 'Fallback',
          labelKey: key,
          routeTemplate: '/x',
        );
        expect(def.localizedLabel(t), isNotEmpty);
      }
    });

    test('AdminAnalyticsItemDescriptions fallbacks', () {
      expect(AdminAnalyticsItemDescriptions.event('weird_event'),
          contains('weird_event'));
      expect(AdminAnalyticsItemDescriptions.feature('mystery'),
          contains('mystery'));
      expect(AdminAnalyticsItemDescriptions.errorEndpoint(''),
          contains('unknown'));
    });
  });

  group('PatientParser', () {
    test('string linkId and no status field', () {
      final p = PatientParser.parsePatientItem({
        'patient': {
          'id': 1,
          'firstName': 'A',
          'lastName': 'B',
          'email': '',
          'phone': '',
          'dob': '',
        },
        'link': {'linkId': '12'},
      });
      expect(p.linkId, 12);
      expect(p.linkStatus, 'ACTIVE');
    });

    test('no id fields at all', () {
      final p = PatientParser.parsePatientItem({
        'patient': {'id': 1, 'firstName': 'A', 'lastName': 'B'},
        'link': {'other': true},
      });
      expect(p.linkId, isNull);
    });

    test('malformed patient falls back to error patient', () {
      final p = PatientParser.parsePatientItem({'patient': 'not-a-map'});
      expect(p.firstName, 'Error');
    });
  });

  group('LinkDebugger link variants', () {
    final patient = Patient(
      id: 7,
      firstName: 'Lin',
      lastName: 'Ko',
      email: '',
      phone: '',
      dob: '',
      relationship: '',
    );

    Future<void> runWith(WidgetTester tester, Object body) async {
      ApiService.debugSetHttpClient(
          MockClient((_) async => http.Response(jsonEncode(body), 200)));
      late BuildContext ctx;
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>.value(
        value: MockUserProvider(
            mockUser: MockUser(id: 1, role: 'CAREGIVER', caregiverId: 3)),
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));
      await runZoned(
        () => LinkDebugger.debugLinkIdForPatient(ctx, patient),
        zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
      );
      ApiService.debugResetHttpClient();
    }

    testWidgets('string link.id with active flag', (tester) async {
      await runWith(tester, [
        {
          'patient': {'id': 7},
          'link': {'id': '9', 'active': true},
        }
      ]);
    });

    testWidgets('int linkId', (tester) async {
      await runWith(tester, [
        {
          'patient': {'id': 7},
          'link': {'linkId': 4, 'active': false},
        }
      ]);
    });

    testWidgets('string relationshipId', (tester) async {
      await runWith(tester, [
        {
          'patient': {'id': 7},
          'link': {'relationshipId': '6'},
        }
      ]);
    });
  });

  group('AdminAnalyticsApi error paths', () {
    test('summary rejects non-map body', () async {
      await expectLater(
        http.runWithClient(
          () => const AdminAnalyticsApi()
              .fetchSummary(from: DateTime(2024), to: DateTime(2024, 2)),
          () => MockClient((_) async => http.Response('[]', 200)),
        ),
        throwsA(isA<AdminAnalyticsApiException>().having(
            (e) => e.toString(), 'msg', 'Invalid analytics response format')),
      );
    });

    test('feature trends rejects non-map body', () async {
      await expectLater(
        http.runWithClient(
          () => const AdminAnalyticsApi().fetchFeatureTrends(
              from: DateTime(2024), to: DateTime(2024, 2), feature: 'x'),
          () => MockClient((_) async => http.Response('[]', 200)),
        ),
        throwsA(isA<AdminAnalyticsApiException>()),
      );
    });
  });

  group('ConfirmationApiService error paths', () {
    Future<Map<String, dynamic>> run(
            Future<Map<String, dynamic>> Function() fn, MockClient c) =>
        http.runWithClient(fn, () => c);
    final throwing = MockClient((_) async => throw Exception('net down'));
    final fail = MockClient((_) async => http.Response('x', 500));

    test('catch blocks return error maps', () async {
      expect((await run(() => ConfirmationApiService.fetchPendingItems(),
          throwing))['success'], isFalse);
      expect((await run(() => ConfirmationApiService.fetchItem(1), throwing))[
          'success'], isFalse);
      expect(
          (await run(() => ConfirmationApiService.dismissItem(1), throwing))[
              'success'],
          isFalse);
    });

    test('non-200 confirm/dismiss return HTTP error', () async {
      expect((await run(() => ConfirmationApiService.confirmItem(1), fail))[
          'error'], 'HTTP 500');
      expect((await run(() => ConfirmationApiService.dismissItem(1), fail))[
          'error'], 'HTTP 500');
    });
  });

  group('DocumentComplianceService', () {
    test('getMissing parses updatedAt and passes filters', () async {
      final rows = await http.runWithClient(
        () => DocumentComplianceService.getMissing(
            subjectType: 'EMPLOYEE', documentType: 'I9'),
        () => MockClient((req) async {
          expect(req.url.queryParameters['subjectType'], 'EMPLOYEE');
          return http.Response(
              jsonEncode([
                {
                  'subjectType': 'EMPLOYEE',
                  'subjectId': 1,
                  'subjectName': 'Pat',
                  'documentType': 'I9',
                  'status': 'MISSING',
                  'updatedAt': '2024-01-02T00:00:00Z',
                }
              ]),
              200);
        }),
      );
      expect(rows.single.updatedAt, isNotNull);
    });

    test('error responses throw', () async {
      final fail = MockClient(
          (_) async => http.Response(jsonEncode({'error': 'nope'}), 500));
      await expectLater(
          http.runWithClient(
              () => DocumentComplianceService.getMissing(), () => fail),
          throwsException);
      await expectLater(
          http.runWithClient(
              () => DocumentComplianceService.exportMissingCsv(
                  subjectType: 'EMPLOYEE', documentType: 'I9'),
              () => fail),
          throwsException);
      await expectLater(
          http.runWithClient(
              () => DocumentComplianceService.getHistory('EMPLOYEE', 1),
              () => fail),
          throwsException);
    });
  });

  group('EHR/Medicare data fallbacks', () {
    late HttpClientAdapter original;
    setUp(() => original = ApiClient.instance.debugHttpClientAdapter);
    tearDown(() => ApiClient.instance.debugSetHttpClientAdapter(original));

    test('Cerner records fall back to codes and class display', () async {
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/api/ehr/resources': '[]',
        '/v1/api/cerner/patients/7/allergies':
            '{"allergies":[{"sourceRecordId":"a1","substanceCode":"PCN"}]}',
        '/v1/api/cerner/patients/7/conditions':
            '{"conditions":[{"sourceRecordId":"c1",'
                '"conditionCodes":["skip",{"display":""},{"code":"I10"}]}]}',
        '/v1/api/cerner/patients/7/encounters': '[]',
      }));
      final records = await EhrDataService().fetchRecords(patientId: 7);
      expect(records, isNotNull);
      final titles = records.map((r) => r.title).toList();
      expect(titles, containsAll(['PCN', 'I10']));
    });

    test('Cerner encounter falls back to classDisplay', () async {
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/api/ehr/resources': '[]',
        '/v1/api/cerner/patients/7/allergies': '{"allergies":"x"}',
        '/v1/api/cerner/patients/7/conditions': '{"conditions":[]}',
        '/v1/api/cerner/patients/7/encounters':
            '{"encounters":[{"sourceRecordId":"e1","classDisplay":"Inpatient"}]}',
      }));
      final records = await EhrDataService().fetchRecords(patientId: 7);
      expect(records.map((r) => r.title), contains('Inpatient'));
    });

    test('Medicare coverage maps plan class from coding display', () async {
      ApiClient.instance.debugSetHttpClientAdapter(RouteAdapter({
        '/v1/api/medicare/visits': '{"resources":[]}',
        '/v1/api/medicare/coverage': jsonEncode({
          'resources': [
            {
              'resourceType': 'Coverage',
              'id': 'cov1',
              'status': 'active',
              'type': {
                'coding': [
                  {'display': 'Medicare Part A'}
                ]
              },
              'class': [
                {
                  'type': {
                    'coding': [
                      {'display': 'Plan A'}
                    ]
                  }
                },
                'junk',
              ],
            }
          ]
        }),
      }));
      final result = await MedicareDataService().fetchRecords();
      expect(result.records.single.title, 'Medicare Part A');
    });
  });
}
