// Page-title tests for ReviewPhotosScreen (lib/features/invoices/widgets/review_photos_screen.dart).
// Setup copied from review_photos_screen_test.dart; adds the page-title
// checks (WCAG 2.4.2) for this PR's TitledMaterialPageRoute changes.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:care_connect_app/features/invoices/widgets/review_photos_screen.dart';
import '../../../helpers/titled_route_probe.dart';

Widget _wrap({List<XFile> photos = const []}) => MaterialApp(
    navigatorObservers: [probe],
    home: ReviewPhotosScreen(initialPhotos: photos));

TitledRouteProbe probe = TitledRouteProbe();

void main() {
  setUp(() => probe = TitledRouteProbe());

  testWidgets('tapping a PDF opens a page titled "PDF Viewer"', (tester) async {
    final pdf = XFile.fromData(Uint8List.fromList([37, 80, 68, 70]),
        name: 'invoice.pdf', path: 'invoice.pdf', mimeType: 'application/pdf');
    await tester.pumpWidget(_wrap(photos: [pdf]));
    await tester.pump();
    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
    expect(
        await probe.tapAndReadTitle(
            tester, find.byIcon(Icons.picture_as_pdf_rounded)),
        'PDF Viewer');
  });
}
