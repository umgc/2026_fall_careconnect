// lib/features/invoices/services/excel_service.dart

// This conditional import is the key: it loads the correct helper file at compile time.
import 'package:care_connect_app/features/invoices/services/excel/save_service_stub.dart'
    if (dart.library.io) 'package:care_connect_app/features/invoices/services/excel/save_service_mobile.dart'
    if (dart.library.html) 'package:care_connect_app/features/invoices/services/excel/save_service_web.dart';

import 'package:care_connect_app/features/invoices/models/invoice_models.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Make sure this import is here

class ExcelService {
  ExcelService._privateConstructor();
  static final ExcelService instance = ExcelService._privateConstructor();

  Future<void> exportInvoices(
    List<Invoice> invoices,
    BuildContext context,
  ) async {
    // ... (no changes in the first part of the function)
    if (invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No invoices to export.')),
      );
      return;
    }

    try {
      // ... (Excel generation logic is unchanged)
      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];

      final List<String> headers = [
        'Invoice ID',
        'Patient',
        'Provider',
        'Service Date',
        'Due Date',
        'Status',
        'Total Amount',
        'Amount Due',
      ];
      sheet.appendRow(headers.map((header) => TextCellValue(header)).toList());

      for (final invoice in invoices) {
        final List<CellValue> row = [
          TextCellValue(invoice.id),
          TextCellValue(invoice.patient.name),
          TextCellValue(invoice.provider.name),
          DateCellValue(
              year: invoice.dates.statementDate.year,
              month: invoice.dates.statementDate.month,
              day: invoice.dates.statementDate.day),
          DateCellValue(
              year: invoice.dates.dueDate.year,
              month: invoice.dates.dueDate.month,
              day: invoice.dates.dueDate.day),
          TextCellValue(_formatPaymentStatus(invoice.paymentStatus)),
          DoubleCellValue(invoice.amounts.total ?? 0),
          DoubleCellValue(invoice.amounts.amountDue ?? 0),
        ];
        sheet.appendRow(row);
      }

      for (var i = 0; i < headers.length; i++) {
        sheet.setColumnAutoFit(i);
      }
      final timestamp =
          DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final String fileName = 'Invoices_Export_$timestamp.xlsx';
      final fileBytes = excel.save(fileName: fileName);

      if (fileBytes != null && !kIsWeb) {
        // --- THIS IS THE FIX ---
        // Create a filename-safe timestamp (e.g., '2025-10-10_15-18-18')

        await saveAndOpenFile(fileBytes, fileName, context);
      } else {
        throw Exception('Could not save Excel file.');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting file: $e')),
      );
    }
  }

  String _formatPaymentStatus(PaymentStatus status) {
    // This helper function is unchanged
    switch (status) {
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.rejectedInsurance:
        return 'Rejected by Insurance';
      default:
        return 'Unknown';
    }
  }
}
