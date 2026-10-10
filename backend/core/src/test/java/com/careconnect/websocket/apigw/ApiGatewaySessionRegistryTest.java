package com.careconnect.websocket.apigw;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class ApiGatewaySessionRegistryTest {

    @Test
    void registerGetAndRemoveTrackConnectionsById() {
        ApiGatewaySessionRegistry registry = new ApiGatewaySessionRegistry();
        ApiGatewayWebSocketSession session = session("connection-1");

        registry.register(session);

        assertThat(registry.size()).isOne();
        assertThat(registry.get("connection-1")).isSameAs(session);
        assertThat(registry.remove("connection-1")).isSameAs(session);
        assertThat(registry.size()).isZero();
        assertThat(registry.get("connection-1")).isNull();
    }

    @Test
    void registerReplacesTheSessionForAnExistingConnectionId() {
        ApiGatewaySessionRegistry registry = new ApiGatewaySessionRegistry();
        ApiGatewayWebSocketSession original = session("connection-1");
        ApiGatewayWebSocketSession replacement = session("connection-1");

        registry.register(original);
        registry.register(replacement);

        assertThat(registry.size()).isOne();
        assertThat(registry.get("connection-1")).isSameAs(replacement);
        assertThat(registry.remove("missing")).isNull();
    }

    private ApiGatewayWebSocketSession session(final String id) {
        ApiGatewayWebSocketSession session = mock(ApiGatewayWebSocketSession.class);
        when(session.getId()).thenReturn(id);
        return session;
    }
}
