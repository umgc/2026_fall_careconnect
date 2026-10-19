import 'package:care_connect_app/features/invoices/models/invoice_models.dart';

class Metrics {
  final int totalCount;
  final double totalAmount;
  final double pendingAmount;
  final int overdueCount;
  final double paidAmount;
  const Metrics({
    required this.totalCount,
    required this.totalAmount,
    required this.pendingAmount,
    required this.overdueCount,
    required this.paidAmount,
  });
}

Metrics computeMetrics(List<Invoice> invoices) {
  final now = DateTime.now();
  double sum(Invoice i) =>
      (i.amounts.amountDue ?? i.amounts.total ?? 0).toDouble();

  final total = invoices.fold<double>(0, (s, i) => s + sum(i));
  final pending = invoices
      .where((i) => i.paymentStatus == PaymentStatus.pending)
      .fold<double>(0, (s, i) => s + sum(i));
  final overdueCount = invoices
      .where((i) =>
          i.paymentStatus != PaymentStatus.paid &&
          i.dates.dueDate.isBefore(now))
      .length;
  final paid = invoices
      .where((i) => i.paymentStatus == PaymentStatus.paid)
      .fold<double>(0, (s, i) => s + sum(i));

  return Metrics(
    totalCount: invoices.length,
    totalAmount: total,
    pendingAmount: pending,
    overdueCount: overdueCount,
    paidAmount: paid,
  );
}
