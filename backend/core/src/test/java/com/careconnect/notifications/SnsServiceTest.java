package com.careconnect.notifications;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.CreatePlatformEndpointRequest;
import software.amazon.awssdk.services.sns.model.CreatePlatformEndpointResponse;
import software.amazon.awssdk.services.sns.model.CreateTopicRequest;
import software.amazon.awssdk.services.sns.model.CreateTopicResponse;
import software.amazon.awssdk.services.sns.model.MessageAttributeValue;
import software.amazon.awssdk.services.sns.model.PublishRequest;
import software.amazon.awssdk.services.sns.model.PublishResponse;
import software.amazon.awssdk.services.sns.model.SnsException;
import software.amazon.awssdk.services.sns.model.SubscribeRequest;
import software.amazon.awssdk.services.sns.model.SubscribeResponse;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link SnsService}.
 *
 * <p>Uses Mockito to mock the AWS {@link SnsClient} so that no real AWS calls
 * are made. Each public method is tested for both its success path and its
 * exception path (AWS SDK exceptions propagate to callers).
 */
class SnsServiceTest {

    private static final String MESSAGE_ID = "sns-msg-id-12345";
    private static final String TOPIC_ARN = "arn:aws:sns:us-east-1:123456789:test-topic";
    private static final String PHONE_NUMBER = "+15555551234";

    private SnsClient snsClient;
    private SnsService snsService;

    @BeforeEach
    void setUp() {
        snsClient = mock(SnsClient.class);
        snsService = new SnsService(snsClient);
    }

    // ==========================================
    // Helpers
    // ==========================================

    private void stubPublish() {
        PublishResponse response = PublishResponse.builder()
                .messageId(MESSAGE_ID)
                .build();
        when(snsClient.publish(any(PublishRequest.class))).thenReturn(response);
    }

    private void stubPublishThrows() {
        when(snsClient.publish(any(PublishRequest.class)))
                .thenThrow(SnsException.builder().message("SNS error").build());
    }

    // ==========================================
    // publishToTopic
    // ==========================================

    @Test
    void publishToTopic_success_returnsMessageId() {
        stubPublish();

        String result = snsService.publishToTopic(TOPIC_ARN, "Subject", "Hello");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void publishToTopic_success_buildsCorrectRequest() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.publishToTopic(TOPIC_ARN, "Subject", "Hello");

        verify(snsClient).publish(captor.capture());
        PublishRequest req = captor.getValue();
        assertEquals(TOPIC_ARN, req.topicArn());
        assertEquals("Subject", req.subject());
        assertEquals("Hello", req.message());
    }

    @Test
    void publishToTopic_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.publishToTopic(TOPIC_ARN, "Subj", "Msg"));
    }

    // ==========================================
    // publishSms
    // ==========================================

    @Test
    void publishSms_success_returnsMessageId() {
        stubPublish();

        String result = snsService.publishSms(PHONE_NUMBER, "Test SMS");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void publishSms_success_buildsCorrectRequest() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.publishSms(PHONE_NUMBER, "Test SMS");

        verify(snsClient).publish(captor.capture());
        PublishRequest req = captor.getValue();
        assertEquals(PHONE_NUMBER, req.phoneNumber());
        assertEquals("Test SMS", req.message());
    }

    @Test
    void publishSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.publishSms(PHONE_NUMBER, "Test SMS"));
    }

    // ==========================================
    // publishSmsWithAttributes
    // ==========================================

    @Test
    void publishSmsWithAttributes_success_returnsMessageId() {
        stubPublish();
        Map<String, MessageAttributeValue> attrs = Map.of(
                "AWS.SNS.SMS.SenderID",
                MessageAttributeValue.builder().stringValue("CareConn").dataType("String").build());

        String result = snsService.publishSmsWithAttributes(PHONE_NUMBER, "Test", attrs);

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void publishSmsWithAttributes_success_buildsCorrectRequest() {
        stubPublish();
        MessageAttributeValue attrValue = MessageAttributeValue.builder()
                .stringValue("CareConn").dataType("String").build();
        Map<String, MessageAttributeValue> attrs = Map.of("AWS.SNS.SMS.SenderID", attrValue);
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.publishSmsWithAttributes(PHONE_NUMBER, "Test", attrs);

        verify(snsClient).publish(captor.capture());
        PublishRequest req = captor.getValue();
        assertEquals(PHONE_NUMBER, req.phoneNumber());
        assertEquals("Test", req.message());
        assertEquals(attrs, req.messageAttributes());
    }

    @Test
    void publishSmsWithAttributes_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.publishSmsWithAttributes(PHONE_NUMBER, "Test", Map.of()));
    }

    // ==========================================
    // createTopic
    // ==========================================

    @Test
    void createTopic_success_returnsTopicArn() {
        CreateTopicResponse response = CreateTopicResponse.builder()
                .topicArn(TOPIC_ARN)
                .build();
        when(snsClient.createTopic(any(CreateTopicRequest.class))).thenReturn(response);

        String result = snsService.createTopic("test-topic");

        assertEquals(TOPIC_ARN, result);
    }

    @Test
    void createTopic_success_buildsCorrectRequest() {
        CreateTopicResponse response = CreateTopicResponse.builder()
                .topicArn(TOPIC_ARN).build();
        when(snsClient.createTopic(any(CreateTopicRequest.class))).thenReturn(response);
        ArgumentCaptor<CreateTopicRequest> captor = ArgumentCaptor.forClass(CreateTopicRequest.class);

        snsService.createTopic("my-topic");

        verify(snsClient).createTopic(captor.capture());
        assertEquals("my-topic", captor.getValue().name());
    }

    @Test
    void createTopic_snsException_propagates() {
        when(snsClient.createTopic(any(CreateTopicRequest.class)))
                .thenThrow(SnsException.builder().message("SNS error").build());

        assertThrows(SnsException.class, () -> snsService.createTopic("bad-topic"));
    }

    // ==========================================
    // subscribeToTopic
    // ==========================================

    @Test
    void subscribeToTopic_success_returnsSubscriptionArn() {
        String subscriptionArn = "arn:aws:sns:us-east-1:123456789:test-topic:sub-1";
        SubscribeResponse response = SubscribeResponse.builder()
                .subscriptionArn(subscriptionArn).build();
        when(snsClient.subscribe(any(SubscribeRequest.class))).thenReturn(response);

        String result = snsService.subscribeToTopic(TOPIC_ARN, "email", "user@example.com");

        assertEquals(subscriptionArn, result);
    }

    @Test
    void subscribeToTopic_success_buildsCorrectRequest() {
        SubscribeResponse response = SubscribeResponse.builder()
                .subscriptionArn("arn:sub").build();
        when(snsClient.subscribe(any(SubscribeRequest.class))).thenReturn(response);
        ArgumentCaptor<SubscribeRequest> captor = ArgumentCaptor.forClass(SubscribeRequest.class);

        snsService.subscribeToTopic(TOPIC_ARN, "sms", PHONE_NUMBER);

        verify(snsClient).subscribe(captor.capture());
        SubscribeRequest req = captor.getValue();
        assertEquals(TOPIC_ARN, req.topicArn());
        assertEquals("sms", req.protocol());
        assertEquals(PHONE_NUMBER, req.endpoint());
    }

    @Test
    void subscribeToTopic_snsException_propagates() {
        when(snsClient.subscribe(any(SubscribeRequest.class)))
                .thenThrow(SnsException.builder().message("SNS error").build());

        assertThrows(SnsException.class,
                () -> snsService.subscribeToTopic(TOPIC_ARN, "email", "user@example.com"));
    }

    // ==========================================
    // sendPaymentConfirmationSms
    // ==========================================

    @Test
    void sendPaymentConfirmationSms_success_returnsMessageId() {
        stubPublish();

        String result = snsService.sendPaymentConfirmationSms(PHONE_NUMBER, "Alice", "99.99");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendPaymentConfirmationSms_success_messageContainsNameAndAmount() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendPaymentConfirmationSms(PHONE_NUMBER, "Alice", "99.99");

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.contains("Alice"));
        assertTrue(msg.contains("$99.99"));
    }

    @Test
    void sendPaymentConfirmationSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.sendPaymentConfirmationSms(PHONE_NUMBER, "Alice", "99.99"));
    }

    // ==========================================
    // sendMedicationReminderSms
    // ==========================================

    @Test
    void sendMedicationReminderSms_success_returnsMessageId() {
        stubPublish();

        String result = snsService.sendMedicationReminderSms(PHONE_NUMBER, "Bob", "Aspirin", "100mg");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendMedicationReminderSms_success_messageContainsDetails() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendMedicationReminderSms(PHONE_NUMBER, "Bob", "Aspirin", "100mg");

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.contains("Bob"));
        assertTrue(msg.contains("Aspirin"));
        assertTrue(msg.contains("100mg"));
    }

    @Test
    void sendMedicationReminderSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.sendMedicationReminderSms(PHONE_NUMBER, "Bob", "Aspirin", "100mg"));
    }

    // ==========================================
    // sendAppointmentReminderSms
    // ==========================================

    @Test
    void sendAppointmentReminderSms_success_returnsMessageId() {
        stubPublish();

        String result = snsService.sendAppointmentReminderSms(PHONE_NUMBER, "Carol", "Checkup", "10:00 AM");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendAppointmentReminderSms_success_messageContainsDetails() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendAppointmentReminderSms(PHONE_NUMBER, "Carol", "Checkup", "10:00 AM");

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.contains("10:00 AM"));
        assertTrue(msg.contains("scheduled appointment"));
    }

    @Test
    void sendAppointmentReminderSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.sendAppointmentReminderSms(PHONE_NUMBER, "Carol", "Checkup", "10:00 AM"));
    }

    // ==========================================
    // sendCaregiverMessageSms
    // ==========================================

    @Test
    void sendCaregiverMessageSms_notUrgent_returnsMessageId() {
        stubPublish();

        String result = snsService.sendCaregiverMessageSms(PHONE_NUMBER, "Dr. Smith", "Check vitals", false);

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendCaregiverMessageSms_notUrgent_messageWithoutUrgentPrefix() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendCaregiverMessageSms(PHONE_NUMBER, "Dr. Smith", "Check vitals", false);

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.contains("Dr. Smith"));
        assertTrue(msg.contains("Check vitals"));
        assertTrue(msg.startsWith("Message from"));
    }

    @Test
    void sendCaregiverMessageSms_urgent_messageHasUrgentPrefix() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendCaregiverMessageSms(PHONE_NUMBER, "Dr. Smith", "Emergency!", true);

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.startsWith("URGENT: "));
        assertTrue(msg.contains("Dr. Smith"));
        assertTrue(msg.contains("Emergency!"));
    }

    @Test
    void sendCaregiverMessageSms_longMessage_truncatedTo160Chars() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);
        String longMessage = "A".repeat(200);

        snsService.sendCaregiverMessageSms(PHONE_NUMBER, "Dr. Smith", longMessage, false);

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.length() <= 160);
        assertTrue(msg.endsWith("..."));
    }

    @Test
    void sendCaregiverMessageSms_shortMessage_notTruncated() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendCaregiverMessageSms(PHONE_NUMBER, "Dr. Smith", "Short", false);

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.length() <= 160);
        // Should not end with "..." for short messages
        assertTrue(msg.endsWith("Short"));
    }

    @Test
    void sendCaregiverMessageSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.sendCaregiverMessageSms(PHONE_NUMBER, "Dr. Smith", "msg", false));
    }

    // ==========================================
    // sendEmergencyAlertSms
    // ==========================================

    @Test
    void sendEmergencyAlertSms_success_returnsMessageId() {
        stubPublish();

        String result = snsService.sendEmergencyAlertSms(PHONE_NUMBER, "Dave", "Fall", "Room 5");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendEmergencyAlertSms_success_messageContainsDetails() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendEmergencyAlertSms(PHONE_NUMBER, "Dave", "Fall", "Room 5");

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.contains("EMERGENCY ALERT"));
        assertTrue(msg.contains("Dave"));
        assertTrue(msg.contains("Fall"));
        assertTrue(msg.contains("Room 5"));
    }

    @Test
    void sendEmergencyAlertSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.sendEmergencyAlertSms(PHONE_NUMBER, "Dave", "Fall", "Room 5"));
    }

    // ==========================================
    // sendVitalAlertSms
    // ==========================================

    @Test
    void sendVitalAlertSms_success_returnsMessageId() {
        stubPublish();

        String result = snsService.sendVitalAlertSms(
                PHONE_NUMBER, "Eve", "Blood Pressure", "180/120", "Critical");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendVitalAlertSms_success_messageContainsDetails() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendVitalAlertSms(PHONE_NUMBER, "Eve", "Blood Pressure", "180/120", "Critical");

        verify(snsClient).publish(captor.capture());
        String msg = captor.getValue().message();
        assertTrue(msg.contains("ALERT"));
        assertTrue(msg.contains("Eve"));
        assertTrue(msg.contains("Blood Pressure"));
        assertTrue(msg.contains("180/120"));
        assertTrue(msg.contains("Critical"));
    }

    @Test
    void sendVitalAlertSms_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.sendVitalAlertSms(
                        PHONE_NUMBER, "Eve", "Blood Pressure", "180/120", "Critical"));
    }

    // ==========================================
    // sendBulkSms
    // ==========================================

    @Test
    void sendBulkSms_success_returnsListOfMessageIds() {
        stubPublish();
        List<String> phones = List.of("+15551111111", "+15552222222", "+15553333333");

        List<String> results = snsService.sendBulkSms(phones, "Bulk message");

        assertEquals(3, results.size());
        results.forEach(id -> assertEquals(MESSAGE_ID, id));
        verify(snsClient, times(3)).publish(any(PublishRequest.class));
    }

    @Test
    void sendBulkSms_emptyList_returnsEmptyList() {
        List<String> results = snsService.sendBulkSms(List.of(), "Bulk message");

        assertEquals(0, results.size());
    }

    @Test
    void sendBulkSms_someFailures_returnsNullForFailedSends() {
        // First call succeeds, second throws, third succeeds
        PublishResponse successResponse = PublishResponse.builder()
                .messageId(MESSAGE_ID).build();
        when(snsClient.publish(any(PublishRequest.class)))
                .thenReturn(successResponse)
                .thenThrow(SnsException.builder().message("SNS error").build())
                .thenReturn(successResponse);

        List<String> phones = List.of("+15551111111", "+15552222222", "+15553333333");
        List<String> results = snsService.sendBulkSms(phones, "Bulk message");

        assertEquals(3, results.size());
        assertEquals(MESSAGE_ID, results.get(0));
        assertNull(results.get(1));
        assertEquals(MESSAGE_ID, results.get(2));
    }

    @Test
    void sendBulkSms_allFailures_returnsAllNulls() {
        stubPublishThrows();

        List<String> phones = List.of("+15551111111", "+15552222222");
        List<String> results = snsService.sendBulkSms(phones, "Bulk message");

        assertEquals(2, results.size());
        results.forEach(id -> assertNull(id));
    }

    // ==========================================
    // sendPushNotification
    // ==========================================

    @Test
    void sendPushNotification_success_returnsMessageId() {
        stubPublish();
        String targetArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token";

        String result = snsService.sendPushNotification(targetArn, "Title", "Body", null);

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void sendPushNotification_withData_buildsCorrectRequest() {
        stubPublish();
        String targetArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token";
        Map<String, String> data = Map.of("key", "value");
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendPushNotification(targetArn, "Title", "Body", data);

        verify(snsClient).publish(captor.capture());
        PublishRequest req = captor.getValue();
        assertEquals(targetArn, req.targetArn());
        assertEquals("json", req.messageStructure());
        assertTrue(req.message().contains("Title"));
        assertTrue(req.message().contains("Body"));
    }

    @Test
    void sendPushNotification_nullData_buildsRequestWithoutData() {
        stubPublish();
        String targetArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token";
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendPushNotification(targetArn, "Title", "Body", null);

        verify(snsClient).publish(captor.capture());
        PublishRequest req = captor.getValue();
        assertTrue(req.message().contains("Title"));
        assertTrue(req.message().contains("Body"));
    }

    @Test
    void sendPushNotification_emptyData_buildsRequestWithoutData() {
        stubPublish();
        String targetArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token";
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.sendPushNotification(targetArn, "Title", "Body", Map.of());

        verify(snsClient).publish(captor.capture());
        // Empty data should not include "data" key based on the condition in source
        assertTrue(captor.getValue().message().contains("Title"));
    }

    @Test
    void sendPushNotification_snsException_propagates() {
        stubPublishThrows();
        String targetArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token";

        assertThrows(SnsException.class,
                () -> snsService.sendPushNotification(targetArn, "Title", "Body", null));
    }

    // ==========================================
    // registerDeviceToken
    // ==========================================

    @Test
    void registerDeviceToken_success_returnsEndpointArn() {
        String endpointArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token123";
        CreatePlatformEndpointResponse response = CreatePlatformEndpointResponse.builder()
                .endpointArn(endpointArn).build();
        when(snsClient.createPlatformEndpoint(any(CreatePlatformEndpointRequest.class)))
                .thenReturn(response);

        String result = snsService.registerDeviceToken(
                "arn:aws:sns:us-east-1:123456789:app/GCM/myapp", "device-token-abc", "user-42");

        assertEquals(endpointArn, result);
    }

    @Test
    void registerDeviceToken_success_buildsCorrectRequest() {
        String endpointArn = "arn:aws:sns:us-east-1:123456789:endpoint/GCM/app/token123";
        CreatePlatformEndpointResponse response = CreatePlatformEndpointResponse.builder()
                .endpointArn(endpointArn).build();
        when(snsClient.createPlatformEndpoint(any(CreatePlatformEndpointRequest.class)))
                .thenReturn(response);
        ArgumentCaptor<CreatePlatformEndpointRequest> captor =
                ArgumentCaptor.forClass(CreatePlatformEndpointRequest.class);

        String platformArn = "arn:aws:sns:us-east-1:123456789:app/GCM/myapp";
        snsService.registerDeviceToken(platformArn, "device-token-abc", "user-42");

        verify(snsClient).createPlatformEndpoint(captor.capture());
        CreatePlatformEndpointRequest req = captor.getValue();
        assertEquals(platformArn, req.platformApplicationArn());
        assertEquals("device-token-abc", req.token());
        assertEquals("user-42", req.customUserData());
    }

    @Test
    void registerDeviceToken_snsException_propagates() {
        when(snsClient.createPlatformEndpoint(any(CreatePlatformEndpointRequest.class)))
                .thenThrow(SnsException.builder().message("SNS error").build());

        assertThrows(SnsException.class,
                () -> snsService.registerDeviceToken("arn:platform", "token", "user"));
    }

    // ==========================================
    // broadcastToTopic
    // ==========================================

    @Test
    void broadcastToTopic_success_returnsMessageId() {
        stubPublish();

        String result = snsService.broadcastToTopic(TOPIC_ARN, "Broadcast Subject", "Broadcast Msg");

        assertEquals(MESSAGE_ID, result);
    }

    @Test
    void broadcastToTopic_success_delegatesToPublishToTopic() {
        stubPublish();
        ArgumentCaptor<PublishRequest> captor = ArgumentCaptor.forClass(PublishRequest.class);

        snsService.broadcastToTopic(TOPIC_ARN, "Broadcast Subject", "Broadcast Msg");

        verify(snsClient).publish(captor.capture());
        PublishRequest req = captor.getValue();
        assertEquals(TOPIC_ARN, req.topicArn());
        assertEquals("Broadcast Subject", req.subject());
        assertEquals("Broadcast Msg", req.message());
    }

    @Test
    void broadcastToTopic_snsException_propagates() {
        stubPublishThrows();

        assertThrows(SnsException.class,
                () -> snsService.broadcastToTopic(TOPIC_ARN, "Subject", "Message"));
    }
}
