package com.careconnect.ai.bedrock.dto;

/**
 * DTO used to return a structured AI response
 * <p>
 * Instead of returning raw strings, we wrap the response
 * in a JSON object for cleaner frontend integration.
 */

public class BedrockResponse {

    private String response;

    /**
     * Constructor used to create response object
     */
    public BedrockResponse(String response) {
        this.response = response;
    }

    public String getResponse() {
        return response;
    }
}
