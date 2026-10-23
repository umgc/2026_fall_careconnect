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
  static const _prefix = 'cc12_emergency_qr_';

  /// Removes every QR code kept on this device, for every patient. Called
  /// when anyone signs out: the code is the only credential for a passport,
  /// so it must not outlive the session on a shared device (DEF-EMG-11).
  /// A picture the patient saved keeps working; the screen offers a new code
  /// after the next sign-in. Never throws, so it can't block a sign-out.
  static Future<void> clearAll({FlutterSecureStorage? storage}) async {
    try {
      final store = storage ??
          const FlutterSecureStorage(webOptions: WebOptions.defaultOptions);
      final all = await store.readAll();
      for (final key in all.keys.where((k) => k.startsWith(_prefix))) {
        await store.delete(key: key);
      }
    } catch (_) {
      // Storage unavailable: nothing more can be done from here.
    }
  }

  QrCodeStore({FlutterSecureStorage? storage, Future<int?> Function()? patientId})
      : _storage = storage ??
            const FlutterSecureStorage(webOptions: WebOptions.defaultOptions),
        _patientId = patientId ?? UserRoleStorageService.instance.getPatientId;

  final FlutterSecureStorage _storage;
  final Future<int?> Function() _patientId;

  Future<String?> _key() async {
    final id = await _patientId();
    return id == null ? null : '$_prefix$id';
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
