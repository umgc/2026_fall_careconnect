package com.careconnect.websocket.apigw;

import jakarta.servlet.FilterChain;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unit tests for {@link InternalPortFilter}.
 *
 * <p>Uses Spring's servlet mocks. The meaningful values are the ports: 8081 stands for the public
 * port the HTTP API reaches, 8082 for the internal port only the NLB reaches.
 */
class InternalPortFilterTest {

    private static final int PUBLIC_PORT = 8081;
    private static final int INTERNAL_PORT = 8082;

    private final InternalPortFilter filter = new InternalPortFilter(INTERNAL_PORT);

    private MockHttpServletResponse run(final int localPort, final String uri, final FilterChain chain)
            throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", uri);
        request.setLocalPort(localPort);
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, chain);
        return response;
    }

    /** The security-critical case: a forged callback through the public API must not get in. */
    @Test
    void callbackPathOnPublicPort_isNotFound() throws Exception {
        MockFilterChain chain = new MockFilterChain();

        MockHttpServletResponse response = run(PUBLIC_PORT, "/api/internal/ws/message", chain);

        assertThat(response.getStatus()).isEqualTo(404);
        assertThat(chain.getRequest()).isNull();
    }

    @Test
    void callbackPathOnInternalPort_passes() throws Exception {
        MockFilterChain chain = new MockFilterChain();

        run(INTERNAL_PORT, "/api/internal/ws/message", chain);

        assertThat(chain.getRequest()).isNotNull();
    }

    @Test
    void otherPathOnInternalPort_isNotFound() throws Exception {
        MockFilterChain chain = new MockFilterChain();

        MockHttpServletResponse response = run(INTERNAL_PORT, "/api/patients", chain);

        assertThat(response.getStatus()).isEqualTo(404);
        assertThat(chain.getRequest()).isNull();
    }

    @Test
    void otherPathOnPublicPort_passes() throws Exception {
        MockFilterChain chain = new MockFilterChain();

        run(PUBLIC_PORT, "/api/patients", chain);

        assertThat(chain.getRequest()).isNotNull();
    }
}
