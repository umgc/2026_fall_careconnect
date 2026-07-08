package com.careconnect.service;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatConversationSummary;
import com.careconnect.dto.ChatMessageSummary;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.dto.UserAIConfigDTO;
import com.careconnect.model.UserAIConfig;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.service.safety.AiOutputValidationService;
import com.careconnect.service.safety.AiOutputValidationService.ValidationResult;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger log = LoggerFactory.getLogger(BedrockAIChatAdapter.class);

    private final AIServiceFactory aiServiceFactory;
    private final AiOutputValidationService outputValidationService;
    // WBS 3.15.7: the documents-exclusion gate lives in MedicalContextService.
    // The live Bedrock path previously sent only the raw user message, so patient
    // context (and the data-source toggles) never reached the model. Assemble context
    // here — the single AIChatService entry point — before delegating to the model.
    private final MedicalContextService medicalContextService;
    private final UserAIConfigService userAIConfigService;

    @Override
    public ChatResponse processChat(ChatRequest request) {
        ChatResponse response = aiServiceFactory.getService().processChat(withMedicalContext(request));
        // Validate against the original request: the outbound prompt carries assembled
        // patient context, but the hold/reject gate reasons about the user's own question.
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

    /**
     * Prepend patient medical context to the user's message so it reaches the model.
     * The context honors the per-user data-source toggles (vitals/medications/notes/
     * mood-pain/allergies/documents — WBS 3.15.7). Fails open: on any error, or when
     * there is no patient scope, the original request is sent unchanged.
     */
    private ChatRequest withMedicalContext(ChatRequest request) {
        Long patientId = request.getPatientId();
        if (patientId == null) {
            // No patient scope (e.g. general support chat) — nothing to gate or include.
            return request;
        }
        try {
            UserAIConfigDTO configDto = userAIConfigService.getUserAIConfig(request.getUserId(), patientId);
            UserAIConfig aiConfig = userAIConfigService.convertDTOToEntity(configDto);
            String context = medicalContextService.buildPatientContext(patientId, request, aiConfig);
            if (context == null || context.isBlank()) {
                return request;
            }
            String userMessage = request.getMessage() == null ? "" : request.getMessage();
            request.setMessage(context + "\n\nUSER QUESTION:\n" + userMessage);
        } catch (Exception e) {
            // Never block the chat on context assembly — send the raw message instead.
            log.warn("Failed to assemble medical context for patient {}; sending message without context: {}",
                    patientId, e.getMessage());
        }
        return request;
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
