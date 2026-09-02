package com.careconnect.service.ai;

import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.model.chat.ChatModel;
import dev.langchain4j.model.chat.response.ChatResponse;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

import java.nio.charset.StandardCharsets;
import java.util.List;

public class BedrockChatModel implements ChatModel {

    private final BedrockRuntimeClient client;
    private final String modelId;
    private final double temperature;

    public BedrockChatModel(String region, String modelId, double temperature) {
        this.client = BedrockRuntimeClient.builder()
                .region(Region.of(region))
                .build();
        this.modelId = modelId;
        this.temperature = temperature;
    }

    @Override
    public ChatResponse chat(List<ChatMessage> messages) {

        // Convert all messages to a simple text prompt
        String prompt = messages.stream()
                .map(Object::toString)
                .reduce("", (a, b) -> a + "\n" + b);

        String body = """
                {
                    "inputText": "%s",
                    "textGenerationConfig": {
                    "maxTokenCount": 2048,
                    "temperature": %f
                    }
                }
                """.formatted(
                prompt.replace("\"", "\\\""),
                temperature
        );

        InvokeModelRequest request = InvokeModelRequest.builder()
                .modelId(modelId)
                .contentType("application/json")
                .accept("application/json")
                .body(software.amazon.awssdk.core.SdkBytes.fromUtf8String(body))
                .build();

        InvokeModelResponse response = client.invokeModel(request);

        String responseBody = response.body().asUtf8String();

        return ChatResponse.builder()
                .aiMessage(AiMessage.from(responseBody))
                .build();
    }
}