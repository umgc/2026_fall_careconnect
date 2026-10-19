package com.careconnect.controller;

import com.careconnect.ai.bedrock.BedrockTestService;
import com.careconnect.ai.bedrock.dto.BedrockResponse;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/bedrock")
public class BedrockTestController {

    private final BedrockTestService service;

    /**
     * Constructor injection of Bedrock service
     * Spring automatically injects the service bean
     */

    public BedrockTestController(BedrockTestService service) {
        this.service = service;
    }

    /**
     * Simple Get endpoint to test Bedrock
     * <p>
     * Example:
     * http://localhost:8081/api/bedrock/test?prompt=Hello
     *
     * @param prompt The user input text
     * @return Raw JSON response from Bedrock
     */

    @GetMapping("/test")
    public BedrockResponse test(@RequestParam String prompt) {
        // Call Bedrock service
        String result = service.testPrompt(prompt);

        // Wrap result inside DTO
        return new BedrockResponse(result);
    }
}