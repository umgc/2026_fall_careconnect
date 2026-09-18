package com.careconnect.service;

import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;

import java.util.List;

public interface AIChatService {
    ChatResponse processChat(ChatRequest request);

    // Conversation management
    List<com.careconnect.dto.ChatConversationSummary> getPatientConversations(Long patientId);

    List<com.careconnect.dto.ChatMessageSummary> getConversationMessages(String conversationId);

    List<com.careconnect.dto.ChatMessageSummary> getRecentMessagesForUser(Long userId, int limit);

    void deactivateConversation(String conversationId);
}
