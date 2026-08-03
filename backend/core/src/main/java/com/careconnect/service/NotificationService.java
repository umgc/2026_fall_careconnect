package com.careconnect.service;

import com.careconnect.dto.FirebaseNotificationRequest;
import com.careconnect.dto.NotificationResponse;
import com.careconnect.model.DeviceToken;
import com.careconnect.model.NotificationSetting;
import com.careconnect.model.User;
import com.careconnect.notifications.SesService;
import com.careconnect.notifications.SnsService;
import com.careconnect.repository.DeviceTokenRepository;
import com.careconnect.repository.NotificationSettingRepository;
import com.careconnect.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class NotificationService {

    private final SesService sesService;
    private final SnsService snsService;
    private final DeviceTokenRepository deviceTokenRepository;
    private final NotificationSettingRepository notificationSettingRepository;
    private final UserRepository userRepository;
    private final Logger log = LoggerFactory.getLogger(NotificationService.class);

    /**
     * Send push notification (legacy method for Firebase compatibility)
     * Now uses AWS SNS for actual delivery
     */
    public NotificationResponse sendNotification(FirebaseNotificationRequest request) {
        try {
            // For now, send SMS if phone number is available, otherwise this is a placeholder
            if (request.getTargetToken() != null && request.getTargetToken().startsWith("+")) {
                // It's a phone number
                String messageId = snsService.publishSms(request.getTargetToken(), request.getBody());
                return NotificationResponse.success(messageId);
            } else {
                // For push notifications, we'd need device tokens registered with SNS
                // This is a placeholder for future implementation
                log.warn("Push notification to token {} not implemented yet", request.getTargetToken());
                return NotificationResponse.success("push-placeholder-" + System.currentTimeMillis());
            }
        } catch (Exception e) {
            log.error("Failed to send notification: {}", e.getMessage(), e);
            return NotificationResponse.failure(e.getMessage());
        }
    }

    /**
     * Send bulk notifications
     */
    public List<NotificationResponse> sendBulkNotifications(List<FirebaseNotificationRequest> requests) {
        return requests.stream()
                .map(this::sendNotification)
                .collect(Collectors.toList());
    }

    /**
     * Send notification to user by ID
     */
    @Transactional(readOnly = true)
    public List<NotificationResponse> sendNotificationToUser(Long userId, String title, String body, String notificationType, Map<String, String> data) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("User not found: " + userId));

        NotificationSetting settings = notificationSettingRepository.findByUserId(userId)
                .orElse(NotificationSetting.builder().userId(userId).build());

        List<NotificationResponse> responses = new java.util.ArrayList<>();

        // Send email if user has email and email notifications are enabled
        if (user.getEmail() != null && shouldSendEmail(notificationType, settings)) {
            try {
                String messageId = sesService.sendEmail(user.getEmail(), title, null, body);
                responses.add(NotificationResponse.success(messageId));
                log.info("Sent email notification to user {}: {}", userId, messageId);
            } catch (Exception e) {
                log.error("Failed to send email to user {}: {}", userId, e.getMessage());
                responses.add(NotificationResponse.failure("Email failed: " + e.getMessage()));
            }
        }

        // Send SMS if user has phone and SMS notifications are enabled
        if (user.getPhone() != null && shouldSendSms(notificationType, settings)) {
            try {
                String messageId = snsService.publishSms(user.getPhone(), body);
                responses.add(NotificationResponse.success(messageId));
                log.info("Sent SMS notification to user {}: {}", userId, messageId);
            } catch (Exception e) {
                log.error("Failed to send SMS to user {}: {}", userId, e.getMessage());
                responses.add(NotificationResponse.failure("SMS failed: " + e.getMessage()));
            }
        }

        // Send push notifications to registered devices
        List<DeviceToken> deviceTokens = deviceTokenRepository.findByUserIdAndIsActiveTrue(userId);
        for (DeviceToken token : deviceTokens) {
            if (shouldSendPush(notificationType, settings)) {
                try {
                    // For now, send SMS to phone numbers, push notification support needs more setup
                    if (token.getDeviceType() == DeviceToken.DeviceType.ANDROID && user.getPhone() != null) {
                        String messageId = snsService.publishSms(user.getPhone(), body);
                        responses.add(NotificationResponse.success(messageId));
                    }
                } catch (Exception e) {
                    log.error("Failed to send push notification to user {} device {}: {}", userId, token.getId(), e.getMessage());
                    responses.add(NotificationResponse.failure("Push failed: " + e.getMessage()));
                }
            }
        }

        return responses;
    }

    /**
     * Send vital signs alert
     */
    public CompletableFuture<List<NotificationResponse>> sendVitalAlert(Long patientId, String vitalType, String vitalValue, String alertLevel) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                User patient = userRepository.findById(patientId)
                        .orElseThrow(() -> new IllegalArgumentException("Patient not found: " + patientId));

                // Get caregivers for this patient (this would need a proper relationship query)
                // For now, just send to the patient
                List<NotificationResponse> responses = new java.util.ArrayList<>();

                String title = "Vital Signs Alert";
                String body = String.format("%s's %s is %s (%s level alert)", patient.getName(), vitalType, vitalValue, alertLevel);

                // Send SMS alert
                if (patient.getPhone() != null) {
                    try {
                        String messageId = snsService.sendVitalAlertSms(patient.getPhone(), patient.getName(), vitalType, vitalValue, alertLevel);
                        responses.add(NotificationResponse.success(messageId));
                    } catch (Exception e) {
                        responses.add(NotificationResponse.failure("SMS failed: " + e.getMessage()));
                    }
                }

                // Send email alert
                if (patient.getEmail() != null) {
                    try {
                        String messageId = sesService.sendEmail(patient.getEmail(), title, null, body);
                        responses.add(NotificationResponse.success(messageId));
                    } catch (Exception e) {
                        responses.add(NotificationResponse.failure("Email failed: " + e.getMessage()));
                    }
                }

                return responses;
            } catch (Exception e) {
                log.error("Failed to send vital alert: {}", e.getMessage(), e);
                return List.of(NotificationResponse.failure(e.getMessage()));
            }
        });
    }

    /**
     * Send a vital alert to a specific care-circle recipient.
     */
    @Transactional(readOnly = true)
    public List<NotificationResponse> sendVitalAlertToRecipient(
            Long recipientUserId,
            String patientDisplayName,
            String vitalType,
            String vitalValue,
            String alertLevel
    ) {
        String normalizedPatientName = (patientDisplayName == null || patientDisplayName.isBlank())
                ? "A patient"
                : patientDisplayName.trim();
        String title = "Wearable Vital Alert";
        String body = String.format(
                "%s reported %s at %s (%s severity).",
                normalizedPatientName,
                vitalType,
                vitalValue,
                alertLevel
        );
        return sendNotificationToUser(
                recipientUserId,
                title,
                body,
                "VITAL_ALERT",
                Map.of(
                        "patientName", normalizedPatientName,
                        "metricType", vitalType,
                        "measuredValue", vitalValue,
                        "alertLevel", alertLevel
                )
        );
    }

    /**
     * Send medication reminder
     */
    public CompletableFuture<List<NotificationResponse>> sendMedicationReminder(Long patientId, String medicationName, String dosage, String scheduledTime) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                User patient = userRepository.findById(patientId)
                        .orElseThrow(() -> new IllegalArgumentException("Patient not found: " + patientId));

                List<NotificationResponse> responses = new java.util.ArrayList<>();

                // Send SMS reminder
                if (patient.getPhone() != null) {
                    try {
                        String messageId = snsService.sendMedicationReminderSms(patient.getPhone(), patient.getName(), medicationName, dosage);
                        responses.add(NotificationResponse.success(messageId));
                    } catch (Exception e) {
                        responses.add(NotificationResponse.failure("SMS failed: " + e.getMessage()));
                    }
                }

                // Send email reminder
                if (patient.getEmail() != null) {
                    try {
                        String messageId = sesService.sendMedicationReminder(patient.getEmail(), patient.getName(), medicationName, dosage, scheduledTime);
                        responses.add(NotificationResponse.success(messageId));
                    } catch (Exception e) {
                        responses.add(NotificationResponse.failure("Email failed: " + e.getMessage()));
                    }
                }

                return responses;
            } catch (Exception e) {
                log.error("Failed to send medication reminder: {}", e.getMessage(), e);
                return List.of(NotificationResponse.failure(e.getMessage()));
            }
        });
    }

    /**
     * Send emergency alert
     */
    public CompletableFuture<List<NotificationResponse>> sendEmergencyAlert(Long patientId, String emergencyType, String location) {
        return CompletableFuture.supplyAsync(() -> {
            try {
                User patient = userRepository.findById(patientId)
                        .orElseThrow(() -> new IllegalArgumentException("Patient not found: " + patientId));

                List<NotificationResponse> responses = new java.util.ArrayList<>();

                String title = "EMERGENCY ALERT";
                String body = String.format("Emergency: %s requires immediate attention. Type: %s, Location: %s", patient.getName(), emergencyType, location);

                // Send SMS emergency alert
                if (patient.getPhone() != null) {
                    try {
                        String messageId = snsService.sendEmergencyAlertSms(patient.getPhone(), patient.getName(), emergencyType, location);
                        responses.add(NotificationResponse.success(messageId));
                    } catch (Exception e) {
                        responses.add(NotificationResponse.failure("SMS failed: " + e.getMessage()));
                    }
                }

                // Send email emergency alert
                if (patient.getEmail() != null) {
                    try {
                        String messageId = sesService.sendEmail(patient.getEmail(), title, null, body);
                        responses.add(NotificationResponse.success(messageId));
                    } catch (Exception e) {
                        responses.add(NotificationResponse.failure("Email failed: " + e.getMessage()));
                    }
                }

                return responses;
            } catch (Exception e) {
                log.error("Failed to send emergency alert: {}", e.getMessage(), e);
                return List.of(NotificationResponse.failure(e.getMessage()));
            }
        });
    }

    /**
     * Register device token for push notifications
     */
    public void registerDeviceToken(Long userId, String fcmToken, String deviceId, DeviceToken.DeviceType deviceType) {
        // For now, just store the token. Full SNS integration would require platform applications
        DeviceToken token = DeviceToken.builder()
                .user(userRepository.findById(userId).orElseThrow())
                .fcmToken(fcmToken)
                .deviceId(deviceId)
                .deviceType(deviceType)
                .build();
        deviceTokenRepository.save(token);
        log.info("Registered device token for user {}: {}", userId, deviceId);
    }

    /**
     * Unregister device token
     */
    public void unregisterDeviceToken(String fcmToken) {
        deviceTokenRepository.findByFcmTokenAndIsActiveTrue(fcmToken).ifPresent(deviceTokenRepository::delete);
        log.info("Unregistered device token: {}", fcmToken);
    }

    // Helper methods to check notification settings
    private boolean shouldSendEmail(String notificationType, NotificationSetting settings) {
        if (!settings.isEmergency() && "EMERGENCY".equals(notificationType)) return false;
        if (!settings.isSignificantVitals() && "VITAL_ALERT".equals(notificationType)) return false;
        return true; // Default to true for other types
    }

    private boolean shouldSendSms(String notificationType, NotificationSetting settings) {
        if (!settings.isEmergency() && "EMERGENCY".equals(notificationType)) return false;
        if (!settings.isSignificantVitals() && "VITAL_ALERT".equals(notificationType)) return false;
        return settings.isSms();
    }

    private boolean shouldSendPush(String notificationType, NotificationSetting settings) {
        if (!settings.isEmergency() && "EMERGENCY".equals(notificationType)) return false;
        if (!settings.isSignificantVitals() && "VITAL_ALERT".equals(notificationType)) return false;
        return true; // Push notifications generally follow SMS settings
    }
}
