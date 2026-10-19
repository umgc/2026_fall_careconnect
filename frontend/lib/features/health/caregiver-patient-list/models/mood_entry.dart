class MoodEntry {
  final String id; // unique ID for this mood record
  final DateTime date; // when the mood was recorded
  final int score10; // mood score on a 0–10 scale (like dashboard)
  final String label; // "Happy", "Anxious"
  final String emoji; // 😀, 😔, etc.
  final String? note; // optional caregiver/patient note

  MoodEntry({
    required this.id,
    required this.date,
    required this.score10,
    required this.label,
    required this.emoji,
    this.note,
  });
}
