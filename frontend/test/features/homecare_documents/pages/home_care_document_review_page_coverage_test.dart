// Coverage tests for HomeCareDocumentReviewPage
// (lib/features/homecare_documents/pages/home_care_document_review_page.dart):
// saving the reviewed record through a mocked upload endpoint (success pops
// with true, failure shows an error snackbar).

import 'dart:convert';

import 'package:care_connect_app/features/homecare_documents/models/home_care_document_models.dart';
import 'package:care_connect_app/features/homecare_documents/pages/home_care_document_review_page.dart';
import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _result = HomeCareExtractionResult(
  documentType: 'TAX_FORM',
  documentTypeDisplayName: 'Tax Form',
  status: HomeCareExtractionStatus.prefilled,
  documentLink: 'homecare-documents/tax.pdf',
  fields: [
    HomeCareExtractedField(
      key: 'fullName',
      label: 'Full Name',
      value: 'Jane Doe',
      machineGenerated: true,
    ),
    HomeCareExtractedField(
      key: 'ssn',
      label: 'SSN',
      value: '',
      machineGenerated: false,
    ),
  ],
);

class _Launcher extends StatefulWidget {
  const _Launcher(this.results);
  final List<Object?> results;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            final r = await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  const HomeCareDocumentReviewPage(result: _result, patientId: 5),
            ));
            widget.results.add(r);
          },
          child: const Text('open review'),
        ),
      );
}

void main() {
  late List<http.BaseRequest> requests;

  setUp(() {
    requests = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });

  Future<List<Object?>> openAndSave(WidgetTester tester, int status) async {
    final results = <Object?>[];
    final client = MockClient((r) async {
      requests.add(r);
      return status == 200
          ? http.Response(
              jsonEncode({'fileId': 1, 'fileName': 'tax_digitized.json'}), 200)
          : http.Response(jsonEncode({'error': 'disk full'}), status);
    });
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: _Launcher(results),
      ));
      await tester.tap(find.text('open review'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'SSN'), '123-45-6789');
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();
    }, () => client);
    return results;
  }

  testWidgets('a successful save uploads the record and pops with true',
      (tester) async {
    final results = await openAndSave(tester, 200);

    expect(requests, hasLength(1));
    expect(requests.single.url.path, endsWith('/users/5/upload'));
    // MockClient flattens the multipart body; the category field is in it.
    expect((requests.single as http.Request).body, contains('ONBOARDING_FORM'));
    expect(results, [true]);
    expect(find.text('open review'), findsOneWidget);
    expect(find.textContaining('tax_digitized.json'), findsOneWidget);
  });

  testWidgets('a failed upload keeps the page open with an error',
      (tester) async {
    final results = await openAndSave(tester, 500);

    expect(results, isEmpty);
    expect(find.text('Review: Tax Form'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
