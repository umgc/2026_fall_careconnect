import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Sentinel to allow nullable fields to be cleared via copyWith
const Object _unset = Object();

@immutable
class ProviderInfo {
  final String name;
  final String address;
  final String phone;
  final String? email;

  const ProviderInfo({
    required this.name,
    required this.address,
    required this.phone,
    this.email,
  });

  ProviderInfo copyWith({
    String? name,
    String? address,
    String? phone,
    Object? email = _unset, // pass null to clear, omit to keep
  }) {
    return ProviderInfo(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: identical(email, _unset) ? this.email : email as String?,
    );
  }
}

@immutable
class PatientInfo {
  final String name;
  final String? address;
  final String? accountNumber;
  final String? billingAddress;

  const PatientInfo({
    required this.name,
    this.address,
    this.accountNumber,
    this.billingAddress,
  });

  PatientInfo copyWith({
    String? name,
    Object? address = _unset,
    Object? accountNumber = _unset,
    Object? billingAddress = _unset,
  }) {
    return PatientInfo(
      name: name ?? this.name,
      address: identical(address, _unset) ? this.address : address as String?,
      accountNumber: identical(accountNumber, _unset)
          ? this.accountNumber
          : accountNumber as String?,
      billingAddress: identical(billingAddress, _unset)
          ? this.billingAddress
          : billingAddress as String?,
    );
  }
}

@immutable
class InvoiceDates {
  // Stored as DateTime; format as yyyy-MM-dd at the edges if needed
  final DateTime statementDate;
  final DateTime dueDate;
  final DateTime? paidDate;

  const InvoiceDates({
    required this.statementDate,
    required this.dueDate,
    this.paidDate,
  });

  InvoiceDates copyWith({
    DateTime? statementDate,
    DateTime? dueDate,
    Object? paidDate = _unset, // pass null to clear, omit to keep
  }) {
    return InvoiceDates(
      statementDate: statementDate ?? this.statementDate,
      dueDate: dueDate ?? this.dueDate,
      paidDate:
          identical(paidDate, _unset) ? this.paidDate : paidDate as DateTime?,
    );
  }
}

@immutable
class ServiceLine {
  final String? description;
  final String? serviceCode;
  final DateTime? serviceDate;
  final double? charge;
  final double? patientBalance;
  final double? insuranceAdjustments;

  const ServiceLine({
    this.description,
    this.serviceCode,
    this.serviceDate,
    this.charge,
    this.patientBalance,
    this.insuranceAdjustments,
  });

  ServiceLine copyWith({
    Object? description = _unset,
    Object? serviceCode = _unset,
    Object? serviceDate = _unset,
    Object? charge = _unset,
    Object? patientBalance = _unset,
    Object? insuranceAdjustments = _unset,
  }) {
    return ServiceLine(
      description: identical(description, _unset)
          ? this.description
          : description as String?,
      serviceCode: identical(serviceCode, _unset)
          ? this.serviceCode
          : serviceCode as String?,
      serviceDate: identical(serviceDate, _unset)
          ? this.serviceDate
          : serviceDate as DateTime?,
      charge: identical(charge, _unset) ? this.charge : charge as double?,
      patientBalance: identical(patientBalance, _unset)
          ? this.patientBalance
          : patientBalance as double?,
      insuranceAdjustments: identical(insuranceAdjustments, _unset)
          ? this.insuranceAdjustments
          : insuranceAdjustments as double?,
    );
  }
}

@immutable
class Amounts {
  final double? totalCharges;
  final double? totalAdjustments;
  final double? total;
  final double? amountDue;

  const Amounts({
    this.totalCharges,
    this.totalAdjustments,
    this.total,
    this.amountDue,
  });

  Amounts copyWith({
    Object? totalCharges = _unset,
    Object? totalAdjustments = _unset,
    Object? total = _unset,
    Object? amountDue = _unset,
  }) {
    return Amounts(
      totalCharges: identical(totalCharges, _unset)
          ? this.totalCharges
          : totalCharges as double?,
      totalAdjustments: identical(totalAdjustments, _unset)
          ? this.totalAdjustments
          : totalAdjustments as double?,
      total: identical(total, _unset) ? this.total : total as double?,
      amountDue:
          identical(amountDue, _unset) ? this.amountDue : amountDue as double?,
    );
  }
}

enum PaymentStatus {
  pending,
  overdue,
  pendingInsurance,
  sent,
  paid,
  partialPayment,
  rejectedInsurance,
}

@immutable
class PaymentReferences {
  final String? paymentLink;
  final String? qrCodeUrl;
  final String? notes;
  final UnmodifiableListView<String> supportedMethods;

  PaymentReferences({
    this.paymentLink,
    this.qrCodeUrl,
    this.notes,
    required List<String> supportedMethods,
  }) : supportedMethods =
            UnmodifiableListView(List<String>.from(supportedMethods));

  PaymentReferences copyWith({
    Object? paymentLink = _unset,
    Object? qrCodeUrl = _unset,
    Object? notes = _unset,
    List<String>? supportedMethods,
  }) {
    return PaymentReferences(
      paymentLink: identical(paymentLink, _unset)
          ? this.paymentLink
          : paymentLink as String?,
      qrCodeUrl:
          identical(qrCodeUrl, _unset) ? this.qrCodeUrl : qrCodeUrl as String?,
      notes: identical(notes, _unset) ? this.notes : notes as String?,
      supportedMethods: supportedMethods ?? this.supportedMethods,
    );
  }
}

@immutable
class CheckPayableTo {
  final String name;
  final String address;
  final String reference;

  const CheckPayableTo({
    required this.name,
    required this.address,
    required this.reference,
  });

  CheckPayableTo copyWith({
    String? name,
    String? address,
    String? reference,
  }) {
    return CheckPayableTo(
      name: name ?? this.name,
      address: address ?? this.address,
      reference: reference ?? this.reference,
    );
  }
}

@immutable
class HistoryEntry {
  final int version;
  final String changes;
  final String userId;
  final String action;
  final String details;
  final String timestamp; // keep String if API returns it as String

  const HistoryEntry({
    required this.userId,
    required this.action,
    required this.details,
    required this.version,
    required this.changes,
    required this.timestamp,
  });
}

@immutable
class Invoice {
  final String id;
  final String invoiceNumber;

  final ProviderInfo provider;
  final PatientInfo patient;
  final InvoiceDates dates;
  final UnmodifiableListView<ServiceLine> services;

  final PaymentStatus paymentStatus;
  final bool billedToInsurance;

  final Amounts amounts;
  final PaymentReferences paymentReferences;
  final CheckPayableTo? checkPayableTo;

  final String createdAt;
  final String updatedAt;
  final String createdBy;
  final String updatedBy;

  final String? documentLink;
  final UnmodifiableListView<HistoryEntry> history;

  final String? aiSummary;
  final UnmodifiableListView<String>? recommendedActions;
  final UnmodifiableListView<PaymentRecord>? payments;
  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.provider,
    required this.patient,
    required this.dates,
    List<ServiceLine>? services,
    required this.paymentStatus,
    required this.billedToInsurance,
    required this.amounts,
    required this.paymentReferences,
    this.checkPayableTo,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.updatedBy,
    this.documentLink,
    List<HistoryEntry>? history,
    required List<PaymentRecord>? payments,
    this.aiSummary,
    List<String>? recommendedActions,
  })  : services =
            UnmodifiableListView(List<ServiceLine>.from(services ?? const [])),
        payments = UnmodifiableListView(
            List<PaymentRecord>.from(payments ?? const [])),
        history =
            UnmodifiableListView(List<HistoryEntry>.from(history ?? const [])),
        recommendedActions = recommendedActions == null
            ? null
            : UnmodifiableListView(List<String>.from(recommendedActions));

  Invoice copyWith({
    ProviderInfo? provider,
    PatientInfo? patient,
    InvoiceDates? dates,
    List<ServiceLine>? services,
    PaymentStatus? paymentStatus,
    bool? billedToInsurance,
    Amounts? amounts,
    PaymentReferences? paymentReferences,
    Object? checkPayableTo = _unset, // pass null to clear
    String? updatedAt,
    List<HistoryEntry>? history,
    Object? aiSummary = _unset, // pass null to clear
    Object? recommendedActions = _unset, // pass null to clear
    String? updatedBy, // allow changing updatedBy
    Object? documentLink = _unset, // pass null to clear
    List<PaymentRecord>? payments,
  }) {
    return Invoice(
      id: id,
      invoiceNumber: invoiceNumber,
      provider: provider ?? this.provider,
      patient: patient ?? this.patient,
      dates: dates ?? this.dates,
      services: services != null
          ? UnmodifiableListView(List<ServiceLine>.from(services))
          : this.services,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      billedToInsurance: billedToInsurance ?? this.billedToInsurance,
      amounts: amounts ?? this.amounts,
      paymentReferences: paymentReferences ?? this.paymentReferences,
      checkPayableTo: identical(checkPayableTo, _unset)
          ? this.checkPayableTo
          : checkPayableTo as CheckPayableTo?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      documentLink: identical(documentLink, _unset)
          ? this.documentLink
          : documentLink as String?,
      history: history != null
          ? UnmodifiableListView(List<HistoryEntry>.from(history))
          : this.history,
      payments: payments ?? this.payments,
      aiSummary:
          identical(aiSummary, _unset) ? this.aiSummary : aiSummary as String?,
      recommendedActions: identical(recommendedActions, _unset)
          ? this.recommendedActions
          : (recommendedActions == null
              ? null
              : UnmodifiableListView(
                  List<String>.from(recommendedActions as List<String>))),
    );
  }
}

extension InvoiceFactories on Invoice {
  static Invoice empty() {
    final now = DateTime.now();
    String iso(DateTime d) => d.toIso8601String();

    return Invoice(
      id: 'local-${now.millisecondsSinceEpoch}', // temporary client id
      invoiceNumber: '',
      provider: const ProviderInfo(
        name: '',
        address: '',
        phone: '',
        email: null,
      ),
      patient: const PatientInfo(
        name: '',
        address: null,
        accountNumber: null,
        billingAddress: null,
      ),
      dates: InvoiceDates(
        statementDate: now,
        dueDate: now.add(const Duration(days: 30)),
        paidDate: null,
      ),
      services: const <ServiceLine>[],
      paymentStatus: PaymentStatus.pending,
      billedToInsurance: false,
      amounts: const Amounts(
        totalCharges: 0,
        totalAdjustments: 0,
        total: 0,
        amountDue: 0,
      ),
      paymentReferences: PaymentReferences(
        paymentLink: null,
        qrCodeUrl: null,
        notes: null,
        supportedMethods: const <String>[],
      ),
      checkPayableTo: null,
      createdAt: iso(now),
      updatedAt: iso(now),
      createdBy: 'system',
      updatedBy: 'system',
      documentLink: null, // not known until upload
      history: const <HistoryEntry>[],
      aiSummary: null,
      recommendedActions: const <String>[],
      payments: const <PaymentRecord>[],
    );
  }
}

@immutable
class PaymentRecord {
  final String id; // server generated UUID or client temp
  final String confirmationNumber;
  final DateTime date;
  final String methodKey; // 'check' | 'credit_card' | 'online' | 'telephone'
  final double amountPaid;
  final bool planEnabled;
  final int? planDurationMonths;

  const PaymentRecord({
    required this.id,
    required this.confirmationNumber,
    required this.date,
    required this.methodKey,
    required this.amountPaid,
    this.planEnabled = false,
    this.planDurationMonths,
  });

  PaymentRecord copyWith({
    String? id,
    String? confirmationNumber,
    DateTime? date,
    String? methodKey,
    double? amountPaid,
    bool? planEnabled,
    int? planDurationMonths,
  }) =>
      PaymentRecord(
        id: id ?? this.id,
        confirmationNumber: confirmationNumber ?? this.confirmationNumber,
        date: date ?? this.date,
        methodKey: methodKey ?? this.methodKey,
        amountPaid: amountPaid ?? this.amountPaid,
        planEnabled: planEnabled ?? this.planEnabled,
        planDurationMonths: planDurationMonths ?? this.planDurationMonths,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'confirmationNumber': confirmationNumber,
        'date': date.toIso8601String(),
        'methodKey': methodKey,
        'amountPaid': amountPaid,
        'planEnabled': planEnabled,
        'planDurationMonths': planDurationMonths,
      };

  static PaymentRecord fromJson(Map<String, dynamic> j) => PaymentRecord(
        id: j['id'] as String,
        confirmationNumber: j['confirmationNumber'] as String,
        date: DateTime.parse(j['date'] as String),
        methodKey: j['methodKey'] as String,
        amountPaid: (j['amountPaid'] as num).toDouble(),
        planEnabled: j['planEnabled'] as bool? ?? false,
        planDurationMonths: j['planDurationMonths'] as int?,
      );
}
