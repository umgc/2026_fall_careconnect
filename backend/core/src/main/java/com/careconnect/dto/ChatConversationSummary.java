package com.careconnect.dto;

import com.careconnect.model.ChatConversation;
import lombok.*;

import java.time.LocalDateTime;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatConversationSummary {

    private String conversationId;
    private String title;
    private ChatConversation.ChatType chatType;
    private String aiProvider;
    private String aiModel;
    private Integer totalMessages;
    private Integer totalTokensUsed;
    private LocalDateTime lastMessageAt;
    private LocalDateTime createdAt;
    private Boolean isActive;
}
