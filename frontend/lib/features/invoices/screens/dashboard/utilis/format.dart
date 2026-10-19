import 'package:care_connect_app/features/invoices/models/invoice_models.dart';

String currency(num value) => '\$${value.toDouble().toStringAsFixed(2)}';

String fmt(DateTime d) => d.toLocal().toString().split(' ').first;

String monthShort(int m) => const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ][m - 1];

String labelForStatus(PaymentStatus s) {
  switch (s) {
    case PaymentStatus.pending:
      return 'Pending';
    case PaymentStatus.overdue:
      return 'Overdue';
    case PaymentStatus.pendingInsurance:
      return 'Pending Insurance';
    case PaymentStatus.sent:
      return 'Sent';
    case PaymentStatus.paid:
      return 'Paid';
    case PaymentStatus.partialPayment:
      return 'Partial Payment';
    case PaymentStatus.rejectedInsurance:
      return 'Rejected Insurance';
  }
}
