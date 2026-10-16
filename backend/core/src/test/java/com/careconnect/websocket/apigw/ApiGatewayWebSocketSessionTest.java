package com.careconnect.websocket.apigw;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.socket.BinaryMessage;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import software.amazon.awssdk.core.exception.SdkException;

import java.io.IOException;
import java.nio.ByteBuffer;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link ApiGatewayWebSocketSession}.
 *
 * <p>The connection client is mocked: the session's job is to translate Spring's
 * {@code WebSocketSession} calls into {@code @connections} calls and to track open/closed state the
 * way handlers expect from a real socket.
 */
@ExtendWith(MockitoExtension.class)
class ApiGatewayWebSocketSessionTest {

    @Mock
    private ApiGatewayConnectionClient client;

    private ApiGatewayWebSocketSession session;

    @BeforeEach
    void setUp() {
        session = new ApiGatewayWebSocketSession("conn-1", WebSocketChannel.CALLS, client);
    }

    @Test
    void identityAndDefaults() {
        assertThat(session.getId()).isEqualTo("conn-1");
        assertThat(session.getChannel()).isEqualTo(WebSocketChannel.CALLS);
        assertThat(session.isOpen()).isTrue();
        assertThat(session.getUri()).isNull();
        assertThat(session.getPrincipal()).isNull();
        assertThat(session.getLocalAddress()).isNull();
        assertThat(session.getRemoteAddress()).isNull();
        assertThat(session.getAcceptedProtocol()).isNull();
        assertThat(session.getHandshakeHeaders()).isEmpty();
        assertThat(session.getExtensions()).isEmpty();
        assertThat(session.getTextMessageSizeLimit()).isEqualTo(128 * 1024);
        assertThat(session.getBinaryMessageSizeLimit()).isEqualTo(128 * 1024);
        session.getAttributes().put("k", "v");
        assertThat(session.getAttributes()).containsEntry("k", "v");
    }

    @Test
    void sizeLimitSetters_areIgnoredBecauseApiGatewayFixesThem() {
        session.setTextMessageSizeLimit(1);
        session.setBinaryMessageSizeLimit(1);

        assertThat(session.getTextMessageSizeLimit()).isEqualTo(128 * 1024);
        assertThat(session.getBinaryMessageSizeLimit()).isEqualTo(128 * 1024);
    }

    @Test
    void markEstablished_isTrueOnlyOnce() {
        assertThat(session.markEstablished()).isTrue();
        assertThat(session.markEstablished()).isFalse();
    }

    @Test
    void sendMessage_postsTextPayload() throws Exception {
        when(client.post("conn-1", "hello")).thenReturn(true);

        session.sendMessage(new TextMessage("hello"));

        verify(client).post("conn-1", "hello");
        assertThat(session.isOpen()).isTrue();
    }

    /**
     * A gone connection must look like a closed socket: handlers check {@code isOpen()} before
     * sending, and a failed send surfaces as an IOException as it would from Tomcat.
     */
    @Test
    void sendMessage_goneConnection_marksClosedAndThrows() {
        when(client.post("conn-1", "hello")).thenReturn(false);

        assertThatThrownBy(() -> session.sendMessage(new TextMessage("hello"))).isInstanceOf(IOException.class);
        assertThat(session.isOpen()).isFalse();
    }

    @Test
    void sendMessage_sdkFailure_wrapsAsIoExceptionAndStaysOpen() {
        when(client.post("conn-1", "hello")).thenThrow(SdkException.builder().message("throttled").build());

        assertThatThrownBy(() -> session.sendMessage(new TextMessage("hello")))
                .isInstanceOf(IOException.class)
                .hasCauseInstanceOf(SdkException.class);
        assertThat(session.isOpen()).isTrue();
    }

    @Test
    void sendMessage_afterClose_throwsWithoutPosting() throws Exception {
        session.markClosed();

        assertThatThrownBy(() -> session.sendMessage(new TextMessage("hello"))).isInstanceOf(IOException.class);
        verify(client, never()).post(anyString(), anyString());
    }

    @Test
    void sendMessage_binary_isUnsupported() {
        assertThatThrownBy(() -> session.sendMessage(new BinaryMessage(ByteBuffer.allocate(1))))
                .isInstanceOf(UnsupportedOperationException.class);
    }

    @Test
    void close_deletesConnectionOnce() throws Exception {
        session.close();
        session.close(CloseStatus.NOT_ACCEPTABLE);

        verify(client, times(1)).delete("conn-1");
        assertThat(session.isOpen()).isFalse();
    }

    @Test
    void close_sdkFailure_wrapsAsIoException() {
        doThrow(SdkException.builder().message("boom").build()).when(client).delete("conn-1");

        assertThatThrownBy(() -> session.close(CloseStatus.NOT_ACCEPTABLE)).isInstanceOf(IOException.class);
        assertThat(session.isOpen()).isFalse();
    }
}
