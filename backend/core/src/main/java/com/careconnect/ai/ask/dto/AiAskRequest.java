package com.careconnect.ai.ask.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class AiAskRequest {

    @NotBlank(message = "Question must not be blank")
    @Size(max = 1000, message = "Question must not exceed 1000 characters")
    private String question;

    public AiAskRequest() {}

    public String getQuestion() { return question; }
    public void setQuestion(String question) { this.question = question; }
}