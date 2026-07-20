package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialLifecycleService;
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

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmailCredentialControllerTest {

    @Mock
    private EmailCredentialLifecycleService credentialLifecycle;
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
        when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
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
}
