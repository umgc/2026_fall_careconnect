// CC-12 Increment 2: saving the QR picture on a phone (share sheet). Test
// Plan §3.27: TC-EMG-278, 279 (the pull request's), 303 (Testing Lead: what
// the share sheet is given, and no temporary folder).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:care_connect_app/features/emergency_passport/utils/qr_image_save_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  const share = MethodChannel('dev.fluttercommunity.plus/share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late List<MethodCall> shared;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cc12_qr_');
    shared = [];
    messenger.setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getTemporaryDirectory') return temp.path;
      return null;
    });
    messenger.setMockMethodCallHandler(share, (call) async {
      shared.add(call);
      return 'dev.fluttercommunity.plus/share/success';
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathProvider, null);
    messenger.setMockMethodCallHandler(share, null);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('TC-EMG-278: writes the picture and opens the share sheet with it', () async {
    final png = Uint8List.fromList([137, 80, 78, 71]);
    final ok = await saveQrImage(png, 'careconnect-emergency-qr.png');

    expect(ok, isTrue);
    final file = File('${temp.path}/careconnect-emergency-qr.png');
    expect(file.readAsBytesSync(), png);
    expect(shared, hasLength(1));
  });

  test('TC-EMG-279: a share sheet that fails gives false, not a crash', () async {
    messenger.setMockMethodCallHandler(share, (call) async {
      throw PlatformException(code: 'error');
    });
    expect(await saveQrImage(Uint8List(4), 'x.png'), isFalse);
  });

  // ---------- Testing Lead ----------

  test(
      'TC-EMG-303: the share sheet gets the one saved PNG, typed image/png, '
      'and with no temporary folder nothing is shared and the answer is false',
      () async {
    final png = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
    expect(await saveQrImage(png, 'careconnect-emergency-qr.png'), isTrue);
    final args = shared.single.arguments as Map;
    expect(shared.single.method, 'share');
    expect(args['paths'], hasLength(1));
    expect(File(args['paths'][0] as String).readAsBytesSync(), png);
    expect(args['mimeTypes'], ['image/png']);
    expect(args.containsKey('text'), isFalse);

    shared.clear();
    messenger.setMockMethodCallHandler(pathProvider, (call) async {
      throw PlatformException(code: 'no_directory');
    });
    expect(await saveQrImage(png, 'careconnect-emergency-qr.png'), isFalse);
    expect(shared, isEmpty);
  });
}
