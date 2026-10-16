package com.careconnect.websocket.apigw;

import java.net.URI;
import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.DeleteConnectionRequest;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.GoneException;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.PostToConnectionRequest;

/**
 * Pushes to and closes API Gateway WebSocket connections through the {@code @connections} API.
 */
public class ApiGatewayConnectionClient implements AutoCloseable {

    private final ApiGatewayManagementApiClient client;

    ApiGatewayConnectionClient(final ApiGatewayManagementApiClient client) {
        this.client = client;
    }

    /**
     * Builds a client for one WebSocket API stage.
     *
     * @param callbackEndpoint {@code https://{api-id}.execute-api.{region}.amazonaws.com/{stage}}
     * @param region           AWS region of the API
     * @return a client using the default credentials chain (the ECS task role in AWS)
     */
    public static ApiGatewayConnectionClient create(final String callbackEndpoint, final String region) {
        return new ApiGatewayConnectionClient(ApiGatewayManagementApiClient.builder()
                .endpointOverride(URI.create(callbackEndpoint))
                .region(Region.of(region))
                .credentialsProvider(DefaultCredentialsProvider.create())
                .build());
    }

    /**
     * Sends a text frame to a connection.
     *
     * @return {@code false} when the connection no longer exists
     * @throws software.amazon.awssdk.core.exception.SdkException for any other failure
     */
    public boolean post(final String connectionId, final String payload) {
        try {
            client.postToConnection(PostToConnectionRequest.builder()
                    .connectionId(connectionId)
                    .data(SdkBytes.fromUtf8String(payload))
                    .build());
            return true;
        } catch (GoneException e) {
            return false;
        }
    }

    /**
     * Closes a connection. A connection that is already gone is not an error.
     */
    public void delete(final String connectionId) {
        try {
            client.deleteConnection(DeleteConnectionRequest.builder().connectionId(connectionId).build());
        } catch (GoneException ignored) {
            // Already closed — nothing to do.
        }
    }

    @Override
    public void close() {
        client.close();
    }
}
