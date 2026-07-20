package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialLifecycleService;
import com.careconnect.service.EmailCredentialService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmailCredentialControllerTest {

    @Mock
    private EmailCredentialLifecycleService credentialLifecycle;
    @Mock
    private EmailCredentialService emailCredentialService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;

    @InjectMocks
    private EmailCredentialController controller;

    private static final String USER_ID = "123";
    private User currentUser;

    @BeforeEach
    void setUp() {
        currentUser = new User();
        currentUser.setId(123L);
        lenient().when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
    }

    @Nested
    class GetConnectionStatus {

        @Test
        void returnsTrue_whenActivelyConnected() throws Exception {
            when(credentialLifecycle.isActivelyConnected(USER_ID)).thenReturn(true);

            final ResponseEntity<Boolean> response = controller.getConnectionStatus(USER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isTrue();
            verify(authorizationService).requireAdminOrCaregiver(currentUser);
            verify(authorizationService).requireSelfOrAdmin(currentUser, 123L);
        }

        @Test
        void returnsFalse_whenNotConnected() throws Exception {
            when(credentialLifecycle.isActivelyConnected(USER_ID)).thenReturn(false);

            final ResponseEntity<Boolean> response = controller.getConnectionStatus(USER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isFalse();
        }

        @Test
        void alwaysQueriesLifecycleForUserId() throws Exception {
            when(credentialLifecycle.isActivelyConnected(USER_ID)).thenReturn(false);

            controller.getConnectionStatus(USER_ID);

            verify(credentialLifecycle).isActivelyConnected(USER_ID);
        }

        @Test
        void passesUserIdToLifecycle() throws Exception {
            final String specificUserId = "456";
            when(credentialLifecycle.isActivelyConnected(specificUserId)).thenReturn(false);

            controller.getConnectionStatus(specificUserId);

            verify(credentialLifecycle).isActivelyConnected(specificUserId);
            verify(authorizationService).requireSelfOrAdmin(currentUser, 456L);
        }

        @Test
        void responseBodyIsNeverNull() throws Exception {
            when(credentialLifecycle.isActivelyConnected(USER_ID)).thenReturn(false);

            final ResponseEntity<Boolean> response = controller.getConnectionStatus(USER_ID);

            assertThat(response.getBody()).isNotNull();
        }

        @Test
        void rejectsNonNumericUserId() {
            assertThatThrownBy(() -> controller.getConnectionStatus("not-a-number"))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("Invalid userId");
            verify(credentialLifecycle, never()).isActivelyConnected(any());
        }
    }

    @Nested
    class GetConnectionDetails {

        @Test
        void returnsNeedsReconnectPayload() throws Exception {
            when(credentialLifecycle.connectionStatus(USER_ID)).thenReturn(
                    new EmailConnectionStatusResponse(
                            false,
                            true,
                            false,
                            "NEEDS_REAUTH",
                            "GMAIL",
                            null,
                            "invalid_grant",
                            "/oauth/google/start"));

            final ResponseEntity<EmailConnectionStatusResponse> response =
                    controller.getConnectionDetails(USER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody().needsReconnect()).isTrue();
            assertThat(response.getBody().reconnectPath()).isEqualTo("/oauth/google/start");
            verify(authorizationService).requireSelfOrAdmin(currentUser, 123L);
        }
    }

    @Nested
    class Disconnect {

        @Test
        void disconnectsAndReturnsReconnectPath() throws Exception {
            final EmailCredential cred = new EmailCredential();
            cred.setStatus(EmailCredential.Status.DISCONNECTED);
            cred.setSyncEnabled(false);
            when(credentialLifecycle.disconnect(USER_ID)).thenReturn(cred);

            final ResponseEntity<Map<String, Object>> response = controller.disconnect(USER_ID);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody().get("disconnected")).isEqualTo(true);
            assertThat(response.getBody().get("reconnectPath"))
                    .isEqualTo("/oauth/google/start");
            verify(authorizationService).requireSelfOrAdmin(currentUser, 123L);
        }
    }

    @Nested
    class GmailHmacApis {

        @Test
        void getGmailConnectionStatus_returnsStructuredStatus() throws Exception {
            EmailConnectionStatus status = EmailConnectionStatus.connected(
                    EmailCredential.Provider.GMAIL, Instant.parse("2026-07-02T00:00:00Z"));
            when(emailCredentialService.getGmailConnectionStatus("patient@example.com"))
                    .thenReturn(status);

            ResponseEntity<EmailConnectionStatus> response =
                    controller.getGmailConnectionStatus("patient@example.com", null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().connected()).isTrue();
            assertThat(response.getBody().status()).isEqualTo(EmailConnectionStatus.STATUS_CONNECTED);
        }

        @Test
        void getGmailConnectionStatus_acceptsLegacyUserIdParam() throws Exception {
            EmailConnectionStatus status =
                    EmailConnectionStatus.notConnected(EmailCredential.Provider.GMAIL);
            when(emailCredentialService.getGmailConnectionStatus("42")).thenReturn(status);

            ResponseEntity<EmailConnectionStatus> response =
                    controller.getGmailConnectionStatus(null, "42");

            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().connected()).isFalse();
        }

        @Test
        void disconnectGmail_returnsNoContent() throws Exception {
            ResponseEntity<Void> response = controller.disconnectGmail("patient@example.com", null);

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
            verify(emailCredentialService).disconnectGmail("patient@example.com");
        }

        @Test
        void getGmailConnectUrl_returnsSignedStartUrl() throws Exception {
            when(emailCredentialService.createGmailOAuthStartToken(
                    "patient@example.com", "http://localhost:3000/usps-test"))
                    .thenReturn("signed-start-token");

            var request = mock(jakarta.servlet.http.HttpServletRequest.class);
            when(request.getContextPath()).thenReturn("");

            ResponseEntity<com.careconnect.dto.GmailConnectUrlResponse> response =
                    controller.getGmailConnectUrl(
                            request,
                            "patient@example.com",
                            null,
                            "http://localhost:3000/usps-test");

            assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
            assertThat(response.getBody()).isNotNull();
            assertThat(response.getBody().url()).contains("/oauth/google/start");
            assertThat(response.getBody().url()).contains("startToken=signed-start-token");
        }
    }
}
