package com.careconnect.controller;



import com.careconnect.security.OAuthRedirectValidator;

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

import static org.assertj.core.api.Assertions.assertThatThrownBy;

import static org.mockito.Mockito.*;



@ExtendWith(MockitoExtension.class)

class EmailOAuthControllerTest {



    @Mock private GoogleOAuthService googleOAuthService;



    private OAuthStateSigner oauthStateSigner;

    private OAuthRedirectValidator oauthRedirectValidator;



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

        oauthRedirectValidator = new OAuthRedirectValidator(FRONTEND_URL, FRONTEND_URL, "");

        controller = new EmailOAuthController(googleOAuthService, oauthStateSigner, oauthRedirectValidator);

        controller.clientId       = CLIENT_ID;

        controller.redirectUri    = REDIRECT_URI;

        controller.scope          = SCOPE;

        controller.frontendBaseUrl = FRONTEND_URL;

    }



    @Nested

    class Start {



        @Test

        void returns302Found() {

            final String startToken = oauthStateSigner.signStartToken(USER_ID, null);

            final ResponseEntity<Void> response = controller.start(startToken);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);

        }



        @Test

        void redirectsToGoogleAuthEndpoint() {

            final String startToken = oauthStateSigner.signStartToken(USER_ID, null);

            final URI location = controller.start(startToken).getHeaders().getLocation();

            assertThat(location.toString()).contains("accounts.google.com/o/oauth2/v2/auth");

        }



        @Test

        void includesSignedStateParameter() {

            final String startToken = oauthStateSigner.signStartToken(USER_ID, FRONTEND_URL + "/page");

            final URI location = controller.start(startToken).getHeaders().getLocation();

            assertThat(location.toString()).contains("state=");

        }



        @Test

        void rejectsUnsignedStartToken() {

            assertThatThrownBy(() -> controller.start("not-a-valid-token"))

                    .isInstanceOf(IllegalArgumentException.class);
            ResponseEntity<Void> response = controller.start("not-a-valid-token");

            assertThat(response.getStatusCode().value()).isEqualTo(400);

        }



        @Test

        void doesNotInteractWithGoogleOAuthService() {

            controller.start(oauthStateSigner.signStartToken(USER_ID, null));

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



            assertThat(location.toString()).contains("oauthError=oauth_failed");

            assertThat(location.toString()).contains("/usps-test");

        }



        @Test

        void redirectsWithOauthErrorOnReturnUrl_whenExchangeFails() {

            final String returnUrl = "http://localhost:3000/usps-test";

            final String state = oauthStateSigner.sign(USER_ID, returnUrl);

            doThrow(new RuntimeException("token exchange failed"))

                    .when(googleOAuthService).exchange(USER_ID, AUTH_CODE);



            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();



            assertThat(location.toString()).startsWith(returnUrl);

            assertThat(location.toString()).contains("oauthError=oauth_failed");

        }



        @Test

        void rejectsLegacyUnsignedState() {

            final String state = "u:" + USER_ID + "|r:http://localhost:3000/page";

            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).contains("oauthError=oauth_failed");

            verifyNoInteractions(googleOAuthService);

        }



        @Test

        void rejectsStartTokenUsedAsCallbackState() {

            final String state = oauthStateSigner.signStartToken(USER_ID, FRONTEND_URL + "/usps-test");

            final URI location = controller.callback(AUTH_CODE, state).getHeaders().getLocation();

            assertThat(location.toString()).contains("oauthError=oauth_failed");

            verifyNoInteractions(googleOAuthService);

        }

    }

}


