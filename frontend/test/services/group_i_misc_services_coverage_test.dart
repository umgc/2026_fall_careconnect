// Coverage-focused tests for misc services (group I): help search, token
// refresh, transcript uploads, profile and invoice error paths.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:care_connect_app/features/help/data/help_repository.dart';
import 'package:care_connect_app/features/help/models/help_article.dart';
import 'package:care_connect_app/features/help/models/help_category.dart';
import 'package:care_connect_app/features/help/models/help_glossary_term.dart';
import 'package:care_connect_app/features/help/models/help_role.dart';
import 'package:care_connect_app/features/help/models/help_section.dart';
import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:care_connect_app/features/invoices/services/invoice_service.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/profile_service.dart';
import 'package:care_connect_app/services/transcript_outbox/pending_transcript_segment.dart';
import 'package:care_connect_app/services/transcript_outbox/transcript_upload.dart';

const _secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
final Map<String, String> _store = {};

PendingTranscriptSegment _segment() => PendingTranscriptSegment(
      clientSegmentId: 'seg-1',
      ownerUserId: 'u1',
      callId: 'call-1',
      speakerLabel: 'A',
      text: 'hello',
      startMs: 0,
      endMs: 10,
      source: 'test',
      createdAt: DateTime.utc(2024),
      nextAttemptAt: DateTime.utc(2024),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, (call) async {
      final args = (call.arguments as Map?) ?? {};
      switch (call.method) {
        case 'read':
          return _store[args['key']];
        case 'write':
          _store[args['key'] as String] = args['value'] as String;
          return null;
        case 'delete':
          _store.remove(args['key']);
          return null;
        case 'readAll':
          return Map<String, String>.from(_store);
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (call) async => call.method == 'check' ? ['wifi'] : null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity_status'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secure, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            null);
  });

  group('HelpRepository.searchArticles', () {
    test('matches glossary terms listed in a glossary section', () {
      final repo = HelpRepository(
        categories: const [
          HelpCategory(id: 'basics', title: 'Basics', description: 'Start'),
        ],
        glossaryTerms: [
          HelpGlossaryTerm(
            id: 'evv',
            term: 'Electronic Visit Verification',
            definition: 'Records visit times.',
            aliases: ['EVV'],
          ),
        ],
        articles: [
          HelpArticle(
            id: 'visits',
            categoryId: 'basics',
            title: 'Visits',
            summary: 'About visits',
            roles: const [HelpRole.caregiver],
            sections: [
              HelpGlossaryTerms(termIds: const ['evv']),
            ],
          ),
        ],
      );
      final hits =
          repo.searchArticles('verification', role: HelpRole.caregiver);
      expect(hits.single.id, 'visits');
    });
  });

  group('UserProvider.refreshToken', () {
    test('no stored token clears the user', () async {
      final p = UserProvider()
        ..setUser(UserSession(
            id: 1, email: 'a@x.com', role: 'PATIENT', token: 't'));
      expect(await p.refreshToken(), isFalse);
      expect(p.user, isNull);
    });

    test('successful refresh replaces the user', () async {
      _store['jwt_token'] = 'old-token';
      final p = UserProvider()
        ..setUser(UserSession(
            id: 1, email: 'a@x.com', role: 'PATIENT', token: 't'));
      final ok = await http.runWithClient(
        () => p.refreshToken(),
        () => MockClient((req) async => http.Response(
            jsonEncode({
              'id': 1,
              'email': 'a@x.com',
              'role': 'PATIENT',
              'token': 'new-token',
            }),
            200)),
      );
      expect(ok, isTrue);
      expect(p.user!.token, 'new-token');
    });
  });

  group('HttpTranscriptSegmentUploader', () {
    test('uses injected client and classifies responses', () async {
      final ok = HttpTranscriptSegmentUploader(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => http.Response('{}', 201)),
      );
      expect(await ok.upload(_segment(), 'jwt'), isA<TranscriptUploadSucceeded>());

      final failing = HttpTranscriptSegmentUploader(
        baseUrl: 'http://example.test',
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      expect(await failing.upload(_segment(), 'jwt'),
          isA<TranscriptUploadRetryable>());
    });

    test('unknown status is terminal and bad retry-after is ignored', () {
      final out = classifyTranscriptUploadResponse(http.Response('', 302));
      expect(out, isA<TranscriptUploadTerminal>());
      expect(parseRetryAfter('not a date at all'), isNull);
    });
  });

  group('ProfileService error paths', () {
    test('caregiver profile returns null when http throws', () async {
      final result = await http.runWithClient(
        () => ProfileService.getCaregiverProfile(5),
        () => MockClient((_) async => throw Exception('offline')),
      );
      expect(result, isNull);
    });

    test('current user profile returns null on malformed session', () async {
      _store['user_session'] =
          jsonEncode({'role': 'PATIENT', 'patientId': 'not-an-int'});
      expect(await ProfileService.getCurrentUserProfile(), isNull);
    });
  });

  group('InvoiceService serialization', () {
    Invoice draft() => Invoice(
          id: 'inv-1',
          invoiceNumber: 'INV-1',
          provider: const ProviderInfo(
              name: 'ACME', address: '1 Rd', phone: '555', email: 'a@b.c'),
          patient: const PatientInfo(
              name: 'Jane', address: '2 Ave', accountNumber: 'P-1'),
          dates: InvoiceDates(
            statementDate: DateTime.utc(2025, 3, 1),
            dueDate: DateTime.utc(2025, 4, 1),
          ),
          paymentStatus: PaymentStatus.pending,
          billedToInsurance: false,
          amounts: const Amounts(totalCharges: 10, total: 10, amountDue: 10),
          paymentReferences: PaymentReferences(supportedMethods: const []),
          checkPayableTo: const CheckPayableTo(
              name: 'ACME', address: '1 Rd', reference: 'REF'),
          createdAt: '2025-03-01T00:00:00.000Z',
          updatedAt: '2025-03-01T00:00:00.000Z',
          createdBy: 'system',
          updatedBy: 'system',
          payments: const [],
        );

    test('create serializes checkPayableTo and handles bad dates', () async {
      String? sentBody;
      final result = await http.runWithClient(
        () => InvoiceService.instance.create(draft()),
        () => MockClient((req) async {
          sentBody = req.body;
          return http.Response(
              jsonEncode({
                'id': 'x',
                'dates': {'statementDate': 12345, 'dueDate': 12345},
              }),
              201);
        }),
      );
      expect(sentBody, contains('REF'));
      expect(result, isNull);
    });
  });
}
