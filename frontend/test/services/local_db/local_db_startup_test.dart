import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/services/local_db/local_db_startup.dart';

const MethodChannel pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

const MethodChannel secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // Per-run temp dir instead of a hardcoded '/tmp' (which resolves to a
  // nonexistent C:	mp on Windows and fails with SQLite code 14).
  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('local_db_startup_test_');
    messenger.setMockMethodCallHandler(
      pathProviderChannel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    messenger.setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall methodCall) async {
        switch (methodCall.method) {
          case 'read':
            return null;
          case 'write':
            return null;
          case 'delete':
            return null;
          case 'deleteAll':
            return null;
          case 'containsKey':
            return false;
          case 'readAll':
            return <String, String>{};
          default:
            return null;
        }
      },
    );
  });

  tearDownAll(() {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(secureStorageChannel, null);
    // The startup DB stays open for the process, so Windows may refuse to
    // delete the file; cleanup is best-effort.
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // ignore
    }
  });

  test('initializeLocalDbOnStartup completes without throwing', () async {
    await initializeLocalDbOnStartup();
  });

  test('initializeLocalDbOnStartup is safe to call multiple times', () async {
    await initializeLocalDbOnStartup();
    await initializeLocalDbOnStartup();
  });
}
