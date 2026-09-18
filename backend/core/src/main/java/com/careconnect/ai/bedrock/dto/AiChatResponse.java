package com.careconnect.ai.bedrock.dto;

/**
 * DTO returned to the frontend containing
 * the AI-generated response
 */

public class AiChatResponse {

    private String response;

    public AiChatResponse(String response) {
        this.response = response;
    }

    public String getResponse() {
        return response;
    }
}
