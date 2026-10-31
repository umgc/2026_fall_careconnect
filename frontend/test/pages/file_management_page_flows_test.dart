// Flow tests for FileManagementPage (lib/pages/file_management_page.dart)
// with a populated file list: file cards, search and category filtering,
// the per-file menu, the cited-file deep link, analytics breakdown and the
// invite card. ComprehensiveFileService uses package:http top-level calls,
// so bodies run inside http.runWithClient with a MockClient.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/pages/file_management_page.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/services/structured_entry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_user_provider.dart';

final _files = [
  {
    'id': 1,
    'originalFilename': 'lab_panel.pdf',
    'filename': 'lab_panel.pdf',
    'contentType': 'application/pdf',
    'fileSize': 512,
    'fileCategory': 'LAB_RESULT',
    'description': 'Quarterly labs',
  },
  {
    'id': 2,
    'originalFilename': 'rx.png',
    'filename': 'rx.png',
    'contentType': 'image/png',
    'fileSize': 2 * 1024 * 1024,
    'fileCategory': 'PRESCRIPTION',
  },
  {
    'id': 3,
    'originalFilename': 'contact.txt',
    'filename': 'contact',
    'contentType': 'text/plain',
    'fileSize': 4096,
    'fileCategory': 'EMERGENCY_CONTACT',
  },
  {
    'id': 4,
    'originalFilename': 'big.zip',
    'filename': 'big.zip',
    'fileSize': 3 * 1024 * 1024 * 1024,
    'fileCategory': 'REFERENCE',
  },
  {
    'id': 5,
    'originalFilename': 'notes.doc',
    'filename': 'notes.doc',
    'fileSize': 10,
    'fileCategory': 'documents',
  },
];

MockClient _client() => MockClient((req) async {
      if (req.url.path.endsWith('/list')) {
        return http.Response(jsonEncode({'files': _files}), 200);
      }
      return http.Response('{}', 404);
    });

Widget _host(UserProvider provider, {String? highlight}) {
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => ChangeNotifierProvider<UserProvider>.value(
        value: provider,
        child: FileManagementPage(highlightFileId: highlight),
      ),
    ),
    GoRoute(
      path: '/care-circle/invite',
      builder: (_, __) => const Scaffold(body: Text('Invite Page')),
    ),
  ]);
  return MaterialApp.router(
    routerConfig: router,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

Future<void> _pump(WidgetTester tester,
    {String role = 'PATIENT', String? highlight}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(
    MockUserProvider(mockUser: MockUser(role: role)),
    highlight: highlight,
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'readAll') return <String, String>{};
        if (call.method == 'containsKey') return false;
        return null;
      },
    );
  });

  testWidgets('lists files, filters by search and category', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      expect(find.text('lab_panel'), findsOneWidget);
      expect(find.text('rx'), findsOneWidget);
      expect(find.text('Quarterly labs'), findsOneWidget);
      expect(find.text('512 B'), findsOneWidget);
      expect(find.text('2.0 MB'), findsOneWidget);
      expect(find.text('4.0 KB'), findsOneWidget);
      expect(find.text('3.0 GB'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'quarterly');
      await tester.pump();
      expect(find.text('lab_panel'), findsOneWidget);
      expect(find.text('rx'), findsNothing);

      await tester.enterText(find.byType(TextField).first, 'zzz');
      await tester.pump();
      expect(find.text('lab_panel'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump();

      // Category filter via the dropdown.
      final dropdown = find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField || w is DropdownButton);
      await tester.tap(dropdown.first);
      await tester.pumpAndSettle();
      final prescription = find.text('Prescription');
      await tester.tap(prescription.last);
      await tester.pumpAndSettle();
    }, _client);
  });

  testWidgets('file menu shows download/delete notices and structured entry',
      (tester) async {
    final calls = <String>[];
    StructuredEntryService.client = MockClient((req) async {
      calls.add(req.url.path);
      return http.Response('{}', 404);
    });
    StructuredEntryService.authHeadersProvider = () async => {};
    addTearDown(() {
      StructuredEntryService.client = http.Client();
      StructuredEntryService.authHeadersProvider = () async => {};
    });

    await http.runWithClient(() async {
      await _pump(tester);
      final t = lookupAppLocalizations(const Locale('en'));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_downloadButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.filemanage_downloadFeatureComingSoon), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(TabBar)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.ptfiles_deleteButton).last);
      await tester.pumpAndSettle();
      expect(find.text(t.filemanage_deleteFeatureComingSoon), findsOneWidget);

      // Emergency-contact files support structured entry (id 3).
      await tester.tap(find.byType(PopupMenuButton<String>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Structured entry').last);
      await tester.pumpAndSettle();
    }, _client);
    expect(calls.single, contains('/3/structured-entry'));
  });

  testWidgets('structured entry load failure shows a snackbar',
      (tester) async {
    StructuredEntryService.client =
        MockClient((req) async => http.Response('{"error":"x"}', 500));
    StructuredEntryService.authHeadersProvider = () async => {};
    addTearDown(() => StructuredEntryService.client = http.Client());
    await http.runWithClient(() async {
      await _pump(tester);
      await tester.tap(find.byType(PopupMenuButton<String>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Structured entry').last);
      await tester.pumpAndSettle();
    }, _client);
    expect(find.textContaining('Failed to load structured entry'),
        findsOneWidget);
  });

  testWidgets('cited file deep link opens its info dialog', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, highlight: '1');
      await tester.pumpAndSettle();
    }, _client);
    final t = lookupAppLocalizations(const Locale('en'));
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Quarterly labs'), findsWidgets);
    await tester.tap(find.text(t.filemanage_close));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('unknown cited file shows a not-found snackbar',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, highlight: '999');
    }, _client);
    expect(find.text('Cited file 999 was not found'), findsOneWidget);
  });

  testWidgets('analytics tab breaks files down by category', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(t.navAnalytics));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsWidgets);
      expect(find.text(t.filemanage_labResult), findsOneWidget);
      expect(find.text(t.filemanage_prescription), findsOneWidget);
      expect(find.text(t.filemanage_emgContact), findsOneWidget);
      expect(find.text(t.filemanage_ref), findsOneWidget);
      expect(find.text(t.filemanage_genDocument), findsOneWidget);
    }, _client);
  });

  testWidgets('patient upload tab offers the invite flow', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester);
      final t = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(t.filemanage_upload));
      await tester.pumpAndSettle();
      expect(find.text('Invite family help'), findsOneWidget);
      await tester.tap(find.text('Start Invite'));
      await tester.pumpAndSettle();
    }, _client);
    expect(find.text('Invite Page'), findsOneWidget);
  });

  testWidgets('admin sees the compliance dashboard action', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, role: 'ADMIN');
      final t = lookupAppLocalizations(const Locale('en'));
      expect(find.byTooltip(t.filemanage_docComplianceDash), findsOneWidget);
    }, _client);
  });
}
