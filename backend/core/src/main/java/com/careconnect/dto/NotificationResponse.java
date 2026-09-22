package com.careconnect.dto;

import lombok.Builder;
import lombok.Data;

@Data
@Builder
public class NotificationResponse {
    private boolean success;
    private String message;
    private String messageId; // Firebase message ID
    private String error;
    private Long timestamp;

    public static NotificationResponse success(String messageId) {
        return NotificationResponse.builder()
                .success(true)
                .message("Notification sent successfully")
                .messageId(messageId)
                .timestamp(System.currentTimeMillis())
                .build();
    }

    public static NotificationResponse failure(String error) {
        return NotificationResponse.builder()
                .success(false)
                .message("Failed to send notification")
                .error(error)
                .timestamp(System.currentTimeMillis())
                .build();
    }
}
