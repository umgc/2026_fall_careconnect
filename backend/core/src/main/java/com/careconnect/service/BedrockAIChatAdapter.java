package com.careconnect.service;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.service.safety.AiOutputValidationService;
import com.careconnect.service.safety.AiOutputValidationService.ValidationResult;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class BedrockAIChatAdapter implements AIChatService {

    /** Shown to the user in place of held/rejected output — the raw text is never delivered. */
    private static final String HELD_MESSAGE =
            "This response is being reviewed by a member of your care team before it can be shown. " +
            "Please check back shortly.";
    private static final String REJECTED_MESSAGE =
            "A response could not be provided for this request. Please rephrase or contact your care team.";

    private final AIServiceFactory aiServiceFactory;
    private final AiOutputValidationService outputValidationService;

    @Override
    public ChatResponse processChat(ChatRequest request) {
        ChatResponse response = aiServiceFactory.getService().processChat(request);
        return applyOutputValidation(request, response);
    }

    /** WBS 3.15.3 — hold/reject gate: held or rejected output is replaced with a safe placeholder. */
    private ChatResponse applyOutputValidation(ChatRequest request, ChatResponse response) {
        if (response == null || Boolean.FALSE.equals(response.getSuccess())) {
            return response;
        }
        ValidationResult result = outputValidationService.validate(
                response.getAiResponse(),
                request.getMessage(),
                AuditSourceFeature.ASK_AI,
                request.getUserId(),
                request.getPatientId(),
                request.getConversationId());

        switch (result.outcome()) {
            case HOLD -> {
                response.setAiResponse(HELD_MESSAGE);
                response.setErrorCode("HELD_FOR_REVIEW");
                response.setErrorMessage(result.reason());
            }
            case REJECT -> {
                response.setAiResponse(REJECTED_MESSAGE);
                response.setSuccess(false);
                response.setErrorCode("OUTPUT_REJECTED");
                response.setErrorMessage(result.reason());
            }
            default -> { /* PASS — deliver as-is */ }
        }
        return response;
    }

    // 🚫 Not supported yet — safe stubs

    @Override
    public List<ChatConversationSummary> getPatientConversations(Long patientId) {
        throw new UnsupportedOperationException("Not supported in Bedrock mode yet.");
    }

    @Override
    public List<ChatMessageSummary> getConversationMessages(String conversationId) {
        throw new UnsupportedOperationException("Not supported in Bedrock mode yet.");
    }

    @Override
    public List<ChatMessageSummary> getRecentMessagesForUser(Long userId, int limit) {
        throw new UnsupportedOperationException("Not supported in Bedrock mode yet.");
    }

    @Override
    public void deactivateConversation(String conversationId) {
        throw new UnsupportedOperationException("Not supported in Bedrock mode yet.");
    }
}