package com.careconnect.notifications;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.*;

import java.util.List;
import java.util.Map;

@Service
public class SnsService {

    private final SnsClient snsClient;

    @Autowired
    public SnsService(@Value("${aws.region:us-east-1}") String awsRegion) {
        Region region = Region.of(awsRegion);
        this.snsClient = SnsClient.builder().region(region).build();
    }

    // Package-visible constructor for tests or alternate client injection
    SnsService(SnsClient snsClient) {
        this.snsClient = snsClient;
    }

    /**
     * Publish to an SNS topic
     */
    public String publishToTopic(String topicArn, String subject, String message) {
        PublishRequest req = PublishRequest.builder()
                .topicArn(topicArn)
                .subject(subject)
                .message(message)
                .build();
        PublishResponse resp = snsClient.publish(req);
        return resp.messageId();
    }

    /**
     * Send SMS to a phone number
     */
    public String publishSms(String phoneNumber, String message) {
        PublishRequest req = PublishRequest.builder()
                .phoneNumber(phoneNumber)
                .message(message)
                .build();
        PublishResponse resp = snsClient.publish(req);
        return resp.messageId();
    }

    /**
     * Send SMS with custom attributes (for delivery tracking, etc.)
     */
    public String publishSmsWithAttributes(String phoneNumber, String message, Map<String, MessageAttributeValue> attributes) {
        PublishRequest req = PublishRequest.builder()
                .phoneNumber(phoneNumber)
                .message(message)
                .messageAttributes(attributes)
                .build();
        PublishResponse resp = snsClient.publish(req);
        return resp.messageId();
    }

    /**
     * Create an SNS topic
     */
    public String createTopic(String topicName) {
        CreateTopicRequest req = CreateTopicRequest.builder()
                .name(topicName)
                .build();
        CreateTopicResponse resp = snsClient.createTopic(req);
        return resp.topicArn();
    }

    /**
     * Subscribe an endpoint to a topic
     */
    public String subscribeToTopic(String topicArn, String protocol, String endpoint) {
        SubscribeRequest req = SubscribeRequest.builder()
                .topicArn(topicArn)
                .protocol(protocol)
                .endpoint(endpoint)
                .build();
        SubscribeResponse resp = snsClient.subscribe(req);
        return resp.subscriptionArn();
    }

    /**
     * Send payment confirmation SMS
     */
    public String sendPaymentConfirmationSms(String phoneNumber, String recipientName, String amount) {
        String message = String.format("Hi %s, your payment of $%s has been received. Thank you for using CareConnect!", recipientName, amount);
        return publishSms(phoneNumber, message);
    }

    /**
     * Send medication reminder SMS
     */
    public String sendMedicationReminderSms(String phoneNumber, String patientName, String medicationName, String dosage) {
        String message = String.format("Hi %s, reminder to take %s (%s). Please take as prescribed.", patientName, medicationName, dosage);
        return publishSms(phoneNumber, message);
    }

    /**
     * Send appointment reminder SMS
     */
    public String sendAppointmentReminderSms(String phoneNumber, String patientName, String appointmentType, String time) {
        String message = buildAppointmentReminderSmsMessage(time);
        return publishSms(phoneNumber, message);
    }

    public String buildAppointmentReminderSmsMessage(String time) {
        return String.format("You have a scheduled appointment for %s. If you have any questions, contact your provider.", time);
    }

    /**
     * Send caregiver message SMS
     */
    public String sendCaregiverMessageSms(String phoneNumber, String fromName, String message, boolean urgent) {
        String prefix = urgent ? "URGENT: " : "";
        String fullMessage = String.format("%sMessage from %s: %s", prefix, fromName, message);
        // Truncate if too long for SMS (160 chars is safe limit)
        if (fullMessage.length() > 160) {
            fullMessage = fullMessage.substring(0, 157) + "...";
        }
        return publishSms(phoneNumber, fullMessage);
    }

    /**
     * Send emergency alert SMS
     */
    public String sendEmergencyAlertSms(String phoneNumber, String patientName, String emergencyType, String location) {
        String message = String.format("EMERGENCY ALERT: %s requires immediate attention. Type: %s, Location: %s", patientName, emergencyType, location);
        return publishSms(phoneNumber, message);
    }

    /**
     * Send vital signs alert SMS
     */
    public String sendVitalAlertSms(String phoneNumber, String patientName, String vitalType, String value, String alertLevel) {
        String message = String.format("ALERT: %s's %s is %s (%s). Please check immediately.", patientName, vitalType, value, alertLevel);
        return publishSms(phoneNumber, message);
    }

    /**
     * Send bulk SMS to multiple recipients
     * Note: This sends individual SMS messages, not using SNS topics
     */
    public List<String> sendBulkSms(List<String> phoneNumbers, String message) {
        return phoneNumbers.stream()
                .map(phone -> {
                    try {
                        return publishSms(phone, message);
                    } catch (Exception e) {
                        // Log error and return null for failed sends
                        return null;
                    }
                })
                .toList();
    }

    /**
     * Send push notification via SNS (for mobile apps)
     * This assumes the endpoint is already registered with SNS
     */
    public String sendPushNotification(String targetArn, String title, String body, Map<String, String> data) {
        // For FCM/APNs, we need to format the message appropriately
        String jsonMessage = String.format("""
                        {
                            "GCM": "{ \\"notification\\": { \\"title\\": \\"%s\\", \\"body\\": \\"%s\\" } %s }"
                        }
                        """,
                title.replace("\"", "\\\""),
                body.replace("\"", "\\\""),
                data != null && !data.isEmpty() ? ", \"data\": " + data.toString() : ""
        );

        PublishRequest req = PublishRequest.builder()
                .targetArn(targetArn)
                .message(jsonMessage)
                .messageStructure("json")
                .build();

        PublishResponse resp = snsClient.publish(req);
        return resp.messageId();
    }

    /**
     * Register a device token for push notifications
     * Returns the endpoint ARN that can be used for sending push notifications
     */
    public String registerDeviceToken(String platformApplicationArn, String deviceToken, String userId) {
        // Create platform endpoint
        CreatePlatformEndpointRequest endpointReq = CreatePlatformEndpointRequest.builder()
                .platformApplicationArn(platformApplicationArn)
                .token(deviceToken)
                .customUserData(userId)
                .build();

        CreatePlatformEndpointResponse endpointResp = snsClient.createPlatformEndpoint(endpointReq);
        return endpointResp.endpointArn();
    }

    /**
     * Future enhancement: Send notification to all subscribers of a topic
     * This would be useful for broadcasting messages to groups
     */
    public String broadcastToTopic(String topicArn, String subject, String message) {
        return publishToTopic(topicArn, subject, message);
    }
}
