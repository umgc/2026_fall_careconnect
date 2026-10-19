package com.careconnect.dto;

import com.careconnect.model.ChatMessage;
import lombok.*;

import java.time.LocalDateTime;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatMessageSummary {

    private Long messageId;
    private ChatMessage.MessageType messageType;
    private String content;
    private Integer tokensUsed;
    private Long processingTimeMs;
    private String aiModelUsed;
    private LocalDateTime createdAt;
}
