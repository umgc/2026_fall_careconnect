// Coverage tests for UploadAvatarScreen
// (lib/features/profile/presentation/pages/upload_avatar_screen.dart):
// picking an avatar through a fake FilePicker, removing it, the missing
// user id guard, and multipart uploads that succeed or fail. The picked
// file is a real 1x1 PNG in a temp directory, so file reads run in
// tester.runAsync; HTTP goes through http.runWithClient.

import 'dart:convert';
import 'dart:io';

import 'package:care_connect_app/features/profile/presentation/pages/upload_avatar_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _FakeFilePicker extends Fake
    with MockPlatformInterfaceMixin
    implements FilePicker {
  FilePickerResult? result;
  final types = <FileType>[];

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
  }) async {
    types.add(type);
    return result;
  }
}

void main() {
  late _FakeFilePicker picker;
  late Directory dir;
  late String avatarPath;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _FakeFilePicker();
    dir = Directory.systemTemp.createTempSync('avatar_cov_');
    avatarPath = '${dir.path}${Platform.pathSeparator}me.png';
    File(avatarPath).writeAsBytesSync(_png);
    picker.result = FilePickerResult([
      PlatformFile(name: 'me.png', size: _png.length, path: avatarPath),
    ]);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pickAvatar(WidgetTester tester) async {
    await tester.tap(find.text('Pick Avatar'));
    await tester.pump();
    await tester.pump();
  }

  Future<void> upload(WidgetTester tester, Finder done) async {
    await tester.tap(find.text('Upload'));
    // Let the real file I/O run until the expected result appears.
    for (var i = 0; i < 250 && done.evaluate().isEmpty; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('picking shows the image and remove clears it', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UploadAvatarScreen()));
    await pickAvatar(tester);
    expect(picker.types.single, FileType.image);
    expect(find.text('Remove Image'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.text('Remove Image'));
    await tester.pump();
    expect(find.text('Remove Image'), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('a cancelled pick keeps the empty state', (tester) async {
    picker.result = null;
    await tester.pumpWidget(const MaterialApp(home: UploadAvatarScreen()));
    await pickAvatar(tester);
    expect(find.text('Remove Image'), findsNothing);
  });

  testWidgets('upload without a user id asks for one', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UploadAvatarScreen()));
    await pickAvatar(tester);
    await tester.tap(find.text('Upload'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Missing user ID or image'), findsOneWidget);
  });

  testWidgets('a successful upload stores the url and shows a preview',
      (tester) async {
    SharedPreferences.setMockInitialValues({'userId': '42'});
    final requests = <http.BaseRequest>[];
    final client = MockClient((req) async {
      requests.add(req);
      return http.Response(jsonEncode({'imageUrl': '/uploads/me.png'}), 200);
    });
    // The preview NetworkImage cannot load in tests (the test HttpClient
    // answers 400); ignore only that image error while the upload runs.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception is NetworkImageLoadException) return;
      originalOnError?.call(details);
    };
    try {
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: UploadAvatarScreen()));
        await pickAvatar(tester);
        await upload(tester, find.text('Preview:'));
      }, () => client);
    } finally {
      FlutterError.onError = originalOnError;
    }
    expect(requests.single.url.path, endsWith('/auth/avatar/42'));
    expect(requests.single.method, 'POST');
    expect(find.text('Avatar uploaded successfully!'), findsWidgets);
    expect(find.text('Preview:'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('profileImageUrl'), '/uploads/me.png');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a failed upload is reported', (tester) async {
    SharedPreferences.setMockInitialValues({'userId': '42'});
    final client =
        MockClient((req) async => http.Response('{"error":"no"}', 500));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: UploadAvatarScreen()));
      await pickAvatar(tester);
      await upload(tester, find.text('Failed to upload avatar'));
    }, () => client);
    expect(find.text('Failed to upload avatar'), findsOneWidget);
    expect(find.text('Preview:'), findsNothing);
  });
}
