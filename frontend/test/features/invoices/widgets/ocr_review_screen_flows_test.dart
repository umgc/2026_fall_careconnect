// OcrReviewScreen (lib/features/invoices/widgets/ocr_review_screen.dart) with
// the native OCR channel faked: results with boxes and QR codes, box toggle,
// re-run, remove, retry after a failure, and finishing with the edited text.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:care_connect_app/features/invoices/widgets/ocr_review_screen.dart';

const _ocr = MethodChannel('care_connect/ocr');

Map<String, dynamic> _result(String path, String text) => {
      'path': path,
      'text': text,
      'lines': [
        {
          'text': text,
          'box': {'l': 0.1, 't': 0.1, 'w': 0.5, 'h': 0.1},
        },
      ],
      'qrcodes': [
        {
          'value': 'https://pay.example',
          'box': {'l': 0.6, 't': 0.6, 'w': 0.2, 'h': 0.2},
        },
        {'value': ''},
      ],
    };

void main() {
  late bool fail;
  late int calls;

  setUp(() {
    fail = false;
    calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocr, (call) async {
      calls++;
      if (fail) throw PlatformException(code: 'ocr');
      final paths = ((call.arguments as Map)['paths'] as List).cast<String>();
      return [for (final p in paths) _result(p, 'text for $p (#$calls)')];
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_ocr, null);
  });

  Future<List<Map<String, String>>?> pump(
    WidgetTester tester,
    List<XFile> images,
    Future<void> Function() interact,
  ) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    List<Map<String, String>>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await Navigator.of(context)
                .push<List<Map<String, String>>>(MaterialPageRoute(
              builder: (_) => OcrReviewScreen(images: images),
            ));
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    return result;
  }

  testWidgets('shows OCR text and QR chips, toggles boxes, re-runs, removes',
      (tester) async {
    final result = await pump(
      tester,
      [XFile('/no/such/a.jpg'), XFile('/no/such/b.jpg')],
      () async {
        expect(find.byType(InputChip), findsNWidgets(4));
        expect(find.text('(empty)'), findsNWidgets(2));
        await tester.tap(find.byType(InputChip).first);

        await tester.tap(find.byTooltip('Hide boxes'));
        await tester.pump();
        expect(find.byTooltip('Show boxes'), findsOneWidget);

        await tester.tap(find.byTooltip('Re-run OCR').first);
        await tester.pumpAndSettle();
        expect(calls, 2);

        await tester.tap(find.byTooltip('Remove').last);
        await tester.pumpAndSettle();
        expect(find.byType(Card), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'edited');
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      },
    );
    expect(result, [
      {'path': '/no/such/a.jpg', 'text': 'edited'},
    ]);
  });

  testWidgets('a failed OCR offers retry; a failed re-run keeps text',
      (tester) async {
    fail = true;
    await pump(tester, [XFile('/no/such/a.jpg')], () async {
      expect(find.text('OCR failed. Tap Retry.'), findsOneWidget);
      await tester.tap(find.byTooltip('Re-run OCR'));
      await tester.pumpAndSettle();

      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('OCR failed. Tap Retry.'), findsNothing);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('No images'), findsOneWidget);
    });
  });
}
