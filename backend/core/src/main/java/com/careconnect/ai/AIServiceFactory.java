package com.careconnect.ai;

import com.careconnect.service.DeepSeekService;
import com.careconnect.service.BedrockAIChatService;
import com.careconnect.service.OllamaService;
import com.careconnect.service.ColibriService;

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
    private final OllamaService ollamaService;
    private final ColibriService colibriService;

    @Value("${careconnect.ai.provider:bedrock}")
    private String provider;

    public AIServiceFactory(ObjectProvider<DeepSeekService> deepSeekServiceProvider,
                            ObjectProvider<BedrockAIChatService> bedrockServiceProvider,
                            ObjectProvider<OllamaService> ollamaServiceProvider,
                            ObjectProvider<ColibriService> colibriServiceProvider) {
        this.deepSeekService = deepSeekServiceProvider.getIfAvailable();
        this.bedrockService = bedrockServiceProvider.getIfAvailable();
        this.ollamaService = ollamaServiceProvider.getIfAvailable();
        this.colibriService = colibriServiceProvider.getIfAvailable();
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
            case "ollama" -> {
                log.info("======================================");
                log.info("Using Local Ollama Inference (HIPAA-Safe / On-Premise)");
                log.info("======================================");
                if (ollamaService == null) {
                    log.error("Ollama provider selected but OllamaService is not available. Ensure careconnect.ai.provider=ollama.");
                }
            }
            case "colibri" -> {
                log.info("======================================");
                log.info("Using Local Colibri MoE Inference (HIPAA-Safe / NVMe-Streamed)");
                log.info("======================================");
                if (colibriService == null) {
                    log.error("Colibri provider selected but ColibriService is not available. Ensure careconnect.ai.provider=colibri.");
                }
            }
            default -> {
                log.error("======================================");
                log.error("CONFIGURATION ERROR: Unknown AI provider '{}'", provider);
                log.error("Valid values: 'bedrock', 'deepseek', 'ollama', 'colibri'");
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
            case "ollama" -> {
                if (ollamaService == null) {
                    throw new IllegalStateException(
                        "AI provider is configured as 'ollama' but OllamaService " +
                        "is not available. Check that careconnect.ai.provider=ollama is set."
                    );
                }
                yield ollamaService;
            }
            case "colibri" -> {
                if (colibriService == null) {
                    throw new IllegalStateException(
                        "AI provider is configured as 'colibri' but ColibriService " +
                        "is not available. Check that careconnect.ai.provider=colibri is set."
                    );
                }
                yield colibriService;
            }
            default -> throw new IllegalStateException(
                "Unknown AI provider '" + provider + "'. " +
                "Valid values are: 'bedrock', 'deepseek', 'ollama', 'colibri'. " +
                "Set AI_MODEL_PROVIDER environment variable to a valid value."
            );
        };
    }
}