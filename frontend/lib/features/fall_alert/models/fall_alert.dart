// 1. You MUST add this import for jsonEncode and jsonDecode
import 'dart:convert';

class FallAlert {
  final String id;
  final String patientId;
  final String patientName;
  final DateTime detectedAtUtc;
  final String source; // "watch" or "camera"
  final bool hasLiveVideo;
  final Uri? liveVideoUrl;
  final String? patientPhone; // E.164 like +15551234567
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  // --- 2. ADDED THIS FIELD ---
  final Map<String, dynamic>? playbackData; // Holds the SAMPLE_RESPONSE map

  FallAlert({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.detectedAtUtc,
    required this.source,
    required this.hasLiveVideo,
    this.liveVideoUrl,
    this.patientPhone,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.playbackData,
  });

  Map<String, String> toPayload() {
    return {
      'id': id,
      'patientId': patientId,
      'patientName': patientName,
      'detectedAtUtc': detectedAtUtc.toIso8601String(),
      'source': source,
      'hasLiveVideo': hasLiveVideo.toString(),
      'liveVideoUrl': liveVideoUrl?.toString() ?? '',
      'patientPhone': patientPhone ?? '',
      'emergencyContactName': emergencyContactName ?? '',
      'emergencyContactPhone': emergencyContactPhone ?? '',

      // --- 4. ADDED JSON ENCODING ---
      // Encodes the map into a JSON string for storage
      'playbackData': playbackData != null ? jsonEncode(playbackData!) : '',
    };
  }

  factory FallAlert.fromPayload(Map<String, String> p) {
    return FallAlert(
      id: p['id']!,
      patientId: p['patientId']!,
      patientName: p['patientName']!,
      detectedAtUtc: DateTime.parse(p['detectedAtUtc']!),
      source: p['source']!,
      hasLiveVideo: p['hasLiveVideo'] == 'true',
      liveVideoUrl: (p['liveVideoUrl']?.isNotEmpty ?? false)
          ? Uri.parse(p['liveVideoUrl']!)
          : null,
      patientPhone:
          (p['patientPhone']?.isNotEmpty ?? false) ? p['patientPhone']! : null,
      emergencyContactName: (p['emergencyContactName']?.isNotEmpty ?? false)
          ? p['emergencyContactName']!
          : null,
      emergencyContactPhone: (p['emergencyContactPhone']?.isNotEmpty ?? false)
          ? p['emergencyContactPhone']!
          : null,

      // --- 5. ADDED JSON DECODING ---
      // Parses the JSON string back into a Map
      playbackData: (p['playbackData']?.isNotEmpty ?? false)
          ? jsonDecode(p['playbackData']!) as Map<String, dynamic>
          : null,
    );
  }
}
