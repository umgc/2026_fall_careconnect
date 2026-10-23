// Tests for save_service_stub.dart
// (lib/features/invoices/services/excel/save_service_stub.dart).
// The stub throws UnsupportedError because file saving is not supported on
// platforms that don't match mobile (dart:io) or web (package:web).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/services/excel/save_service_stub.dart';

void main() {
  group('saveAndOpenFile stub', () {
    testWidgets('throws UnsupportedError', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));
      expect(
        () => saveAndOpenFile([1, 2, 3], 'test.xlsx', context),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('throws UnsupportedError with empty bytes', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));
      expect(
        () => saveAndOpenFile([], 'empty.xlsx', context),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('error message mentions platform support', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));
      try {
        await saveAndOpenFile([1], 'test.xlsx', context);
        fail('Expected UnsupportedError');
      } on UnsupportedError catch (e) {
        expect(e.message, contains('not supported'));
      }
    });

    testWidgets('throws UnsupportedError with different file name',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));
      expect(
        () => saveAndOpenFile([0xFF, 0xD8], 'photo.jpg', context),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('throws UnsupportedError with large byte list',
        (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));
      final largeBytes = List<int>.filled(10000, 0);
      expect(
        () => saveAndOpenFile(largeBytes, 'large.bin', context),
        throwsA(isA<UnsupportedError>()),
      );
    });

    testWidgets('returns Future that completes with error', (tester) async {
      await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox())));
      final context = tester.element(find.byType(SizedBox));
      expect(
        saveAndOpenFile([1, 2, 3], 'test.xlsx', context),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
