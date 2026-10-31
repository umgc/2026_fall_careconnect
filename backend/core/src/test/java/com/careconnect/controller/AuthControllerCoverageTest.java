package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import jakarta.servlet.http.Cookie;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.net.SocketTimeoutException;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class AuthControllerCoverageTest {

    @Mock private JwtTokenProvider jwt;
    @Mock private UserRepository userRepository;
    @InjectMocks private AuthController controller;

    @Test
    void validateTokenEndpoint() {
        when(jwt.validateToken("good")).thenReturn(true);
        when(jwt.validateToken("bad")).thenReturn(false);
        when(jwt.validateToken("boom")).thenThrow(new RuntimeException("x"));
        assertThat(controller.validateToken(null).getStatusCode().value()).isEqualTo(401);
        assertThat(controller.validateToken("Basic abc").getStatusCode().value()).isEqualTo(401);
        assertThat(controller.validateToken("Bearer good").getStatusCode().value()).isEqualTo(200);
        assertThat(controller.validateToken("Bearer bad").getStatusCode().value()).isEqualTo(401);
        assertThat(controller.validateToken("Bearer boom").getStatusCode().value()).isEqualTo(401);
    }

    @Test
    void currentUserEndpoint() {
        MockHttpServletRequest none = new MockHttpServletRequest();
        assertThat(controller.getCurrentUser(none).getStatusCode().value()).isEqualTo(401);

        when(jwt.getEmailFromToken("t1")).thenReturn("a@example.test");
        when(userRepository.findByEmail("a@example.test")).thenReturn(Optional.of(
                User.builder().id(1L).name("A").email("a@example.test").role(Role.PATIENT).build()));
        MockHttpServletRequest bearer = new MockHttpServletRequest();
        bearer.addHeader("Authorization", "Bearer t1");
        assertThat(controller.getCurrentUser(bearer).getStatusCode().value()).isEqualTo(200);

        when(jwt.getEmailFromToken("t2")).thenReturn("missing@example.test");
        when(userRepository.findByEmail("missing@example.test")).thenReturn(Optional.empty());
        MockHttpServletRequest cookie = new MockHttpServletRequest();
        cookie.setCookies(new Cookie("OTHER", "x"), new Cookie("AUTH", "t2"));
        assertThat(controller.getCurrentUser(cookie).getStatusCode().value()).isEqualTo(404);

        when(jwt.getEmailFromToken("t3")).thenThrow(new RuntimeException("expired"));
        MockHttpServletRequest broken = new MockHttpServletRequest();
        broken.addHeader("Authorization", "Bearer t3");
        assertThat(controller.getCurrentUser(broken).getStatusCode().value()).isEqualTo(401);
    }

    private String classify(Exception e) {
        return ReflectionTestUtils.invokeMethod(controller, "determineOAuthErrorType", e);
    }

    static class OAuthProblem extends RuntimeException {
        OAuthProblem(String m) {
            super(m);
        }
    }

    static class AuthenticationProblem extends RuntimeException {
        AuthenticationProblem(String m) {
            super(m);
        }
    }

    static class JsonParseProblem extends RuntimeException {
        JsonParseProblem(String m) {
            super(m);
        }
    }

    static class RestClientProblem extends RuntimeException {
        RestClientProblem(String m) {
            super(m);
        }
    }

    @Test
    void oauthErrorClassification() {
        assertThat(classify(null)).isEqualTo("oauth_failed");
        assertThat(classify(new RuntimeException())).isEqualTo("oauth_failed");
        assertThat(classify(new RuntimeException("access_denied"))).isEqualTo("access_denied");
        assertThat(classify(new RuntimeException("invalid_grant"))).isEqualTo("invalid_grant");
        assertThat(classify(new RuntimeException("invalid_client"))).isEqualTo("invalid_client");
        assertThat(classify(new RuntimeException("bad request"))).isEqualTo("invalid_request");
        assertThat(classify(new RuntimeException("503"))).isEqualTo("temporarily_unavailable");
        assertThat(classify(new RuntimeException("insufficient_scope"))).isEqualTo("invalid_scope");
        assertThat(classify(new RuntimeException("token expired"))).isEqualTo("invalid_token");
        assertThat(classify(new RuntimeException("socket closed"))).isEqualTo("network_error");
        assertThat(classify(new RuntimeException("could not retrieve email"))).isEqualTo("invalid_response");
        assertThat(classify(new RestClientProblem("x"))).isEqualTo("api_error");
        assertThat(classify(new SocketTimeoutException("x"))).isEqualTo("network_error");
        assertThat(classify(new JsonParseProblem("x"))).isEqualTo("invalid_response");
        assertThat(classify(new AuthenticationProblem("x"))).isEqualTo("authentication_failed");
        assertThat(classify(new OAuthProblem("x"))).isEqualTo("oauth_failed");
        assertThat(classify(new IllegalStateException("x"))).isNotNull();
    }
}
