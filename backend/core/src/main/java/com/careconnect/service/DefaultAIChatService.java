package com.careconnect.service;

import com.careconnect.ai.AIService;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@ConditionalOnProperty(
        name = "careconnect.ai.provider",
        havingValue = "deepseek",
        matchIfMissing = false
)
public class DefaultAIChatService implements AIService {

    public DefaultAIChatService() {
        log.info("DefaultAIChatService initialized (DeepSeek path disabled)");
    }

    //Dummy constructor to satisfy existing tests
    public DefaultAIChatService(
            Object chatModel,
            Object userAIConfigRepository,
            Object chatConversationRepository,
            Object chatMessageRepository,
            Object patientRepository,
            Object medicalContextService,
            Object patientContextRetrievalService,
            Object chatMemoryFactory,
            Object chatAuditService,
            Object caregiverPatientLinkService,
            Object inputSanitizationService,
            Object responseSanitizationService,
            Object langChainGovernanceService,
            Object aiChatCacheService,
            Object securityAuditService,
            Object documentProcessingService
    ) {
        log.warn("Test constructor used - DefaultAIChatService is disabled");
    }

    /**
     * DeepSeek path DISABLED
     * Bedrock is used instead via AIServiceFactory
     */
    @Override
    public ChatResponse processChat(ChatRequest request) {

        log.warn("DefaultAIChatService should NOT be used. Provider is not deepseek.");

        throw new UnsupportedOperationException(
                "DeepSeek AI is disabled. Application is configured to use Bedrock."
        );
    }

    // =============================
    // Stubbed methods (required by interface)
    // =============================

    @Override
    public List<ChatConversationSummary> getPatientConversations(Long patientId) {
        throw new UnsupportedOperationException("Not supported in DeepSeek-disabled mode");
    }

    @Override
    public List<ChatMessageSummary> getConversationMessages(String conversationId) {
        throw new UnsupportedOperationException("Not supported in DeepSeek-disabled mode");
    }

    @Override
    public List<ChatMessageSummary> getRecentMessagesForUser(Long userId, int limit) {
        throw new UnsupportedOperationException("Not supported in DeepSeek-disabled mode");
    }

    @Override
    public void deactivateConversation(String conversationId) {
        throw new UnsupportedOperationException("Not supported in DeepSeek-disabled mode");
    }
}
