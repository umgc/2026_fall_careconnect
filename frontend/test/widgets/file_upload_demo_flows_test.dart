// FileUploadDemo with a file list served by a MockClient: file cards,
// download and delete from the card menu, and a quick photo upload whose
// picked file cannot be read.

import 'dart:convert';

import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/user_provider.dart';
import 'package:care_connect_app/widgets/file_upload_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import '../mock_user_provider.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _imagePicker = MethodChannel('plugins.flutter.io/image_picker');

final _files = [
  {
    'id': 1,
    'originalFilename': 'tiny.txt',
    'contentType': 'text/plain',
    'fileSize': 100,
  },
  {
    'id': 2,
    'originalFilename': 'scan.pdf',
    'contentType': 'application/pdf',
    'fileSize': 5 * 1024,
  },
  {
    'id': 3,
    'originalFilename': 'video.mp4',
    'contentType': 'video/mp4',
    'fileSize': 5 * 1024 * 1024,
  },
  {
    'id': 4,
    'originalFilename': 'backup.zip',
    'contentType': 'application/zip',
    'fileSize': 5 * 1024 * 1024 * 1024,
  },
];

void main() {
  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, (call) async => null);
    messenger.setMockMethodCallHandler(
        _imagePicker, (call) async => '/missing/photo.jpg');
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_secureStorage, null);
    messenger.setMockMethodCallHandler(_imagePicker, null);
  });

  testWidgets('lists files, downloads, deletes and handles a quick upload',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path.endsWith('/list')) {
        return http.Response(jsonEncode({'files': _files}), 200);
      }
      if (request.url.path.endsWith('/download')) {
        return http.Response.bytes([1, 2], 200);
      }
      return http.Response('{}', 200);
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(
        ChangeNotifierProvider<UserProvider>.value(
          value: MockUserProvider(),
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: FileUploadDemo(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('scan.pdf'), findsOneWidget);
      expect(find.textContaining('GB'), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests.where((r) => r.endsWith('/download')), hasLength(1));

      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(requests.where((r) => r.startsWith('DELETE')), hasLength(1));

      await tester.tap(find.text('Profile Photo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SnackBar), findsWidgets);
    }, () => client);
  });
}
