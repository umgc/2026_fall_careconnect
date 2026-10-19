package com.careconnect.service;

import com.careconnect.websocket.CallNotificationHandler;
import com.careconnect.websocket.CareConnectWebSocketHandler;
import com.careconnect.dto.CaregiverPatientLinkResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Map;

@Service
@Slf4j
@RequiredArgsConstructor
public class WebSocketNotificationService {
    private final CallNotificationHandler callNotificationHandler;
    private final CareConnectWebSocketHandler careConnectWebSocketHandler;
    private final CaregiverPatientLinkService caregiverPatientLinkService;

    /**
     * Register a user for WebSocket notifications via HTTP (undying session)
     */
    public void registerUser(String userId, String userName) {
        careConnectWebSocketHandler.registerUser(userId, userName);
        log.info("User {} ({}) registered for WebSocket notifications via HTTP", userId, userName);
    }

    /**
     * Send a call invitation to a specific user
     */
    public void sendCallInvitation(String recipientId, String senderId, String senderName,
                                   String callId, boolean isVideoCall, String callType) {
        Map<String, Object> notification = Map.of(
                "type", "incoming-video-call",
                "senderId", senderId,
                "senderName", senderName,
                "callId", callId,
                "isVideoCall", isVideoCall,
                "callType", callType,
                "timestamp", System.currentTimeMillis()
        );

        callNotificationHandler.sendNotificationToUser(recipientId, notification);
        log.info("Call invitation sent to user {} from {}", recipientId, senderId);
    }

    /**
     * Send SMS notification to a specific user
     */
    public void sendSMSNotification(String recipientId, String senderId, String senderName,
                                    String message, String messageType) {
        Map<String, Object> notification = Map.of(
                "type", "incoming-sms",
                "senderId", senderId,
                "senderName", senderName,
                "message", message,
                "messageType", messageType,
                "timestamp", System.currentTimeMillis()
        );

        callNotificationHandler.sendNotificationToUser(recipientId, notification);
        log.info("SMS notification sent to user {} from {}", recipientId, senderId);
    }

    /**
     * Send AI chat response notification
     */
    public void sendAIChatNotification(String userId, String conversationId, String message) {
        Map<String, Object> notification = Map.of(
                "type", "ai-chat-response",
                "conversationId", conversationId,
                "message", message,
                "timestamp", System.currentTimeMillis()
        );

        careConnectWebSocketHandler.sendRealTimeUpdate(userId, notification);
        log.info("AI chat notification sent to user {}", userId);
    }

    /**
     * Send mood/pain log update notification to caregivers and family members
     */
    public void sendMoodPainLogUpdate(String patientId, String patientName,
                                      Integer moodValue, Integer painValue) {
        Map<String, Object> notification = Map.of(
                "type", "mood-pain-log-updated",
                "patientId", patientId,
                "patientName", patientName,
                "moodValue", moodValue,
                "painValue", painValue,
                "timestamp", System.currentTimeMillis()
        );

        // This could be enhanced to get actual caregiver/family member IDs
        // and send to each of them individually
        careConnectWebSocketHandler.sendRealTimeUpdate(patientId, notification);
        log.info("Mood/pain log update notification sent for patient {}", patientId);
    }

    /**
     * Send medication reminder to patient
     */
    public void sendMedicationReminder(String patientId, String medicationName,
                                       String reminderTime, String dosage) {
        Map<String, Object> notification = Map.of(
                "type", "medication-reminder",
                "medicationName", medicationName,
                "dosage", dosage,
                "reminderTime", reminderTime,
                "message", "Time to take your " + medicationName + " (" + dosage + ")",
                "timestamp", System.currentTimeMillis()
        );

        careConnectWebSocketHandler.sendRealTimeUpdate(patientId, notification);
        log.info("Medication reminder sent to patient {} for {}", patientId, medicationName);
    }

    /**
     * Send vital signs alert to healthcare providers
     */
    public void sendVitalSignsAlert(String patientId, String patientName, String alertType,
                                    String alertMessage, String severity, String[] recipientIds) {
        Map<String, Object> notification = Map.of(
                "type", "vital-signs-alert",
                "patientId", patientId,
                "patientName", patientName,
                "alertType", alertType,
                "message", alertMessage,
                "severity", severity,
                "timestamp", System.currentTimeMillis()
        );

        // Send to multiple healthcare providers
        for (String recipientId : recipientIds) {
            careConnectWebSocketHandler.sendRealTimeUpdate(recipientId, notification);
        }

        log.info("Vital signs alert sent for patient {} to {} recipients", patientId, recipientIds.length);
    }

    /**
     * Send family member request notification
     */
    public void sendFamilyMemberRequest(String patientId, String requesterUserId,
                                        String requesterName, String requesterEmail, String relationship) {
        Map<String, Object> notification = Map.of(
                "type", "family-member-request",
                "fromUserId", requesterUserId,
                "fromUserName", requesterName,
                "fromUserEmail", requesterEmail,
                "relationship", relationship,
                "requestType", "family-member-link",
                "timestamp", System.currentTimeMillis()
        );

        careConnectWebSocketHandler.sendRealTimeUpdate(patientId, notification);
        log.info("Family member request sent to patient {} from {}", patientId, requesterName);
    }

    /**
     * Send emergency alert (high priority)
     */
    public void sendEmergencyAlert(String patientId, String patientName, String alertMessage,
                                   String[] emergencyContactIds) {
        Map<String, Object> notification = Map.of(
                "type", "emergency-alert",
                "patientId", patientId,
                "patientName", patientName,
                "message", alertMessage,
                "severity", "CRITICAL",
                "priority", "HIGH",
                "timestamp", System.currentTimeMillis()
        );

        // Send to all emergency contacts
        for (String contactId : emergencyContactIds) {
            careConnectWebSocketHandler.sendRealTimeUpdate(contactId, notification);
        }

        log.warn("Emergency alert sent for patient {} to {} emergency contacts", patientId, emergencyContactIds.length);
    }

    /**
     * Send appointment reminder
     */
    public void sendAppointmentReminder(String patientId, String appointmentDetails,
                                        String appointmentTime, String providerName) {
        Map<String, Object> notification = Map.of(
                "type", "appointment-reminder",
                "appointmentDetails", appointmentDetails,
                "appointmentTime", appointmentTime,
                "providerName", providerName,
                "message", "Reminder: You have an appointment with " + providerName + " at " + appointmentTime,
                "timestamp", System.currentTimeMillis()
        );

        careConnectWebSocketHandler.sendRealTimeUpdate(patientId, notification);
        log.info("Appointment reminder sent to patient {} for appointment with {}", patientId, providerName);
    }

    /**
     * Broadcast system announcement to all users
     */
    public void broadcastSystemAnnouncement(String title, String message, String type) {
        Map<String, Object> announcement = Map.of(
                "type", "system-announcement",
                "title", title,
                "message", message,
                "announcementType", type,
                "timestamp", System.currentTimeMillis()
        );

        careConnectWebSocketHandler.broadcastToAllUsers(announcement);
        log.info("System announcement broadcasted: {}", title);
    }

    /**
     * Check if a user is currently online
     */
    public boolean isUserOnline(String userId) {
        return careConnectWebSocketHandler.isUserOnline(userId);
    }

    /**
     * Get count of online users
     */
    public int getOnlineUsersCount() {
        return careConnectWebSocketHandler.getOnlineUsersCount();
    }

    /**
     * Get list of online users (for admin purposes)
     */
    public Map<String, String> getOnlineUsers() {
        return callNotificationHandler.getOnlineUsers();
    }

    // Additional REST API support methods

    /**
     * Send SOS call to all caregivers associated with a patient
     */
    public int sendSOSCallToAllCaregivers(String patientUserId, String patientName,
                                          String callId, String emergencyType, String location,
                                          String additionalInfo, boolean isVideoCall) {
        try {
            // Get all caregivers associated with this patient
            List<CaregiverPatientLinkResponse> caregiverLinks =
                    caregiverPatientLinkService.getCaregiversByPatient(Long.parseLong(patientUserId));

            if (caregiverLinks.isEmpty()) {
                log.warn("No caregivers found for patient user ID: {}", patientUserId);
                return 0;
            }

            // Prepare SOS call notification
            Map<String, Object> sosNotification = Map.of(
                    "type", "sos-call",
                    "timestamp", Instant.now().toString(),
                    "data", Map.of(
                            "patientUserId", patientUserId,
                            "patientName", patientName,
                            "callId", callId,
                            "emergencyType", emergencyType,
                            "location", location != null ? location : "Unknown",
                            "additionalInfo", additionalInfo != null ? additionalInfo : "",
                            "isVideoCall", isVideoCall,
                            "priority", "CRITICAL",
                            "message", "🚨 EMERGENCY: " + patientName + " needs immediate assistance!",
                            "urgency", "HIGH"
                    )
            );

            int notifiedCount = 0;

            // Send SOS call to each caregiver
            for (CaregiverPatientLinkResponse link : caregiverLinks) {
                try {
                    callNotificationHandler.sendCallInvitation(
                            link.caregiverUserId().toString(),
                            sosNotification
                    );
                    notifiedCount++;
                    log.info("SOS call sent to caregiver {} for patient {}",
                            link.caregiverName(), patientName);
                } catch (Exception e) {
                    log.error("Failed to send SOS call to caregiver {}: {}",
                            link.caregiverUserId(), e.getMessage());
                }
            }

            log.info("SOS call from patient {} sent to {} caregivers",
                    patientName, notifiedCount);

            return notifiedCount;

        } catch (Exception e) {
            log.error("Error sending SOS call for patient {}: {}", patientUserId, e.getMessage());
            throw new RuntimeException("Failed to send SOS call to caregivers", e);
        }
    }
}
