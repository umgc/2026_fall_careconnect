import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../services/user_role_storage_service.dart';

/// A QR code kept on this device. The server gives the code only once, so the
/// app keeps it to show the QR again later.
class StoredQrCode {
  final String url;
  final DateTime createdAt;

  const StoredQrCode({required this.url, required this.createdAt});
}

/// Keeps the patient's current QR code in secure storage, one per patient.
class QrCodeStore {
  QrCodeStore({FlutterSecureStorage? storage, Future<int?> Function()? patientId})
      : _storage = storage ??
            const FlutterSecureStorage(webOptions: WebOptions.defaultOptions),
        _patientId = patientId ?? UserRoleStorageService.instance.getPatientId;

  final FlutterSecureStorage _storage;
  final Future<int?> Function() _patientId;

  Future<String?> _key() async {
    final id = await _patientId();
    return id == null ? null : 'cc12_emergency_qr_$id';
  }

  Future<StoredQrCode?> read() async {
    try {
      final key = await _key();
      if (key == null) return null;
      final raw = await _storage.read(key: key);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final created = DateTime.tryParse('${json['createdAt']}');
      final url = json['url'];
      if (created == null || url is! String || url.isEmpty) return null;
      return StoredQrCode(url: url, createdAt: created);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(StoredQrCode code) async {
    try {
      final key = await _key();
      if (key == null) return;
      await _storage.write(
        key: key,
        value: jsonEncode({
          'url': code.url,
          'createdAt': code.createdAt.toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // Not kept: the QR still shows now; next time the screen offers a new code.
    }
  }

  /// Forgets this patient's code, after it is turned off.
  Future<void> clear() async {
    try {
      final key = await _key();
      if (key == null) return;
      await _storage.delete(key: key);
    } catch (_) {
      // Nothing kept, or storage unavailable: the code is off on the server
      // either way, and read() never shows a code the server says is off.
    }
  }
}
