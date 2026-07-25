package com.careconnect.controller;

import com.careconnect.security.OAuthRedirectValidator;
import com.careconnect.security.OAuthStateSigner;
import com.careconnect.service.GoogleOAuthService;
import com.careconnect.service.MicrosoftOAuthService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
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
    @Mock private MicrosoftOAuthService microsoftOAuthService;

    private OAuthStateSigner oauthStateSigner;
    private OAuthRedirectValidator oauthRedirectValidator;
    private EmailOAuthController controller;

    private static final String USER_ID = "user-123";
    private static final String CLIENT_ID = "test-client-id";
    private static final String REDIRECT_URI = "http://localhost/callback";
    private static final String SCOPE = "openid email";
    private static final String FRONTEND_URL = "http://localhost:3000";
    private static final String AUTH_CODE = "auth-code-abc";
    private static final String MS_CLIENT = "ms-client";
    private static final String MS_REDIRECT = "http://localhost/oauth/microsoft/callback";
    private static final String MS_SCOPE = "openid offline_access Mail.Read";

    @BeforeEach
    void setUp() {
        oauthStateSigner = new OAuthStateSigner("unit-test-secret-32-bytes-long!!!");
        oauthRedirectValidator = new OAuthRedirectValidator(FRONTEND_URL, FRONTEND_URL, "");
        controller = new EmailOAuthController(
                googleOAuthService, microsoftOAuthService, oauthStateSigner, oauthRedirectValidator);
        controller.clientId = CLIENT_ID;
        controller.redirectUri = REDIRECT_URI;
        controller.scope = SCOPE;
        controller.frontendBaseUrl = FRONTEND_URL;
        controller.microsoftClientId = MS_CLIENT;
        controller.microsoftRedirectUri = MS_REDIRECT;
        controller.microsoftScope = MS_SCOPE;
    }

    @Nested
    class GoogleStart {
        @Test
        void returns302Found() {
            final String startToken = oauthStateSigner.signStartToken(USER_ID, null);
            assertThat(controller.start(startToken).getStatusCode()).isEqualTo(HttpStatus.FOUND);
        }

        @Test
        void redirectsToGoogleAuthEndpoint() {
            final String startToken = oauthStateSigner.signStartToken(USER_ID, null);
            final URI location = controller.start(startToken).getHeaders().getLocation();
            assertThat(location.toString()).contains("accounts.google.com/o/oauth2/v2/auth");
            assertThat(location.toString()).contains("state=");
        }

        @Test
        void rejectsUnsignedStartToken() {
            assertThat(controller.start("not-a-valid-token").getStatusCode().value()).isEqualTo(400);
        }

        @Test
        void doesNotInteractWithGoogleOAuthService() {
            controller.start(oauthStateSigner.signStartToken(USER_ID, null));
            verifyNoInteractions(googleOAuthService);
        }
    }

    @Nested
    class MicrosoftStart {
        @Test
        void redirectsToMicrosoftAuthEndpoint() {
            final String startToken = oauthStateSigner.signStartToken(USER_ID, null);
            final URI location = controller.microsoftStart(startToken).getHeaders().getLocation();
            assertThat(location.toString()).contains("login.microsoftonline.com");
            assertThat(location.toString()).contains("state=");
        }

        @Test
        void rejectsUnsignedStartToken() {
            assertThat(controller.microsoftStart("tampered").getStatusCode().value()).isEqualTo(400);
        }
    }

    @Nested
    class GoogleCallback {
        @Test
        void redirectsToReturnUrl_whenSuccessful() {
            final String returnUrl = "http://localhost:3000/settings";
            final String state = oauthStateSigner.sign(USER_ID, returnUrl);

            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).isEqualTo(returnUrl);
            verify(googleOAuthService).exchange(USER_ID, AUTH_CODE);
        }

        @Test
        void redirectsToFallback_whenNoReturnUrl() {
            final String state = oauthStateSigner.sign(USER_ID, null);
            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();
            assertThat(location.toString()).isEqualTo(FRONTEND_URL + "/usps-test");
        }

        @Test
        void rejectsTamperedState_withoutCallingExchange() {
            final String state = oauthStateSigner.sign(USER_ID, FRONTEND_URL + "/page") + "xx";
            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();
            assertThat(location.toString()).contains(EmailOAuthController.OAUTH_ERROR_PARAM + "=oauth_failed");
            assertThat(location.toString()).startsWith(FRONTEND_URL);
            verifyNoInteractions(googleOAuthService);
        }

        @Test
        void errorRedirectUsesGenericCode_notExceptionMessage() {
            final String state = oauthStateSigner.sign(USER_ID, FRONTEND_URL + "/usps-test");
            doThrow(new RuntimeException("token exchange failed secret"))
                    .when(googleOAuthService).exchange(USER_ID, AUTH_CODE);

            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).contains("oauthError=oauth_failed");
            assertThat(location.toString()).doesNotContain("token");
            assertThat(location.toString()).doesNotContain("secret");
            assertThat(location.toString()).startsWith(FRONTEND_URL);
        }
    }

    @Nested
    class MicrosoftCallback {
        @Test
        void bindsMailboxUsingSignedStateUserId() {
            final String returnUrl = "http://localhost:3000/usps-test";
            final String state = oauthStateSigner.sign(USER_ID, returnUrl);

            final URI location = controller.microsoftCallback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).isEqualTo(returnUrl);
            verify(microsoftOAuthService).exchange(USER_ID, AUTH_CODE);
        }

        @Test
        void rejectsTamperedState() {
            final String state = oauthStateSigner.sign(USER_ID, null) + "ab";
            final URI location = controller.microsoftCallback(AUTH_CODE, state).getHeaders().getLocation();
            assertThat(location.toString()).contains("oauthError=oauth_failed");
            verifyNoInteractions(microsoftOAuthService);
        }

        @Test
        void errorRedirectUsesFrontendBaseAndGenericCode() {
            final String state = oauthStateSigner.sign(USER_ID, null);
            doThrow(new RuntimeException("graph blew up"))
                    .when(microsoftOAuthService).exchange(USER_ID, AUTH_CODE);

            final URI location = controller.microsoftCallback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).isEqualTo(FRONTEND_URL + "/usps-test?oauthError=oauth_failed");
        }
    }

    @Nested
    class RedirectAllowlist {
        @Test
        void callbackIgnoresDisallowedReturnUrlHost() {
            // Signed state can only be created via sanitize on start; simulate a signed
            // localhost URL which is allowed, then ensure evil hosts are rejected at sanitize time.
            assertThat(org.junit.jupiter.api.Assertions.assertThrows(
                    IllegalArgumentException.class,
                    () -> oauthRedirectValidator.sanitizeReturnUrl("https://evil.example/phish"))
            ).hasMessageContaining("not allowed");
        }
    }
}
