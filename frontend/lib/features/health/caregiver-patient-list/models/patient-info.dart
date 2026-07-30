/// Model class representing a patient in the caregiver's patient list.
///
/// This class contains all the essential information about a patient
/// that caregivers need to monitor their health status, mood, and
/// communication requirements.
class Patient {
  /// Unique identifier for the patient
  final String id;

  /// User identifier used for direct chat and messaging
  final int? patientUserId;

  /// Care-circle link id (for invite QR / suspend / reactivate).
  final int? linkId;

  /// Patient's first name
  final String firstName;

  /// Patient's last name
  final String lastName;

  /// Timestamp of the last update from this patient
  final DateTime lastUpdated;

  /// Current status message or health update from the patient
  final String statusMessage;

  /// Scheduled date and time for the next check-in
  final DateTime nextCheckIn;

  /// Current mood description of the patient
  final String mood;

  /// Emoji representation of the patient's mood
  final String moodEmoji;

  /// Flag indicating if this patient requires urgent attention
  final bool isUrgent;

  /// Number of unread messages from this patient
  final int messageCount;

  /// Creates a new Patient instance.
  ///
  /// Parameters:
  /// * [id] - Unique identifier for the patient
  /// * [firstName] - Patient's first name
  /// * [lastName] - Patient's last name
  /// * [lastUpdated] - Timestamp of the last update from this patient
  /// * [statusMessage] - Current status message or health update from the patient
  /// * [nextCheckIn] - Scheduled date and time for the next check-in
  /// * [mood] - Current mood description of the patient
  /// * [moodEmoji] - Emoji representation of the patient's mood
  /// * [isUrgent] - Flag indicating if this patient requires urgent attention
  /// * [messageCount] - Number of unread messages from this patient (defaults to 0)
  Patient({
    required this.id,
    this.patientUserId,
    this.linkId,
    required this.firstName,
    required this.lastName,
    required this.lastUpdated,
    required this.statusMessage,
    required this.nextCheckIn,
    required this.mood,
    required this.moodEmoji,
    required this.isUrgent,
    this.messageCount = 0,
  });

  /// Returns the patient's full name.
  ///
  /// Combines the first and last name with a space separator.
  ///
  /// Returns:
  /// * String - The patient's full name in "firstName lastName" format
  String get fullName => '$firstName $lastName';
}
