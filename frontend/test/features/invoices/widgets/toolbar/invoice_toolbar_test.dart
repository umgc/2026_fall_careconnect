// Tests for InvoiceToolbar widget
// (lib/features/invoices/widgets/toolbar/invoice_toolbar.dart).
// Pure StatelessWidget — no platform channels or network I/O.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:care_connect_app/features/invoices/widgets/toolbar/invoice_toolbar.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(appBar: AppBar(actions: [child])));

void main() {
  group('InvoiceToolbar – view mode (isEditing=false)', () {
    testWidgets('shows Edit button when not editing', (tester) async {
      // Verifies the Edit button is visible in view mode.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: false,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('Edit'), findsOneWidget);
    });

    testWidgets('shows PDF button when showPdf is true', (tester) async {
      // Verifies the PDF button is present by default.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: false,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('PDF'), findsOneWidget);
    });

    testWidgets('hides PDF button when showPdf is false', (tester) async {
      // Verifies that showPdf=false removes the PDF button.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: false,
        isNew: false,
        showPdf: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('PDF'), findsNothing);
    });

    testWidgets('shows Close button', (tester) async {
      // Verifies the Close button is always present.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: false,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('tapping Edit calls onEdit', (tester) async {
      // Verifies the onEdit callback fires.
      var called = false;
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: false,
        isNew: false,
        onEdit: () => called = true,
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('tapping Close calls onClose', (tester) async {
      // Verifies the onClose callback fires.
      var called = false;
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: false,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () => called = true,
      )));
      await tester.tap(find.text('Close'));
      await tester.pump();
      expect(called, isTrue);
    });
  });

  group('InvoiceToolbar – edit mode (isEditing=true)', () {
    testWidgets('shows Save button when editing', (tester) async {
      // Verifies the Save button is visible in edit mode.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: true,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('shows Cancel label when editing existing invoice', (tester) async {
      // Verifies that isNew=false produces "Cancel" text.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: true,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows Discard label when editing a new invoice', (tester) async {
      // Verifies that isNew=true produces "Discard" text.
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: true,
        isNew: true,
        onEdit: () {},
        onCancel: () {},
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('tapping Save calls onSave', (tester) async {
      // Verifies the onSave callback fires.
      var called = false;
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: true,
        isNew: false,
        onEdit: () {},
        onCancel: () {},
        onSave: () => called = true,
        onPdf: () {},
        onClose: () {},
      )));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('tapping Cancel calls onCancel', (tester) async {
      // Verifies the onCancel callback fires.
      var called = false;
      await tester.pumpWidget(_wrap(InvoiceToolbar(
        isEditing: true,
        isNew: false,
        onEdit: () {},
        onCancel: () => called = true,
        onSave: () {},
        onPdf: () {},
        onClose: () {},
      )));
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(called, isTrue);
    });
  });
}
