package com.careconnect.websocket.apigw;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Keeps the API Gateway callback endpoints and the public API on separate ports.
 *
 * <p>The public HTTP API forwards every path to the main port, so the callback endpoints (which
 * trust the {@code X-Ws-Connection-Id} header) must answer only on the internal port that just the
 * internal NLB can reach. Conversely, nothing else is served on the internal port.
 */
public class InternalPortFilter extends OncePerRequestFilter {

    /** Path prefix of the API Gateway callback endpoints. */
    public static final String INTERNAL_PATH_PREFIX = "/api/internal/ws/";

    private final int internalPort;

    public InternalPortFilter(final int internalPort) {
        this.internalPort = internalPort;
    }

    @Override
    protected void doFilterInternal(
            final HttpServletRequest request, final HttpServletResponse response, final FilterChain chain)
            throws ServletException, IOException {
        final boolean internalPath = request.getRequestURI().startsWith(INTERNAL_PATH_PREFIX);
        final boolean onInternalPort = request.getLocalPort() == internalPort;
        if (internalPath != onInternalPort) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND);
            return;
        }
        chain.doFilter(request, response);
    }
}
