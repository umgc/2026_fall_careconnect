package com.careconnect.config;

import com.careconnect.service.SsmParameterService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

import javax.annotation.PostConstruct;

/**
 * Configuration class for loading secrets from AWS SSM Parameter Store in production.
 * In development, environment variables are used instead.
 * <p>
 * SSM Parameter Naming Convention:
 * /careconnect/prod/{parameter-name}
 * <p>
 * Example:
 * - /careconnect/prod/stripe-secret-key
 * - /careconnect/prod/openai-api-key
 * - /careconnect/prod/jwt-secret
 */
@Configuration
@Profile("prod")
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = true)
public class SsmConfig {

    private static final Logger LOGGER = LoggerFactory.getLogger(SsmConfig.class);
    private static final String SSM_PARAMETER_PREFIX = "/careconnect/prod/";

    @Autowired(required = false)
    private SsmParameterService ssmParameterService;

    @PostConstruct
    public void init() {
        if (ssmParameterService != null) {
            LOGGER.info("SSM Configuration initialized - production secrets will be loaded from AWS SSM Parameter Store");
            LOGGER.info("SSM Parameter prefix: {}", SSM_PARAMETER_PREFIX);
        } else {
            LOGGER.warn("SSM Parameter Service not available - falling back to environment variables");
        }
    }

    /**
     * Provides Stripe secret key from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/stripe-secret-key
     */
    @Bean
    public String stripeSecretKey() {
        return getSsmParameter("stripe-secret-key", System.getenv("STRIPE_SECRET_KEY"));
    }

    /**
     * Provides Stripe webhook secret from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/stripe-webhook-secret
     */
    @Bean
    public String stripeWebhookSecret() {
        return getSsmParameter("stripe-webhook-secret", System.getenv("STRIPE_WEBHOOK_SIGNING_SECRET"));
    }

    /**
     * Provides OpenAI API key from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/openai-api-key
     */
    @Bean
    public String openaiApiKey() {
        return getSsmParameter("openai-api-key", System.getenv("OPENAI_API_KEY"));
    }

    /**
     * Provides DeepSeek API key from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/deepseek-api-key
     */
    @Bean
    public String deepseekApiKey() {
        return getSsmParameter("deepseek-api-key", System.getenv("DEEPSEEK_API_KEY"));
    }

    /**
     * Provides JWT secret from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/jwt-secret
     */
    @Bean
    public String jwtSecret() {
        return getSsmParameter("jwt-secret", System.getenv("SECURITY_JWT_SECRET"));
    }

    /**
     * Provides SendGrid API key from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/sendgrid-api-key
     */
    @Bean
    public String sendgridApiKey() {
        return getSsmParameter("sendgrid-api-key", System.getenv("SENDGRID_API_KEY"));
    }

    /**
     * Provides Google OAuth client ID from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/google-client-id
     */
    @Bean
    public String googleClientId() {
        return getSsmParameter("google-client-id", System.getenv("GOOGLE_CLIENT_ID"));
    }

    /**
     * Provides Google OAuth client secret from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/google-client-secret
     */
    @Bean
    public String googleClientSecret() {
        return getSsmParameter("google-client-secret", System.getenv("GOOGLE_CLIENT_SECRET"));
    }

    /**
     * Provides Fitbit OAuth client ID from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/fitbit-client-id
     */
    @Bean
    public String fitbitClientId() {
        return getSsmParameter("fitbit-client-id", System.getenv("FITBIT_CLIENT_ID"));
    }

    /**
     * Provides Fitbit OAuth client secret from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/fitbit-client-secret
     */
    @Bean
    public String fitbitClientSecret() {
        return getSsmParameter("fitbit-client-secret", System.getenv("FITBIT_CLIENT_SECRET"));
    }

    /**
     * Provides database password from SSM Parameter Store.
     * SSM Parameter: /careconnect/prod/db-password
     */
    @Bean
    public String databasePassword() {
        return getSsmParameter("db-password", System.getenv("DB_PASSWORD"));
    }

    /**
     * Helper method to retrieve parameter from SSM or fall back to environment variable.
     *
     * @param parameterName the SSM parameter name (without prefix)
     * @param envFallback   the environment variable fallback value
     * @return the parameter value
     */
    private String getSsmParameter(String parameterName, String envFallback) {
        if (ssmParameterService == null) {
            LOGGER.warn("SSM service not available, using environment variable for: {}", parameterName);
            return envFallback;
        }

        String fullParameterName = SSM_PARAMETER_PREFIX + parameterName;
        String value = ssmParameterService.getParameterOrDefault(fullParameterName, envFallback);

        if (value == null || value.equals(envFallback)) {
            LOGGER.warn("Using environment variable fallback for parameter: {}", parameterName);
        } else {
            LOGGER.info("Loaded parameter from SSM: {}", parameterName);
        }

        return value;
    }
}