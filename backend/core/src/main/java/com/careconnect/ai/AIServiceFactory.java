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

    @Value("${careconnect.ai.provider:bedrock}")
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
            case "bedrock" -> {
                log.info("Using AWS Bedrock (Nova Lite / Claude)");
                if (bedrockService == null) {
                    log.error("======================================");
                    log.error("CONFIGURATION ERROR: AI provider is set to 'bedrock'");
                    log.error("but BedrockAIChatService is not available.");
                    log.error("Ensure careconnect.aws.enabled=true and AWS");
                    log.error("credentials are configured in your .env file.");
                    log.error("AI features will fail at runtime until this is resolved.");
                    log.error("======================================");
                }
            }
            case "deepseek" -> {
                log.warn("======================================");
                log.warn("WARNING: AI provider is set to 'deepseek'.");
                log.warn("DeepSeek is not the approved provider for this environment.");
                log.warn("Set AI_MODEL_PROVIDER=bedrock to use AWS Bedrock.");
                log.warn("======================================");
                if (deepSeekService == null) {
                    log.error("DeepSeek provider selected but DeepSeekService is not available.");
                }
            }
            default -> {
                log.error("======================================");
                log.error("CONFIGURATION ERROR: Unknown AI provider '{}'", provider);
                log.error("Valid values: 'bedrock', 'deepseek'");
                log.error("Defaulting will NOT occur - AI features will fail at runtime.");
                log.error("======================================");
            }
        }

        log.info("======================================");
    }

    public AIService getService() {
        return switch (provider.toLowerCase()) {
            case "deepseek" -> {
                if (deepSeekService == null) {
                    throw new IllegalStateException(
                        "AI provider is configured as 'deepseek' but DeepSeekService " +
                        "is not available. Check careconnect.deepseek.enabled and " +
                        "DEEPSEEK_API_KEY in your environment."
                    );
                }
                yield deepSeekService;
            }
            case "bedrock" -> {
                if (bedrockService == null) {
                    throw new IllegalStateException(
                        "AI provider is configured as 'bedrock' but BedrockAIChatService " +
                        "is not available. Ensure careconnect.aws.enabled=true and " +
                        "AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY) " +
                        "are set in your .env file."
                    );
                }
                yield bedrockService;
            }
            default -> throw new IllegalStateException(
                "Unknown AI provider '" + provider + "'. " +
                "Valid values are: 'bedrock', 'deepseek'. " +
                "Set AI_MODEL_PROVIDER environment variable to a valid value."
            );
        };
    }
}