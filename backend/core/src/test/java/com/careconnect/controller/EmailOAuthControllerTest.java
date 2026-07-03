package com.careconnect.controller;

import com.careconnect.security.OAuthStateSigner;
import com.careconnect.service.GoogleOAuthService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.net.URI;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmailOAuthControllerTest {

    @Mock private GoogleOAuthService googleOAuthService;

    private OAuthStateSigner oauthStateSigner;

    private EmailOAuthController controller;

    private static final String USER_ID      = "user-123";
    private static final String CLIENT_ID    = "test-client-id";
    private static final String REDIRECT_URI = "http://localhost/callback";
    private static final String SCOPE        = "openid email";
    private static final String FRONTEND_URL = "http://localhost:3000";
    private static final String AUTH_CODE    = "auth-code-abc";

    @BeforeEach
    void setUp() {
        oauthStateSigner = new OAuthStateSigner("unit-test-secret-32-bytes-long!!!");
        controller = new EmailOAuthController(googleOAuthService, oauthStateSigner);
        controller.clientId       = CLIENT_ID;
        controller.redirectUri    = REDIRECT_URI;
        controller.scope          = SCOPE;
        controller.frontendBaseUrl = FRONTEND_URL;
    }

    @Nested
    class Start {

        @Test
        void returns302Found() {
            final ResponseEntity<Void> response = controller.start(USER_ID, null);
            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);
        }

        @Test
        void redirectsToGoogleAuthEndpoint() {
            final URI location = controller.start(USER_ID, null).getHeaders().getLocation();
            assertThat(location.toString()).contains("accounts.google.com/o/oauth2/v2/auth");
        }

        @Test
        void includesSignedStateParameter() {
            final URI location = controller.start(USER_ID, "http://frontend/page").getHeaders().getLocation();
            assertThat(location.toString()).contains("state=");
        }

        @Test
        void doesNotInteractWithGoogleOAuthService() {
            controller.start(USER_ID, null);
            verifyNoInteractions(googleOAuthService);
        }
    }

    @Nested
    class Callback {

        @Test
        void redirectsToReturnUrl_whenSuccessful() {
            final String returnUrl = "http://localhost:3000/settings";
            final String state = oauthStateSigner.sign(USER_ID, returnUrl);

            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location).isNotNull();
            assertThat(location.toString()).isEqualTo(returnUrl);
            verify(googleOAuthService).exchange(USER_ID, AUTH_CODE);
        }

        @Test
        void redirectsToFallbackUrl_whenNoReturnUrl() {
            final String state = oauthStateSigner.sign(USER_ID, null);
            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();
            assertThat(location.toString()).isEqualTo(FRONTEND_URL + "/usps-test");
        }

        @Test
        void redirectsWithOauthError_whenExchangeFails() {
            final String state = oauthStateSigner.sign(USER_ID, null);
            doThrow(new RuntimeException("token exchange failed"))
                    .when(googleOAuthService).exchange(USER_ID, AUTH_CODE);

            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).contains("oauthError=");
            assertThat(location.toString()).contains("token+exchange+failed");
        }

        @Test
        void supportsLegacyUnsignedState() {
            final String state = "u:" + USER_ID + "|r:http://localhost:3000/page";
            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();
            assertThat(location.toString()).isEqualTo("http://localhost:3000/page");
            verify(googleOAuthService).exchange(USER_ID, AUTH_CODE);
        }
    }
}
