package com.careconnect.service.invoice;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.llm.enabled", havingValue = "true", matchIfMissing = false)
public class LlmExtractionService {

    private final AIServiceFactory aiServiceFactory;

    public String extractInvoiceData(String rawInvoiceText) {

        String systemMessageText = """
                You are an invoice extraction engine.
                
                Extract invoice data and return ONLY valid JSON.
                
                Do NOT explain anything.
                Do NOT return text.
                Do NOT use markdown.
                
                Return EXACTLY this format:
                
                {
                  "invoiceNumber": "",
                  "provider": {
                    "name": ""
                  },
                  "amounts": {
                    "total": 0
                  }
                }
                
                Only return JSON.
                """;

        String prompt = systemMessageText + "\n\nInvoice:\n" + rawInvoiceText;

        System.out.println("===== CALLING BEDROCK =====");
        System.out.println("Prompt:\n" + prompt);

        ChatRequest request = new ChatRequest();
        request.setMessage(prompt);
        request.setUserId(1L); // required field
        request.setPatientId(null);

        ChatResponse response = aiServiceFactory.getService().processChat(request);

        String result = response.getAiResponse();

        return result == null ? "" : result.trim();
    }
}