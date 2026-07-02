package com.careconnect.ai;

import com.careconnect.service.DeepSeekService;
import com.careconnect.service.BedrockAIChatService;

import jakarta.annotation.PostConstruct;
import lombok.extern.slf4j.Slf4j;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Slf4j
@Component
public class AIServiceFactory {

    private final DeepSeekService deepSeekService;
    private final BedrockAIChatService bedrockService;

    @Value("${careconnect.ai.provider}")
    private String provider;

    public AIServiceFactory(ObjectProvider<DeepSeekService> deepSeekServiceProvider,
                        ObjectProvider<BedrockAIChatService> bedrockServiceProvider) {
        this.deepSeekService = deepSeekServiceProvider.getIfAvailable();
        this.bedrockService = bedrockServiceProvider.getIfAvailable();
    }

    @PostConstruct
    public void logSelectedProvider() {
        log.info("======================================");
        log.info("AI PROVIDER SELECTED: {}", provider.toUpperCase());

        switch (provider.toLowerCase()) {
            case "bedrock" ->
                log.info("Using AWS Bedrock (Nova Lite / Claude)");
            case "deepseek" ->
                log.info("Using DeepSeek (OpenRouter)");
            default ->
                log.warn("Unknown AI provider: {}", provider);
        }

        log.info("======================================");
    }

    public AIService getService() {
        return switch (provider.toLowerCase()) {
            case "deepseek" -> {
                if (deepSeekService == null) {
                    throw new RuntimeException("DeepSeekService not available");
                }
                yield deepSeekService;
            }
            case "bedrock" -> {
                if (bedrockService == null) {
                    throw new RuntimeException("BedrockService not available");
                }
                yield bedrockService;
            }
            default -> throw new RuntimeException("Unknown provider: " + provider);
        };
    }
}
