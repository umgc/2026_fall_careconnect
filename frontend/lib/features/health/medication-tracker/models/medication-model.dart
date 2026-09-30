/// Medication type enum
/// Mirrors backend Medication.MedicationType (Medication.java) — PRESCRIPTION,
/// SUPPLEMENT, HERBAL, and EMERGENCY match the backend enum's constant names.
/// OTC remains distinct from the backend's OVER_THE_COUNTER; see KI-05.
enum MedicationType { PRESCRIPTION, OTC, SUPPLEMENT, HERBAL, EMERGENCY }

/// Medication status enum (for UI display purposes)
enum MedicationStatus { upcoming, taken, missed }

/// Medication model matching backend structure
class Medication {
  final int? id;
  final int? patientId;
  final String medicationName;
  final String dosage;
  final String frequency;
  final String route; // Oral, IV, Topical, etc.
  final MedicationType? medicationType;
  final String? prescribedBy;
  final String? prescribedDate; // ISO 8601 date string
  final String? startDate; // ISO 8601 date string
  final String? endDate; // ISO 8601 date string (null if ongoing)
  final String? notes;
  final bool isActive;

  // UI-only fields (not from backend)
  final MedicationStatus? status; // For UI display
  final String? nextDose; // For UI display

  const Medication({
    this.id,
    this.patientId,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.route,
    this.medicationType,
    this.prescribedBy,
    this.prescribedDate,
    this.startDate,
    this.endDate,
    this.notes,
    required this.isActive,
    this.status,
    this.nextDose,
  });

  /// Create Medication from JSON (backend response)
  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as int?,
      patientId: json['patientId'] as int?,
      medicationName: json['medicationName'] as String,
      dosage: json['dosage'] as String,
      frequency: json['frequency'] as String,
      route: json['route'] as String,
      medicationType: json['medicationType'] != null
          ? MedicationType.values.firstWhere(
              (e) => e.name == json['medicationType'],
              orElse: () => MedicationType.PRESCRIPTION,
            )
          : null,
      prescribedBy: json['prescribedBy'] as String?,
      prescribedDate: json['prescribedDate'] as String?,
      startDate: json['startDate'] as String?,
      endDate: json['endDate'] as String?,
      notes: json['notes'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      // UI fields - calculate from backend data
      nextDose: _calculateNextDose(
        json['frequency'] as String?,
        json['startDate'] as String?,
      ),
    );
  }

  /// Convert Medication to JSON (for API requests)
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (patientId != null) 'patientId': patientId,
      'medicationName': medicationName,
      'dosage': dosage,
      'frequency': frequency,
      'route': route,
      if (medicationType != null) 'medicationType': medicationType!.name,
      if (prescribedBy != null) 'prescribedBy': prescribedBy,
      if (prescribedDate != null) 'prescribedDate': prescribedDate,
      if (startDate != null) 'startDate': startDate,
      if (endDate != null) 'endDate': endDate,
      if (notes != null) 'notes': notes,
      'isActive': isActive,
    };
  }

  /// Helper method to calculate next dose time (placeholder logic)
  static String? _calculateNextDose(String? frequency, String? startDate) {
    if (frequency == null) return null;

    // Simple logic: if frequency contains "daily", show "Today"
    if (frequency.toLowerCase().contains('daily')) {
      return 'Today';
    } else if (frequency.toLowerCase().contains('weekly')) {
      return 'This week';
    } else if (frequency.toLowerCase().contains('monthly')) {
      return 'This month';
    }

    return 'As needed';
  }

  /// Create a copy with modified fields
  Medication copyWith({
    int? id,
    int? patientId,
    String? medicationName,
    String? dosage,
    String? frequency,
    String? route,
    MedicationType? medicationType,
    String? prescribedBy,
    String? prescribedDate,
    String? startDate,
    String? endDate,
    String? notes,
    bool? isActive,
    MedicationStatus? status,
    String? nextDose,
  }) {
    return Medication(
      id: id ?? this.id,
      patientId: patientId ?? this.patientId,
      medicationName: medicationName ?? this.medicationName,
      dosage: dosage ?? this.dosage,
      frequency: frequency ?? this.frequency,
      route: route ?? this.route,
      medicationType: medicationType ?? this.medicationType,
      prescribedBy: prescribedBy ?? this.prescribedBy,
      prescribedDate: prescribedDate ?? this.prescribedDate,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      nextDose: nextDose ?? this.nextDose,
    );
  }

  @override
  String toString() {
    return 'Medication(id: $id, name: $medicationName, dosage: $dosage, frequency: $frequency, isActive: $isActive)';
  }
}