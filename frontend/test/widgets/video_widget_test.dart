// VideoWidget with the camera plugin channel mocked: with no cameras the
// widget keeps its loading indicator.

import 'package:care_connect_app/widgets/video_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _camera = MethodChannel('plugins.flutter.io/camera');

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_camera, null);
  });

  void mockCameras(List<Map<String, Object>> cameras) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_camera, (call) async {
      if (call.method == 'availableCameras') return cameras;
      return null;
    });
  }

  testWidgets('no cameras keeps the loading indicator', (tester) async {
    mockCameras(const []);
    await tester.pumpWidget(const MaterialApp(home: VideoWidget()));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
