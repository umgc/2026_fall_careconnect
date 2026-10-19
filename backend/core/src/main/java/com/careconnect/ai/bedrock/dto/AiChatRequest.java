package com.careconnect.ai.bedrock.dto;

/**
 * DTO representing a request coming from the frontend
 * when a user sends a message to the AI
 */

public class AiChatRequest {
    private String message;     //Message user inputs

    public AiChatRequest() {
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }
}
