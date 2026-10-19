package com.careconnect.websocket.apigw;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.security.Principal;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import org.springframework.http.HttpHeaders;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.TextMessage;
import org.springframework.web.socket.WebSocketExtension;
import org.springframework.web.socket.WebSocketMessage;
import org.springframework.web.socket.WebSocketSession;
import software.amazon.awssdk.core.exception.SdkException;

/**
 * A {@link WebSocketSession} backed by an API Gateway WebSocket connection.
 *
 * <p>API Gateway holds the client's socket; this object stands in for it so the existing Spring
 * handlers run unchanged. Sending a message posts to the connection, and closing deletes it.
 * Handshake details (URI, headers, addresses, principal) are not available and return empty values.
 */
public class ApiGatewayWebSocketSession implements WebSocketSession {

    /** API Gateway's maximum message size (fixed quota). */
    static final int MESSAGE_SIZE_LIMIT = 128 * 1024;

    private final String connectionId;
    private final WebSocketChannel channel;
    private final ApiGatewayConnectionClient client;
    private final Map<String, Object> attributes = new ConcurrentHashMap<>();
    private final AtomicBoolean established = new AtomicBoolean(false);
    private volatile boolean open = true;

    public ApiGatewayWebSocketSession(
            final String connectionId, final WebSocketChannel channel, final ApiGatewayConnectionClient client) {
        this.connectionId = connectionId;
        this.channel = channel;
        this.client = client;
    }

    public WebSocketChannel getChannel() {
        return channel;
    }

    /**
     * Marks the session established.
     *
     * @return {@code true} only the first time, so the handler's connect callback runs once
     */
    boolean markEstablished() {
        return established.compareAndSet(false, true);
    }

    /** Records that API Gateway reported the connection closed. */
    void markClosed() {
        open = false;
    }

    @Override
    public String getId() {
        return connectionId;
    }

    @Override
    public URI getUri() {
        return null;
    }

    @Override
    public HttpHeaders getHandshakeHeaders() {
        return new HttpHeaders();
    }

    @Override
    public Map<String, Object> getAttributes() {
        return attributes;
    }

    @Override
    public Principal getPrincipal() {
        return null;
    }

    @Override
    public InetSocketAddress getLocalAddress() {
        return null;
    }

    @Override
    public InetSocketAddress getRemoteAddress() {
        return null;
    }

    @Override
    public String getAcceptedProtocol() {
        return null;
    }

    @Override
    public void setTextMessageSizeLimit(final int messageSizeLimit) {
        // Fixed by API Gateway.
    }

    @Override
    public int getTextMessageSizeLimit() {
        return MESSAGE_SIZE_LIMIT;
    }

    @Override
    public void setBinaryMessageSizeLimit(final int messageSizeLimit) {
        // Fixed by API Gateway.
    }

    @Override
    public int getBinaryMessageSizeLimit() {
        return MESSAGE_SIZE_LIMIT;
    }

    @Override
    public List<WebSocketExtension> getExtensions() {
        return List.of();
    }

    @Override
    public void sendMessage(final WebSocketMessage<?> message) throws IOException {
        if (!(message instanceof TextMessage text)) {
            throw new UnsupportedOperationException("Only text messages are supported");
        }
        synchronized (this) {
            if (!open) {
                throw new IOException("WebSocket connection " + connectionId + " is closed");
            }
            final boolean delivered;
            try {
                delivered = client.post(connectionId, text.getPayload());
            } catch (SdkException e) {
                throw new IOException("Failed to post to connection " + connectionId, e);
            }
            if (!delivered) {
                open = false;
                throw new IOException("WebSocket connection " + connectionId + " is gone");
            }
        }
    }

    @Override
    public boolean isOpen() {
        return open;
    }

    @Override
    public void close() throws IOException {
        close(CloseStatus.NORMAL);
    }

    @Override
    public void close(final CloseStatus status) throws IOException {
        if (!open) {
            return;
        }
        open = false;
        try {
            client.delete(connectionId);
        } catch (SdkException e) {
            throw new IOException("Failed to close connection " + connectionId, e);
        }
    }
}
