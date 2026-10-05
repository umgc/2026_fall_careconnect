package com.careconnect.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

import java.util.Map;

@Validated
@ConfigurationProperties(prefix = "ai")
public class AiProperties {

    private Map<String, ProviderProps> providers;

    public Map<String, ProviderProps> getProviders() {
        return providers;
    }

    public void setProviders(Map<String, ProviderProps> providers) {
        this.providers = providers;
    }

    public static class ProviderProps {
        private String apiKey;
        private String model;
        private String baseUrl; // OpenAI-compatible base URL
        private Double temperature = 0.2;
        private Integer maxTokens = 1500;

        public String getApiKey() {
            return apiKey;
        }

        public void setApiKey(String apiKey) {
            this.apiKey = apiKey;
        }

        public String getModel() {
            return model;
        }

        public void setModel(String model) {
            this.model = model;
        }

        public String getBaseUrl() {
            return baseUrl;
        }

        public void setBaseUrl(String baseUrl) {
            this.baseUrl = baseUrl;
        }

        public Double getTemperature() {
            return temperature;
        }

        public void setTemperature(Double temperature) {
            this.temperature = temperature;
        }

        public Integer getMaxTokens() {
            return maxTokens;
        }

        public void setMaxTokens(Integer maxTokens) {
            this.maxTokens = maxTokens;
        }
    }
}