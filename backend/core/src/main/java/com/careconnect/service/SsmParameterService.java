package com.careconnect.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;
import software.amazon.awssdk.services.ssm.model.ParameterNotFoundException;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Service for retrieving parameters from AWS Systems Manager Parameter Store.
 * Only active when AWS is enabled (production environment).
 */
@Service
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = false)
public class SsmParameterService {

    private static final Logger logger = LoggerFactory.getLogger(SsmParameterService.class);

    private final SsmClient ssmClient;
    private final Map<String, String> parameterCache;

    public SsmParameterService(SsmClient ssmClient) {
        this.ssmClient = ssmClient;
        this.parameterCache = new ConcurrentHashMap<>();
        logger.info("SsmParameterService initialized - will fetch secrets from AWS SSM Parameter Store");
    }

    /**
     * Retrieves a parameter value from SSM Parameter Store.
     * Parameters are cached to reduce API calls.
     *
     * @param parameterName  the name of the SSM parameter (e.g., "/careconnect/prod/stripe-secret-key")
     * @param withDecryption whether to decrypt SecureString parameters
     * @return the parameter value, or null if not found
     */
    public String getParameter(String parameterName, boolean withDecryption) {
        // Check cache first
        String cacheKey = parameterName + ":" + withDecryption;
        if (parameterCache.containsKey(cacheKey)) {
            logger.debug("Retrieved parameter from cache: {}", parameterName);
            return parameterCache.get(cacheKey);
        }

        try {
            GetParameterRequest request = GetParameterRequest.builder()
                    .name(parameterName)
                    .withDecryption(withDecryption)
                    .build();

            GetParameterResponse response = ssmClient.getParameter(request);
            String value = response.parameter().value();

            // Cache the value
            parameterCache.put(cacheKey, value);
            logger.info("Successfully retrieved parameter from SSM: {}", parameterName);

            return value;
        } catch (ParameterNotFoundException e) {
            logger.error("Parameter not found in SSM: {}", parameterName);
            return null;
        } catch (Exception e) {
            logger.error("Error retrieving parameter from SSM: {}", parameterName, e);
            return null;
        }
    }

    /**
     * Retrieves a parameter value from SSM Parameter Store with decryption enabled.
     * Convenience method for encrypted parameters (SecureString type).
     *
     * @param parameterName the name of the SSM parameter
     * @return the decrypted parameter value, or null if not found
     */
    public String getParameter(String parameterName) {
        return getParameter(parameterName, true);
    }

    /**
     * Retrieves a parameter value or returns a default value if not found.
     *
     * @param parameterName the name of the SSM parameter
     * @param defaultValue  the default value to return if parameter is not found
     * @return the parameter value or default value
     */
    public String getParameterOrDefault(String parameterName, String defaultValue) {
        String value = getParameter(parameterName);
        return value != null ? value : defaultValue;
    }

    /**
     * Clears the parameter cache.
     * Useful for testing or when parameters are updated in SSM.
     */
    public void clearCache() {
        parameterCache.clear();
        logger.info("SSM parameter cache cleared");
    }
}