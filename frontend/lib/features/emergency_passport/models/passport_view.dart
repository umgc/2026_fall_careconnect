// The signed-in patient's own passport, as GET /v1/api/passport returns it
// (PassportView). Only the parts the QR screen (design screen 2) uses.

/// The five sections a patient can share, in the order the screen lists them.
enum PassportField {
  bloodType('BLOOD_TYPE', 'Blood type'),
  allergies('ALLERGIES', 'Allergies'),
  medications('MEDICATIONS', 'Medications'),
  emergencyContact('EMERGENCY_CONTACT', 'Emergency contact'),
  chronicConditions('CHRONIC_CONDITIONS', 'Chronic conditions');

  const PassportField(this.key, this.label);
  final String key;
  final String label;
}

/// The patient's QR code as the server knows it. Never carries the code itself.
class QrCodeStatus {
  final DateTime createdAt;
  final DateTime? lastScannedAt;

  const QrCodeStatus({required this.createdAt, this.lastScannedAt});
}

class PassportView {
  final String name;
  final Map<PassportField, bool> sharing;
  final int allergyCount;
  final int medicationCount;

  /// Null when the patient never made a code or turned it off.
  final QrCodeStatus? code;

  /// An active code and at least one shared section.
  final bool ready;

  const PassportView({
    required this.name,
    required this.sharing,
    this.allergyCount = 0,
    this.medicationCount = 0,
    this.code,
    this.ready = false,
  });

  bool isShared(PassportField f) => sharing[f] ?? false;

  factory PassportView.fromJson(Map<String, dynamic> json) {
    final rawSharing = json['sharing'];
    final sharing = <PassportField, bool>{
      for (final f in PassportField.values)
        f: rawSharing is Map && rawSharing[f.key] == true,
    };

    QrCodeStatus? code;
    final token = json['token'];
    if (token is Map && token['active'] == true) {
      final created = DateTime.tryParse('${token['createdAt']}');
      if (created != null) {
        final scanned = token['lastScannedAt'];
        code = QrCodeStatus(
          createdAt: created,
          lastScannedAt: scanned is String ? DateTime.tryParse(scanned) : null,
        );
      }
    }

    int count(String key) => json[key] is List ? (json[key] as List).length : 0;

    return PassportView(
      name: (json['name'] ?? '').toString(),
      sharing: sharing,
      allergyCount: count('allergies'),
      medicationCount: count('medications'),
      code: code,
      ready: json['ready'] == true,
    );
  }
}

/// What POST /v1/api/passport/token returns. The only time the code is given.
class NewQrCode {
  final String token;
  final String url;
  final DateTime createdAt;

  const NewQrCode(
      {required this.token, required this.url, required this.createdAt});

  factory NewQrCode.fromJson(Map<String, dynamic> json) => NewQrCode(
        token: (json['token'] ?? '').toString(),
        url: scanLink((json['url'] ?? '').toString()),
        createdAt:
            DateTime.tryParse('${json['createdAt']}') ?? DateTime.now().toUtc(),
      );
}

/// The web app uses # links, so {site}/passport/{code} has to become
/// {site}/#/passport/{code} or the scan page won't open. A link that already
/// has the # is left alone.
String scanLink(String url) {
  if (url.contains('/#/')) return url;
  final i = url.lastIndexOf('/passport/');
  if (i < 0) return url;
  return '${url.substring(0, i)}/#${url.substring(i)}';
}
