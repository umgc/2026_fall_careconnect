enum CheckInType { routine, followUp, urgent }
enum CheckInStatus { draft, submitted, reviewed, completed, missed, cancelled }

class VirtualCheckIn {
  final String id;
  final CheckInType type;        // routine | followUp | urgent
  final String clinicianName;    // e.g., "Dr. Sarah Johnson"
  final DateTime startedAt;      // e.g., Dec 4, 2024 • 10:30 AM
  final int durationMinutes;     // e.g., 15
  final CheckInStatus status;    // Completed, Missed, Cancelled
  final String moodLabel;        // Good | Fair | Poor
  final DateTime nextCheckIn;    // e.g., Dec 11, 2024
  final String summary;          // Session Summary paragraph

  VirtualCheckIn({
    required this.id,
    required this.type,
    required this.clinicianName,
    required this.startedAt,
    required this.durationMinutes,
    required this.status,
    required this.moodLabel,
    required this.nextCheckIn,
    required this.summary,
  });
}



