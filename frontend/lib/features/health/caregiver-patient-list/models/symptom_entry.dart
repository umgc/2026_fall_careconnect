class SymptomEntry {
  final String id; // unique ID for this symptom record
  final DateTime date; // when patient logged it
  final String name; // e.g., "Headache"
  final String severity; // "Mild" | "Moderate" | "Severe"
  final String? note; // optional note

  SymptomEntry({
    required this.id,
    required this.date,
    required this.name,
    required this.severity,
    this.note,
  });
}
