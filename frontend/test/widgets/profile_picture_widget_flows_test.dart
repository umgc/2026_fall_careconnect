// Flow tests for ProfilePictureWidget and CompactProfilePicture with a
// stored profile image served by a MockClient: viewing, removing and the
// upload guards.

import 'dart:convert';

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

/// A valid 1x1 PNG so Image.memory can decode it.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

final _image = {
  'id': 77,
  'originalFilename': 'me.png',
  'contentType': 'image/png',
  'fileSize': 10,
  'fileCategory': 'PROFILE_PICTURE',
  'ownerId': 1,
  'ownerType': 'USER',
};

MockClient _backend({bool hasImage = true, int deleteCode = 200}) =>
    MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/profile-image')) {
        return hasImage
            ? http.Response(jsonEncode({'data': _image}), 200)
            : http.Response('{}', 404);
      }
      if (path.endsWith('/download')) {
        return http.Response.bytes(_onePixelPng, 200);
      }
      if (request.method == 'DELETE') {
        return http.Response('{"error":"nope"}', deleteCode);
      }
      return http.Response('{}', 200);
    });

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester
      .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late _FakeFilePicker picker;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FilePicker.platform = picker = _FakeFilePicker();
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
  });

  testWidgets('a stored image can be viewed full size', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, const ProfilePictureWidget());
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      expect(find.text('View Full Size'), findsOneWidget);
      expect(find.text('Remove Photo'), findsOneWidget);
      await tester.tap(find.text('View Full Size'));
      await tester.pumpAndSettle();
      expect(find.text('Profile Picture'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Profile Picture'), findsNothing);
    }, _backend);
  });

  testWidgets('read-only widgets open the full-size view on tap',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, const ProfilePictureWidget(canEdit: false));
      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      expect(find.text('Profile Picture'), findsOneWidget);
    }, _backend);
  });

  testWidgets('removing the image notifies the parent', (tester) async {
    final updates = <UserFileDTO>[];
    await http.runWithClient(() async {
      await _pump(tester, ProfilePictureWidget(onImageUpdated: updates.add));

      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(updates, isEmpty);

      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Profile picture removed successfully'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
    }, _backend);
    expect(updates.single.id, -1);
  });

  testWidgets('a failed removal is reported', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, const ProfilePictureWidget());
      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove Photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Failed to remove profile picture'), findsOneWidget);
    }, () => _backend(deleteCode: 500));
  });

  testWidgets('images over 5MB are rejected before upload', (tester) async {
    picker.result = FilePickerResult([
      PlatformFile(name: 'big.png', size: 6 * 1024 * 1024, path: '/x/big.png'),
    ]);
    await http.runWithClient(() async {
      await _pump(tester, const ProfilePictureWidget());
      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload New Photo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Image size must be less than 5MB'), findsOneWidget);
    }, _backend);
  });

  testWidgets('a pick without a file path reports an upload error',
      (tester) async {
    picker.result = FilePickerResult([
      PlatformFile(name: 'nopath.png', size: 10),
    ]);
    await http.runWithClient(() async {
      await _pump(tester, const ProfilePictureWidget());
      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload New Photo'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('Error uploading image'), findsOneWidget);
    }, _backend);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    picker.result = null;
    await http.runWithClient(() async {
      await _pump(tester, const ProfilePictureWidget());
      await tester.tap(find.byType(ProfilePictureWidget));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload New Photo'));
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    }, _backend);
  });

  testWidgets('an existing image URL that fails falls back to the placeholder',
      (tester) async {
    await http.runWithClient(() async {
      await _pump(
        tester,
        const ProfilePictureWidget(
          existingImageUrl: 'https://example.invalid/me.png',
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    }, () => _backend(hasImage: false));
  });

  testWidgets('compact picture loads the stored image', (tester) async {
    await http.runWithClient(() async {
      await _pump(
        tester,
        CompactProfilePicture(
          profileImage: UserFileDTO.fromJson(_image),
          initials: 'pe',
        ),
      );
      expect(find.byType(Image), findsOneWidget);
    }, _backend);
  });
}
