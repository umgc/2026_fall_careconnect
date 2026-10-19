package com.careconnect.dto;

import lombok.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

import java.time.LocalDateTime;
import java.util.List;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ChatResponse {

    private String conversationId;
    private String message;
    private String aiResponse;
    private Long messageId;

    // Metadata
    private String aiProvider;
    private String modelUsed;
    private Integer tokensUsed;
    private Long processingTimeMs;
    private Double temperatureUsed;

    // Context information
    private List<String> contextIncluded;
    private Boolean isNewConversation;
    private LocalDateTime timestamp;

    // Conversation info
    private String conversationTitle;
    private Integer totalMessagesInConversation;

    // Usage tracking
    private Integer totalTokensUsedInConversation;
    private Boolean approachingTokenLimit;

    // Error handling
    @Builder.Default
    private Boolean success = true;
    private String errorMessage;
    private String errorCode;

    // Explicit getter for compatibility
    public Boolean getSuccess() {
        return success;
    }
}
