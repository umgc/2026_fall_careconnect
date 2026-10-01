package com.careconnect.service.homecare;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.model.homecare.HomeCareDocumentType;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

/**
 * Reuses the invoice LLM extraction pattern for home-care onboarding
 * documents. The prompt embeds the per-document-type JSON schema so the
 * model output is restricted to exactly the fields allowed for that type.
 */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.llm.enabled", havingValue = "true", matchIfMissing = false)
public class HomeCareLlmExtractionService {

    private final AIServiceFactory aiServiceFactory;

    public String extractDocumentData(HomeCareDocumentType documentType, String rawDocumentText) {

        String systemMessageText = """
                You are a home care onboarding document extraction engine.
                
                Extract data from a %s and return ONLY valid JSON.
                
                Do NOT explain anything.
                Do NOT return text.
                Do NOT use markdown.
                Do NOT add fields that are not in the format below.
                
                Return EXACTLY this format:
                
                %s
                
                Use an empty string "" for any value that is not present in the document.
                Only return JSON.
                """.formatted(documentType.getDisplayName(), documentType.promptSchemaJson());

        String prompt = systemMessageText + "\n\nDocument:\n" + rawDocumentText;

        ChatRequest request = new ChatRequest();
        request.setMessage(prompt);
        request.setUserId(1L); // required field
        request.setPatientId(null);

        ChatResponse response = aiServiceFactory.getService().processChat(request);

        String result = response.getAiResponse();

        return result == null ? "" : result.trim();
    }
}
