package com.careconnect.controller;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import org.springframework.web.bind.annotation.*;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;

import java.util.List;
import java.util.Map;

@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = false)
@RestController
@RequestMapping("/v1/api/test")
public class TextractTestController {

    private final AIServiceFactory aiServiceFactory;

    public TextractTestController(AIServiceFactory aiServiceFactory) {
        this.aiServiceFactory = aiServiceFactory;
    }

    @PostMapping("/extract-invoice")
    public String extractInvoice(@RequestBody Map<String, Object> body) {

        List<String> lines = (List<String>) body.get("lines");
        String invoiceText = String.join("\n", lines);

        String prompt = """
                You are an invoice data extraction engine.
                
                Extract structured invoice data from the text below.
                
                Return ONLY valid JSON matching this schema:
                
                {
                  "invoice_number": "",
                  "invoice_date": "",
                  "payment_due_date": "",
                  "vendor_name": "",
                  "vendor_email": "",
                  "vendor_address": "",
                  "bill_to_name": "",
                  "bill_to_address": "",
                  "line_items": [
                    {
                      "description": "",
                      "quantity": "",
                      "unit_cost": "",
                      "amount": ""
                    }
                  ],
                  "subtotal": "",
                  "tax": "",
                  "total": "",
                  "amount_due": ""
                }
                
                Rules:
                - Return ONLY JSON
                - No explanations
                - No markdown
                - No extra text
                
                Invoice Text:
                """ + invoiceText;

        ChatRequest request = new ChatRequest();
        request.setMessage(prompt);

        ChatResponse response = aiServiceFactory
                .getService()
                .processChat(request);

        return response.getAiResponse();
    }
}