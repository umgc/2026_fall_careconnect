import 'dart:convert';
import 'package:http/http.dart' as http;

/// Super-light DTO that only includes fields your UI uses right now.
class PatientData {
  final String id, mrn, fullName, sex, moodLabel, moodEmoji;
  final int age;
  final DateTime? lastCheckIn;

  final List<String> diagnoses, allergies, emergencyPhones;
  final int? heartRate, bpSys, bpDia, oxygen;
  final double? tempF;

  // Pain snapshot for PainLevelCard
  final int? painCurrent, dizziness, fatigue;
  final String? painLocation;

  // Raw lists you’ll map to your existing widgets
  final List<Map<String, dynamic>> symptoms;
  final List<Map<String, dynamic>> medications;
  final List<Map<String, dynamic>> checkIns;

  PatientData({
    required this.id,
    required this.mrn,
    required this.fullName,
    required this.sex,
    required this.age,
    required this.moodLabel,
    required this.moodEmoji,
    required this.lastCheckIn,
    required this.diagnoses,
    required this.allergies,
    required this.emergencyPhones,
    required this.heartRate,
    required this.bpSys,
    required this.bpDia,
    required this.oxygen,
    required this.tempF,
    required this.painCurrent,
    required this.painLocation,
    required this.dizziness,
    required this.fatigue,
    required this.symptoms,
    required this.medications,
    required this.checkIns,
  });

  factory PatientData.fromJson(Map<String, dynamic> j) {
    final v = (j['vitals'] ?? {}) as Map<String, dynamic>;
    final p = (j['pain'] ?? {}) as Map<String, dynamic>;
    return PatientData(
      id: j['id'] ?? '',
      mrn: j['mrn'] ?? '',
      fullName: j['fullName'] ?? '',
      sex: j['sex'] ?? '',
      age: (j['age'] ?? 0) as int,
      moodLabel: j['currentMoodLabel'] ?? '—',
      moodEmoji: j['currentMoodEmoji'] ?? '🙂',
      lastCheckIn:
          j['lastCheckIn'] != null ? DateTime.tryParse(j['lastCheckIn']) : null,
      diagnoses: (j['diagnoses'] as List?)?.cast<String>() ?? const [],
      allergies: (j['allergies'] as List?)?.cast<String>() ?? const [],
      emergencyPhones: ((j['emergencyContacts'] as List?) ?? [])
          .map((e) => (e['phone'] ?? '') as String)
          .where((s) => s.isNotEmpty)
          .toList(),
      heartRate: v['heartRateBpm'],
      bpSys: v['bpSystolic'],
      bpDia: v['bpDiastolic'],
      oxygen: v['oxygenPercent'],
      tempF: (v['temperatureF'] as num?)?.toDouble(),
      painCurrent: p['current'],
      painLocation: p['location'],
      dizziness: p['dizziness'],
      fatigue: p['fatigue'],
      symptoms: ((j['symptoms'] as List?) ?? []).cast<Map<String, dynamic>>(),
      medications:
          ((j['medications'] as List?) ?? []).cast<Map<String, dynamic>>(),
      checkIns:
          ((j['virtualCheckIns'] as List?) ?? []).cast<Map<String, dynamic>>(),
    );
  }
}

/// One simple fetch. Set your base URL below.
class PatientApiSimple {
  final String baseUrl;
  PatientApiSimple(this.baseUrl);

  Future<PatientData> fetchPatient(String id) async {
    final uri = Uri.parse(
      '$baseUrl/api/patients/$id?include=medications,symptoms,checkins',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Load failed: ${res.statusCode}');
    }
    final Map<String, dynamic> json = jsonDecode(res.body);
    final body = (json['data'] ?? json) as Map<String, dynamic>;
    return PatientData.fromJson(body);
  }
}
