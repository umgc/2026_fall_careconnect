package com.careconnect;

import com.amazonaws.serverless.exceptions.ContainerInitializationException;
import com.amazonaws.serverless.proxy.model.AwsProxyRequest;
import com.amazonaws.serverless.proxy.model.AwsProxyResponse;
import com.amazonaws.serverless.proxy.spring.SpringBootLambdaContainerHandler;
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestStreamHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

public class CcLambdaHandler implements RequestStreamHandler {
    private static final Logger LOG = LoggerFactory.getLogger(CcLambdaHandler.class);
    private static final SpringBootLambdaContainerHandler<AwsProxyRequest, AwsProxyResponse> HANDLER;

    static {
        try {
            LOG.info("Initializing Lambda Handler");
            // Initialize the handler with specific configurations
            HANDLER = SpringBootLambdaContainerHandler
                    .getAwsProxyHandler(CareconnectBackendApplication.class);

            LOG.info("Lambda Handler initialized successfully");
        } catch (ContainerInitializationException e) {
            LOG.error("Failed to initialize Spring Boot application", e);
            throw new RuntimeException("Could not initialize Spring Boot application", e);
        }
    }

    @Override
    public void handleRequest(InputStream inputStream, OutputStream outputStream, Context context)
            throws IOException {
        try {
            LOG.info("Initializing Lambda in the handler again");

            // Process the request and write directly to output stream
            HANDLER.proxyStream(inputStream, outputStream, context);

            // Log after processing
            LOG.info("Response sent directly to output stream");
        } catch (Exception e) {
            LOG.error("Error processing request", e);
            throw new RuntimeException(e);
        }
    }
}