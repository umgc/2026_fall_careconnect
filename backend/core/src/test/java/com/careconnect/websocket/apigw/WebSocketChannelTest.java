package com.careconnect.websocket.apigw;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for {@link WebSocketChannel} and {@link ApiGatewaySessionRegistry}: the small lookup
 * pieces the controller relies on.
 */
class WebSocketChannelTest {

    @Test
    void fromQueryValue_resolvesEveryChannel() {
        assertThat(WebSocketChannel.fromQueryValue("calls")).contains(WebSocketChannel.CALLS);
        assertThat(WebSocketChannel.fromQueryValue("careconnect")).contains(WebSocketChannel.CARECONNECT);
        assertThat(WebSocketChannel.fromQueryValue("notifications")).contains(WebSocketChannel.NOTIFICATIONS);
        assertThat(WebSocketChannel.fromQueryValue("chat")).contains(WebSocketChannel.CHAT);
    }

    @Test
    void fromQueryValue_isExactAndRejectsUnknownOrMissing() {
        assertThat(WebSocketChannel.fromQueryValue("CHAT")).isEmpty();
        assertThat(WebSocketChannel.fromQueryValue("admin")).isEmpty();
        assertThat(WebSocketChannel.fromQueryValue(null)).isEmpty();
    }

    @Test
    void registry_registerGetRemove() {
        ApiGatewaySessionRegistry registry = new ApiGatewaySessionRegistry();
        ApiGatewayWebSocketSession session =
                new ApiGatewayWebSocketSession("c1", WebSocketChannel.CHAT, null);

        registry.register(session);

        assertThat(registry.get("c1")).isSameAs(session);
        assertThat(registry.size()).isEqualTo(1);
        assertThat(registry.remove("c1")).isSameAs(session);
        assertThat(registry.get("c1")).isNull();
        assertThat(registry.remove("c1")).isNull();
    }
}
