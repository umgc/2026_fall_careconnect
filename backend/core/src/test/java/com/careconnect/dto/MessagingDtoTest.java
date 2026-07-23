package com.careconnect.dto;

// Tests for messaging/notification DTOs.
// Covers ChatMessageSummary, FirebaseNotificationRequest,
// NotificationSettingDTO, ScheduledNotificationDTO.

import com.careconnect.model.ChatMessage;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.time.LocalDateTime;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

@DisplayName("Messaging & Notification DTOs")
class MessagingDtoTest {

    @Nested
    @DisplayName("ChatMessageSummary")
    class ChatMessageSummaryTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsAll() {
            LocalDateTime now = LocalDateTime.of(2026, 3, 17, 10, 0);
            ChatMessageSummary summary = ChatMessageSummary.builder()
                    .messageId(42L)
                    .messageType(ChatMessage.MessageType.ASSISTANT)
                    .content("Hello patient")
                    .tokensUsed(150)
                    .processingTimeMs(250L)
                    .aiModelUsed("claude-sonnet-4-6")
                    .createdAt(now)
                    .build();

            assertEquals(42L, summary.getMessageId());
            assertEquals(ChatMessage.MessageType.ASSISTANT, summary.getMessageType());
            assertEquals("Hello patient", summary.getContent());
            assertEquals(150, summary.getTokensUsed());
            assertEquals(250L, summary.getProcessingTimeMs());
            assertEquals("claude-sonnet-4-6", summary.getAiModelUsed());
            assertEquals(now, summary.getCreatedAt());
        }

        @Test
        @DisplayName("no-arg constructor creates null fields")
        void noArgConstructor() {
            ChatMessageSummary summary = new ChatMessageSummary();
            assertNull(summary.getMessageId());
            assertNull(summary.getContent());
            assertNull(summary.getTokensUsed());
        }
    }

    @Nested
    @DisplayName("FirebaseNotificationRequest")
    class FirebaseNotificationRequestTests {

        @Test
        @DisplayName("builder sets all fields")
        void builderSetsAll() {
            FirebaseNotificationRequest req = FirebaseNotificationRequest.builder()
                    .title("Medication Reminder")
                    .body("Time to take your blood pressure medication")
                    .targetToken("fcm-token-abc123")
                    .targetUserId(42L)
                    .userType("PATIENT")
                    .notificationType("MEDICATION_REMINDER")
                    .deepLink("/medications/reminder/1")
                    .data(Map.of("medicationId", "123"))
                    .build();

            assertEquals("Medication Reminder", req.getTitle());
            assertEquals("Time to take your blood pressure medication", req.getBody());
            assertEquals("fcm-token-abc123", req.getTargetToken());
            assertEquals(42L, req.getTargetUserId());
            assertEquals("PATIENT", req.getUserType());
            assertEquals("MEDICATION_REMINDER", req.getNotificationType());
            assertEquals("/medications/reminder/1", req.getDeepLink());
            assertEquals("123", req.getData().get("medicationId"));
        }

        @Test
        @DisplayName("emergency notification type")
        void emergencyType() {
            FirebaseNotificationRequest req = FirebaseNotificationRequest.builder()
                    .title("SOS Emergency")
                    .body("Patient needs immediate assistance")
                    .notificationType("EMERGENCY")
                    .targetUserId(10L)
                    .userType("CAREGIVER")
                    .build();

            assertEquals("EMERGENCY", req.getNotificationType());
            assertEquals("CAREGIVER", req.getUserType());
        }

        @Test
        @DisplayName("image URL is optional")
        void imageUrlOptional() {
            FirebaseNotificationRequest req = FirebaseNotificationRequest.builder()
                    .title("Test")
                    .body("Test body")
                    .imageUrl("https://example.com/icon.png")
                    .build();

            assertEquals("https://example.com/icon.png", req.getImageUrl());
        }
    }

    @Nested
    @DisplayName("NotificationSettingDTO")
    class NotificationSettingDTOTests {

        @Test
        @DisplayName("builder creates record with all fields")
        void builderCreatesAll() {
            Instant now = Instant.now();
            NotificationSettingDTO dto = NotificationSettingDTO.builder()
                    .id(1L)
                    .userId(42L)
                    .gamification(true)
                    .emergency(true)
                    .videoCall(true)
                    .audioCall(false)
                    .sms(true)
                    .significantVitals(true)
                    .createdAt(now)
                    .updatedAt(now)
                    .build();

            assertEquals(1L, dto.id());
            assertEquals(42L, dto.userId());
            assertTrue(dto.gamification());
            assertTrue(dto.emergency());
            assertTrue(dto.videoCall());
            assertFalse(dto.audioCall());
            assertTrue(dto.sms());
            assertTrue(dto.significantVitals());
        }

        @Test
        @DisplayName("all notifications disabled")
        void allDisabled() {
            NotificationSettingDTO dto = NotificationSettingDTO.builder()
                    .userId(1L)
                    .gamification(false)
                    .emergency(false)
                    .videoCall(false)
                    .audioCall(false)
                    .sms(false)
                    .significantVitals(false)
                    .build();

            assertFalse(dto.gamification());
            assertFalse(dto.emergency());
            assertFalse(dto.videoCall());
            assertFalse(dto.audioCall());
            assertFalse(dto.sms());
            assertFalse(dto.significantVitals());
        }
    }

    @Nested
    @DisplayName("ScheduledNotificationDTO")
    class ScheduledNotificationDTOTests {

        @Test
        @DisplayName("builder sets all required fields")
        void builderSetsRequired() {
            ScheduledNotificationDTO dto = ScheduledNotificationDTO.builder()
                    .receiverId(42L)
                    .title("Medication Reminder")
                    .body("Take your 10am medication")
                    .scheduledTime("2026-03-17T10:00:00")
                    .build();

            assertEquals(42L, dto.getReceiverId());
            assertEquals("Medication Reminder", dto.getTitle());
            assertEquals("Take your 10am medication", dto.getBody());
            assertEquals("2026-03-17T10:00:00", dto.getScheduledTime());
        }

        @Test
        @DisplayName("notificationType is optional")
        void notificationTypeOptional() {
            ScheduledNotificationDTO dto = ScheduledNotificationDTO.builder()
                    .receiverId(1L)
                    .title("Test")
                    .body("Test body")
                    .scheduledTime("2026-03-17T14:00:00")
                    .notificationType("REMINDER")
                    .build();

            assertEquals("REMINDER", dto.getNotificationType());
        }

        @Test
        @DisplayName("no-arg constructor creates null fields")
        void noArgConstructor() {
            ScheduledNotificationDTO dto = new ScheduledNotificationDTO();
            assertNull(dto.getReceiverId());
            assertNull(dto.getTitle());
            assertNull(dto.getScheduledTime());
        }
    }
}
