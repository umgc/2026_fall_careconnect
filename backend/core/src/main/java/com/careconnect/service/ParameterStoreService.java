package com.careconnect.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.services.ssm.SsmClient;
import software.amazon.awssdk.services.ssm.model.GetParameterRequest;
import software.amazon.awssdk.services.ssm.model.GetParameterResponse;
import software.amazon.awssdk.services.ssm.model.SsmException;

@Service
@ConditionalOnProperty(name = "careconnect.aws.enabled", havingValue = "true", matchIfMissing = true)
public class ParameterStoreService {

    private static final Logger logger = LoggerFactory.getLogger(ParameterStoreService.class);
    private final SsmClient ssmClient;

    @Autowired(required = false)
    public ParameterStoreService(SsmClient ssmClient) {
        this.ssmClient = ssmClient;
    }

    /**
     * Retrieves a parameter from SSM Parameter Store
     *
     * @param parameterName  The name of the parameter to retrieve
     * @param withDecryption Whether to decrypt the parameter (for SecureString type)
     * @return The parameter value or null if not found
     */
    public String getParameter(String parameterName, boolean withDecryption) {
        try {
            GetParameterRequest request = GetParameterRequest.builder()
                    .name(parameterName)
                    .withDecryption(withDecryption)
                    .build();

            GetParameterResponse response = ssmClient.getParameter(request);
            return response.parameter().value();
        } catch (SsmException e) {
            logger.error("Error retrieving parameter {}: ", e.getMessage());
            logger.info("We are returning your initial parameter name");
            return parameterName;
        }
    }

    /**
     * Convenience method for retrieving a parameter with decryption
     */
    public String getSecureParameter(String parameterName) {
        return getParameter(parameterName, true);
    }
}

