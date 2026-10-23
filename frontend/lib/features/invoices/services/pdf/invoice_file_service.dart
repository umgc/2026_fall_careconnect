// services/invoice_file_service.dart
import 'package:url_launcher/url_launcher_string.dart';

class InvoiceFileService {
  static Future<void> openInvoicePdf(String documentLink) async {
    if (await canLaunchUrlString(documentLink)) {
      await launchUrlString(documentLink, mode: LaunchMode.externalApplication);
    }
  }
}
