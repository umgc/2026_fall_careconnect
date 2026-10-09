package com.careconnect.websocket.apigw;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.apigatewaymanagementapi.ApiGatewayManagementApiClient;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.DeleteConnectionRequest;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.GoneException;
import software.amazon.awssdk.services.apigatewaymanagementapi.model.PostToConnectionRequest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.assertThatNoException;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link ApiGatewayConnectionClient}.
 *
 * <p>The AWS SDK client is mocked; these tests cover how {@code @connections} responses map to the
 * wrapper's results (delivered, gone, or failure), not the AWS call itself.
 */
@ExtendWith(MockitoExtension.class)
class ApiGatewayConnectionClientTest {

    @Mock
    private ApiGatewayManagementApiClient sdk;

    private ApiGatewayConnectionClient client;

    @BeforeEach
    void setUp() {
        client = new ApiGatewayConnectionClient(sdk);
    }

    @Test
    void post_sendsPayloadToConnectionAndReturnsTrue() {
        // Act
        boolean delivered = client.post("conn-1", "{\"type\":\"x\"}");

        // Assert
        ArgumentCaptor<PostToConnectionRequest> captor = ArgumentCaptor.forClass(PostToConnectionRequest.class);
        verify(sdk).postToConnection(captor.capture());
        assertThat(delivered).isTrue();
        assertThat(captor.getValue().connectionId()).isEqualTo("conn-1");
        assertThat(captor.getValue().data().asUtf8String()).isEqualTo("{\"type\":\"x\"}");
    }

    @Test
    void post_goneConnection_returnsFalse() {
        when(sdk.postToConnection(any(PostToConnectionRequest.class)))
                .thenThrow(GoneException.builder().message("gone").build());

        assertThat(client.post("conn-1", "x")).isFalse();
    }

    @Test
    void post_otherFailure_propagates() {
        when(sdk.postToConnection(any(PostToConnectionRequest.class)))
                .thenThrow(SdkException.builder().message("throttled").build());

        assertThatThrownBy(() -> client.post("conn-1", "x")).isInstanceOf(SdkException.class);
    }

    @Test
    void delete_deletesConnection() {
        client.delete("conn-1");

        ArgumentCaptor<DeleteConnectionRequest> captor = ArgumentCaptor.forClass(DeleteConnectionRequest.class);
        verify(sdk).deleteConnection(captor.capture());
        assertThat(captor.getValue().connectionId()).isEqualTo("conn-1");
    }

    @Test
    void delete_alreadyGone_isNotAnError() {
        when(sdk.deleteConnection(any(DeleteConnectionRequest.class)))
                .thenThrow(GoneException.builder().message("gone").build());

        assertThatNoException().isThrownBy(() -> client.delete("conn-1"));
    }

    @Test
    void close_closesSdkClient() {
        client.close();

        verify(sdk).close();
    }

    @Test
    void create_buildsClientForEndpoint() {
        // A real SDK client is built but never called, so no network or credentials are needed.
        try (ApiGatewayConnectionClient created = ApiGatewayConnectionClient.create(
                "https://abc123.execute-api.us-east-1.amazonaws.com/dev", "us-east-1")) {
            assertThat(created).isNotNull();
        }
    }
}
