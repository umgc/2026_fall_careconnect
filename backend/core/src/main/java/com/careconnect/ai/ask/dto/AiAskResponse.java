package com.careconnect.ai.ask.dto;

public class AiAskResponse {

    private final String answer;
    private final int chunksUsed;

    public AiAskResponse(String answer, int chunksUsed) {
        this.answer = answer;
        this.chunksUsed = chunksUsed;
    }

    public String getAnswer() { return answer; }
    public int getChunksUsed() { return chunksUsed; }
}