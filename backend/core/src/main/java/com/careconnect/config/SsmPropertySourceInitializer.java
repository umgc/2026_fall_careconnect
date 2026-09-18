package com.careconnect.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationContextInitializer;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.core.env.ConfigurableEnvironment;
import org.springframework.core.env.MapPropertySource;
import org.springframework.core.env.PropertySource;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.regions.providers.DefaultAwsRegionProviderChain;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;

import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Initializes SSM Parameter Store as a property source for production environment.
 * This class loads secrets from AWS SSM before the Spring context is fully initialized,
 * allowing them to be used in @Value annotations and application.properties.
 * <p>
 * To enable this initializer, add to application-prod.properties:
 * context.initializer.classes=com.careconnect.config.SsmPropertySourceInitializer
 *
 * <p>JWT and database credentials are injected by ECS from Secrets Manager ({@code SECURITY_JWT_SECRET},
 * {@code DB_PASSWORD}, {@code DB_USER}) and are intentionally excluded from SSM loading to avoid
 * overriding the CloudFormation-managed secret source.
 */
public class SsmPropertySourceInitializer implements ApplicationContextInitializer<ConfigurableApplicationContext> {

    private static final Logger LOGGER = LoggerFactory.getLogger(SsmPropertySourceInitializer.class);
    private static final String PROPERTY_SOURCE_NAME = "ssmPropertySource";
    private static final String ENVIRONMENT_PROPERTY = "ENVIRONMENT";
    private static final String SSM_PREFIX_PROPERTY = "CARECONNECT_SSM_PREFIX";

    // List of parameter names to load from SSM
    private static final List<String> SSM_PARAMETERS = Arrays.asList(
            "stripe-secret-key",
            "stripe-webhook-secret",
            "openai-api-key",
            "deepseek-api-key",
            "sendgrid-api-key",
            "google-client-id",
            "google-client-secret",
            "fitbit-client-id",
            "fitbit-client-secret",
            "firebase-service-account-key",
            "aws-access-key-id",
            "aws-secret-access-key",
            "kvs-stream-pool-arn"
    );

    // Mapping of SSM parameter names to Spring property names
    private static final Map<String, String> PARAMETER_MAPPING = new HashMap<String, String>() {{
        put("stripe-secret-key", "stripe.secret-key");
        put("stripe-webhook-secret", "stripe.webhook-secret");
        put("openai-api-key", "openai.api-key");
        put("deepseek-api-key", "spring.ai.openai.api-key");
        put("sendgrid-api-key", "careconnect.email.sendgrid.api-key");
        put("google-client-id", "spring.security.oauth2.client.registration.google.client-id");
        put("google-client-secret", "spring.security.oauth2.client.registration.google.client-secret");
        put("fitbit-client-id", "spring.security.oauth2.client.registration.fitbit.client-id");
        put("fitbit-client-secret", "spring.security.oauth2.client.registration.fitbit.client-secret");
        put("firebase-service-account-key", "firebase.service-account-key");
        put("aws-access-key-id", "aws.s3.access-key");
        put("aws-secret-access-key", "aws.s3.secret-key");
        put("kvs-stream-pool-arn", "careconnect.kvs.stream-pool-arn");
    }};

    /**
     * Resolves the SSM path prefix for secrets. ECS sets {@code ENVIRONMENT} from CloudFormation;
     * override entirely with {@code CARECONNECT_SSM_PREFIX} (must end with {@code /}).
     */
    static String resolveSsmPrefix(ConfigurableEnvironment environment) {
        String explicitPrefix = environment.getProperty(SSM_PREFIX_PROPERTY);
        if (explicitPrefix != null && !explicitPrefix.isBlank()) {
            return explicitPrefix.endsWith("/") ? explicitPrefix : explicitPrefix + "/";
        }
        String envName = environment.getProperty(ENVIRONMENT_PROPERTY, "prod");
        return "/careconnect/" + envName.trim() + "/";
    }

    @Override
    public void initialize(ConfigurableApplicationContext applicationContext) {
        ConfigurableEnvironment environment = applicationContext.getEnvironment();

        // Check if we're in production profile and AWS is enabled
        String[] activeProfiles = environment.getActiveProfiles();
        boolean isProduction = Arrays.asList(activeProfiles).contains("prod");

        // Check if AWS is enabled (default true if not specified)
        String awsEnabled = environment.getProperty("careconnect.aws.enabled", "true");

        if (!isProduction || !"true".equalsIgnoreCase(awsEnabled)) {
            LOGGER.info("SSM PropertySource not initialized - not in production mode or AWS disabled");
            return;
        }

        LOGGER.info("Initializing SSM Parameter Store property source for production...");

        String ssmPrefix = resolveSsmPrefix(environment);

        try {
            // Create SSM client
            Region region = new DefaultAwsRegionProviderChain().getRegion();
            SsmClient ssmClient = SsmClient.builder()
                    .region(region)
                    .credentialsProvider(DefaultCredentialsProvider.create())
                    .build();

            // Load parameters from SSM
            Map<String, Object> ssmProperties = loadParametersFromSsm(ssmClient, ssmPrefix);

            // Add SSM property source to environment
            if (!ssmProperties.isEmpty()) {
                PropertySource<?> ssmPropertySource = new MapPropertySource(PROPERTY_SOURCE_NAME, ssmProperties);
                environment.getPropertySources().addFirst(ssmPropertySource);
                LOGGER.info("SSM PropertySource initialized with {} parameters", ssmProperties.size());
            } else {
                LOGGER.warn("No SSM parameters loaded - application may use environment variable fallbacks");
            }

            // Close SSM client
            ssmClient.close();

        } catch (Exception e) {
            LOGGER.error("Failed to initialize SSM PropertySource - falling back to environment variables", e);
            // Don't fail application startup, just log the error and continue
        }
    }

    private Map<String, Object> loadParametersFromSsm(SsmClient ssmClient, String ssmPrefix) {
        Map<String, Object> properties = new HashMap<>();

        for (String parameterName : SSM_PARAMETERS) {
            String fullParameterName = ssmPrefix + parameterName;
            String springPropertyName = PARAMETER_MAPPING.get(parameterName);

            if (springPropertyName == null) {
                LOGGER.warn("No Spring property mapping found for SSM parameter: {}", parameterName);
                continue;
            }

            try {
                GetParameterRequest request = GetParameterRequest.builder()
                        .name(fullParameterName)
                        .withDecryption(true)
                        .build();

                GetParameterResponse response = ssmClient.getParameter(request);
                String value = response.parameter().value();

                properties.put(springPropertyName, value);
                LOGGER.info("Loaded SSM parameter: {} -> {}", fullParameterName, springPropertyName);

            } catch (Exception e) {
                LOGGER.warn("Could not load SSM parameter: {} - will use environment variable fallback if available",
                        fullParameterName);
            }
        }

        return properties;
    }
}