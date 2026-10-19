// invoice_ocr_llm_api.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:mime/mime.dart';

import 'package:care_connect_app/services/auth_token_manager.dart';
import 'package:care_connect_app/services/api_service.dart';

import '../models/invoice_models.dart';

class InvoiceResponseDto {
  final Invoice invoice;
  final bool duplicate;
  final String? message;
  final String? duplicateId;
  final String? duplicateInvoiceNumber;

  InvoiceResponseDto({
    required this.invoice,
    required this.duplicate,
    this.message,
    this.duplicateId,
    this.duplicateInvoiceNumber,
  });
}

class InvoiceOcrLlmApi {
  static Future<InvoiceResponseDto?> extractWithLlm({
    List<XFile> images = const [],
    List<String> pdfPaths = const [],
    List<Uint8List> pdfBytes = const [], // <-- 1. PARAMETER ADDED HERE
  }) async {
    final uri = Uri.parse('${ApiConstants.invoices}/extract-llm');
    final headers = await AuthTokenManager.getAuthHeaders();

    final req = http.MultipartRequest('POST', uri)..headers.addAll(headers);

    // Images (handles HEIC -> PNG)
    for (final x in images) {
      final part = await _multipartForImageXFile(x);
      req.files.add(part);
    }

    // PDFs (from paths)
    for (final path in pdfPaths) {
      req.files.add(await http.MultipartFile.fromPath(
        'files',
        path,
        filename: p.basename(path),
        contentType: MediaType('application', 'pdf'),
      ));
    }

    // <-- 2. NEW LOGIC BLOCK ADDED HERE
    // PDFs (from bytes)
    int pdfBytesCounter = 0;
    for (final bytes in pdfBytes) {
      req.files.add(http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: 'upload_${pdfBytesCounter++}.pdf', // Generate a filename
        contentType: MediaType('application', 'pdf'),
      ));
    }
    // END OF NEW LOGIC BLOCK

    final streamed = await req.send().timeout(const Duration(seconds: 180));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw Exception('extract-llm failed: ${resp.statusCode} ${resp.body}');
    }

    final body = jsonDecode(resp.body);

    // New shape: { invoice: {...}, duplicate: bool, message, duplicateId, duplicateInvoiceNumber }
    if (body is Map && body['invoice'] is Map) {
      final inv =
          _mapInvoiceDtoToClient(body['invoice'] as Map<String, dynamic>);
      return InvoiceResponseDto(
        invoice: inv,
        duplicate: body['duplicate'] == true,
        message: body['message'] as String?,
        duplicateId: body['duplicateId'] as String?,
        duplicateInvoiceNumber: body['duplicateInvoiceNumber'] as String?,
      );
    }

    // Backward compatibility
    if (body is Map<String, dynamic>) {
      final inv = _mapInvoiceDtoToClient(body);
      return InvoiceResponseDto(invoice: inv, duplicate: false);
    }

    throw Exception('Unexpected response shape from extract-llm');
  }

  static Future<http.MultipartFile> _multipartForImageXFile(XFile x) async {
    final raw = await x.readAsBytes(); // Uint8List
    final ext = p.extension(x.name).replaceFirst('.', '').toLowerCase();
    final guessMime = x.mimeType ?? lookupMimeType(x.name, headerBytes: raw);

    if (_looksLikeHeic(raw, ext, guessMime)) {
      final png = await _heicBytesToPng(raw);
      final filename = '${p.basenameWithoutExtension(x.name)}.png';
      return http.MultipartFile.fromBytes(
        'files',
        png,
        filename: filename,
        contentType: MediaType('image', 'png'),
      );
    }

    final media = _mediaTypeFromString(guessMime ?? 'image/jpeg');
    final safeName = _normalizedNameForMime(x.name, media);
    return http.MultipartFile.fromBytes(
      'files',
      raw,
      filename: safeName,
      contentType: media,
    );
  }
}

// ---------------------- helpers----------------------

MediaType _mediaTypeFromString(String mime) {
  final parts = mime.split('/');
  if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return MediaType(parts[0], parts[1]);
  }
  return MediaType('application', 'octet-stream');
}

String _normalizedNameForMime(String original, MediaType media) {
  final base = p.basenameWithoutExtension(original);
  final ext = () {
    if (media.type == 'image' && media.subtype == 'png') return '.png';
    if (media.type == 'image' &&
        (media.subtype == 'jpeg' || media.subtype == 'jpg')) return '.jpg';
    if (media.type == 'application' && media.subtype == 'pdf') return '.pdf';
    return p.extension(original).isEmpty ? '.bin' : p.extension(original);
  }();
  return '$base$ext';
}

bool _looksLikeHeic(Uint8List bytes, String? ext, String? mime) {
  final e = (ext ?? '').toLowerCase();
  if (e == 'heic' || e == 'heif' || e == 'heifs') return true;
  final m = (mime ?? '').toLowerCase();
  if (m.contains('heic') || m.contains('heif')) return true;

  if (bytes.length >= 12) {
    final sig = String.fromCharCodes(bytes.sublist(4, 12));
    if (sig.startsWith('ftypheic') ||
        sig.startsWith('ftypheix') ||
        sig.startsWith('ftyphevc') ||
        sig.startsWith('ftypmif1') ||
        sig.startsWith('ftypmsf1')) {
      return true;
    }
  }
  return false;
}

Future<Uint8List> _heicBytesToPng(Uint8List heic) async {
  final codec = await ui.instantiateImageCodec(heic);
  final frame = await codec.getNextFrame();
  final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw Exception('Failed to convert HEIC to PNG');
  }
  return byteData.buffer.asUint8List();
}

// Maps server InvoiceDto -> client Invoice model
Invoice _mapInvoiceDtoToClient(Map<String, dynamic> j) {
  T? m<T>(String k) => j[k] as T?;

  final providerMap = j['provider'] as Map<String, dynamic>?;
  final patientMap = j['patient'] as Map<String, dynamic>?;
  final datesMap = j['dates'] as Map<String, dynamic>?;

  final servicesList = (j['services'] as List?) ?? const [];
  final historyList = (j['history'] as List?) ?? const [];
  final paymentsList = (j['payments'] as List?) ?? const [];
  final paymentRefs = j['paymentReferences'] as Map<String, dynamic>?;
  final checkPayable = j['checkPayableTo'] as Map<String, dynamic>?;

  final nowIso = DateTime.now().toIso8601String();

  final provider = ProviderInfo(
    name: _str(providerMap?['name']),
    address: _str(providerMap?['address']),
    phone: _str(providerMap?['phone']),
    email: providerMap?['email'] as String?,
  );

  final patient = PatientInfo(
    name: _str(patientMap?['name']),
    address: patientMap?['address'] as String?,
    accountNumber: patientMap?['accountNumber'] as String?,
    billingAddress: patientMap?['billingAddress'] as String?,
  );

  final dates = InvoiceDates(
    statementDate: _parseDate(datesMap?['statementDate']) ?? DateTime.now(),
    dueDate: _parseDate(datesMap?['dueDate']) ?? DateTime.now(),
    paidDate: _parseDate(datesMap?['paidDate']),
  );

  final services = servicesList.map<ServiceLine>((e) {
    final m = e as Map<String, dynamic>;
    return ServiceLine(
      description: m['description'] as String?,
      serviceCode: m['serviceCode'] as String?,
      serviceDate: _parseDate(m['serviceDate']),
      charge: _asDouble(m['charge']),
      patientBalance: _asDouble(m['patientBalance']),
      insuranceAdjustments: _asDouble(m['insuranceAdjustments']),
    );
  }).toList();

  final amountsMap = j['amounts'] as Map<String, dynamic>?;
  final amounts = Amounts(
    totalCharges: _asDouble(amountsMap?['totalCharges']),
    totalAdjustments: _asDouble(amountsMap?['totalAdjustments']),
    total: _asDouble(amountsMap?['total']),
    amountDue: _asDouble(amountsMap?['amountDue']),
  );

  final refs = PaymentReferences(
    paymentLink: paymentRefs?['paymentLink'] as String?,
    qrCodeUrl: paymentRefs?['qrCodeUrl'] as String?,
    notes: paymentRefs?['notes'] as String?,
    supportedMethods: _stringList(paymentRefs?['supportedMethods']),
  );

  final check = (checkPayable != null)
      ? CheckPayableTo(
          name: _str(checkPayable['name']),
          address: _str(checkPayable['address']),
          reference: _str(checkPayable['reference']),
        )
      : null;

  final history = historyList.map<HistoryEntry>((e) {
    final m = e as Map<String, dynamic>;
    return HistoryEntry(
      userId: _str(m['userId']),
      action: _str(m['action']),
      details: _str(m['details']),
      version: (m['version'] as num?)?.toInt() ?? 1,
      changes: _str(m['changes']),
      timestamp: _str(m['timestamp']),
    );
  }).toList();

  final payments = paymentsList.map<PaymentRecord>((e) {
    final m = e as Map<String, dynamic>;
    return PaymentRecord(
      id: _str(m['id']),
      confirmationNumber: _str(m['confirmationNumber']),
      date: _parseDate(m['date']) ?? DateTime.now(),
      methodKey: _str(m['methodKey']),
      amountPaid: (_asDouble(m['amountPaid']) ?? 0).toDouble(),
      planEnabled: m['planEnabled'] as bool? ?? false,
      planDurationMonths: (m['planDurationMonths'] as num?)?.toInt(),
    );
  }).toList();

  final recActions = _stringList(j['recommendedActions']);

  return Invoice(
    id: m<String>('id') ?? '',
    invoiceNumber: m<String>('invoiceNumber') ?? '',
    provider: provider,
    patient: patient,
    dates: dates,
    services: services,
    paymentStatus: _paymentStatusFromWire(m<String>('paymentStatus')),
    billedToInsurance: j['billedToInsurance'] as bool? ?? false,
    amounts: amounts,
    paymentReferences: refs,
    checkPayableTo: check,
    createdAt: m<String>('createdAt') ?? nowIso,
    updatedAt: m<String>('updatedAt') ?? nowIso,
    createdBy: m<String>('createdBy') ?? 'system',
    updatedBy: m<String>('updatedBy') ?? 'system',
    documentLink: m<String>('documentLink'),
    history: history,
    payments: payments,
    aiSummary: m<String>('aiSummary'),
    recommendedActions: recActions,
  );
}

String _str(Object? v) => (v as String?) ?? '';

DateTime? _parseDate(Object? v) {
  if (v == null) return null;
  if (v is String && v.isNotEmpty) {
    try {
      return DateTime.parse(v);
    } catch (_) {
      return null;
    }
  }
  return null;
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

List<String> _stringList(Object? v) {
  if (v is List) return v.map((e) => e.toString()).toList();
  return const <String>[];
}

PaymentStatus _paymentStatusFromWire(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'pending':
      return PaymentStatus.pending;
    case 'overdue':
      return PaymentStatus.overdue;
    case 'pendinginsurance':
      return PaymentStatus.pendingInsurance;
    case 'sent':
      return PaymentStatus.sent;
    case 'paid':
      return PaymentStatus.paid;
    case 'partialpayment':
      return PaymentStatus.partialPayment;
    case 'rejectedinsurance':
      return PaymentStatus.rejectedInsurance;
    default:
      return PaymentStatus.pending;
  }
}
