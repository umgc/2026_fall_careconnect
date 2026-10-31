// Coverage tests for ProfilePictureWidget
// (lib/widgets/profile_picture_widget.dart): uploading a new photo from a
// real temp file, with the uploading overlay, the reload and the parent
// callback on success, and the error snackbar when the upload is rejected.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/services/enhanced_file_service.dart';
import 'package:care_connect_app/widgets/profile_picture_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    dynamic Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      result;
}

class _Backend {
  _Backend({this.uploadCode = 200});
  final int uploadCode;
  bool uploaded = false;
  final paths = <String>[];

  MockClient client() => MockClient((req) async {
        final path = req.url.path;
        paths.add('${req.method} $path');
        if (path.endsWith('/upload')) {
          if (uploadCode != 200) {
            return http.Response('{"error":"too big"}', uploadCode);
          }
          uploaded = true;
          return http.Response(
              jsonEncode({
                'data': {'fileId': 9, 'originalFilename': 'me.png'},
              }),
              200);
        }
        if (path.endsWith('/profile-image')) {
          return uploaded
              ? http.Response(
                  jsonEncode({
                    'data': {
                      'id': 9,
                      'originalFilename': 'me.png',
                      'contentType': 'image/png',
                      'fileSize': _png.length,
                      'fileCategory': 'PROFILE_PICTURE',
                      'ownerId': 1,
                      'ownerType': 'USER',
                    },
                  }),
                  200)
              : http.Response('{}', 404);
        }
        if (path.endsWith('/download')) {
          return http.Response.bytes(_png, 200);
        }
        return http.Response('{}', 200);
      });
}

void main() {
  late _FakeFilePicker picker;
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _FakeFilePicker();
    dir = Directory.systemTemp.createTempSync('pfp_cov_');
    final path = '${dir.path}${Platform.pathSeparator}me.png';
    File(path).writeAsBytesSync(_png);
    picker.result = FilePickerResult([
      PlatformFile(name: 'me.png', size: _png.length, path: path),
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'read' &&
          (call.arguments as Map)['key'] == 'jwt_token') {
        return 'jwt';
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> startUpload(WidgetTester tester, Widget widget) async {
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: widget))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(ProfilePictureWidget));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload New Photo'));
    await tester.pump();
    await tester.pump();
  }

  Future<void> settleIo(WidgetTester tester, Finder done) async {
    // Let the real file I/O run until the expected result appears.
    for (var i = 0; i < 250 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('a successful upload reloads the image and notifies the parent',
      (tester) async {
    final updates = <UserFileDTO>[];
    final backend = _Backend();
    await http.runWithClient(() async {
      await startUpload(
        tester,
        ProfilePictureWidget(onImageUpdated: updates.add),
      );
      // The overlay spinner is shown while the upload is in flight.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await settleIo(
          tester, find.text('Profile picture updated successfully'));
    }, backend.client);
    expect(backend.paths.where((p) => p.endsWith('/upload')), hasLength(1));
    expect(find.text('Profile picture updated successfully'), findsOneWidget);
    expect(updates.single.id, 9);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a rejected upload shows an error', (tester) async {
    final updates = <UserFileDTO>[];
    final backend = _Backend(uploadCode: 413);
    await http.runWithClient(() async {
      await startUpload(
        tester,
        ProfilePictureWidget(onImageUpdated: updates.add),
      );
      await settleIo(tester, find.text('Failed to upload profile picture'));
    }, backend.client);
    expect(find.text('Failed to upload profile picture'), findsOneWidget);
    expect(updates, isEmpty);
  });
}
