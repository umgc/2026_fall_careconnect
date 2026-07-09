package com.careconnect.controller;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.model.EmailCredential;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.EmailCredentialService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmailCredentialControllerTest {

    @Mock
    private EmailCredentialService emailCredentialService;

    @Mock
    private Jwt jwt;

    @InjectMocks
    private EmailCredentialController controller;

    @Test
    void getConnectionStatus_returnsStructuredStatus() throws Exception {
        EmailConnectionStatus status = EmailConnectionStatus.connected(
                EmailCredential.Provider.GMAIL, Instant.parse("2026-07-02T00:00:00Z"));
        when(emailCredentialService.getGmailConnectionStatus("patient@example.com")).thenReturn(status);

        ResponseEntity<EmailConnectionStatus> response =
                controller.getConnectionStatus(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().connected()).isTrue();
        assertThat(response.getBody().status()).isEqualTo(EmailConnectionStatus.STATUS_CONNECTED);
    }

    @Test
    void getConnectionStatus_acceptsLegacyUserIdParam() throws Exception {
        EmailConnectionStatus status = EmailConnectionStatus.notConnected(EmailCredential.Provider.GMAIL);
        when(emailCredentialService.getGmailConnectionStatus("42")).thenReturn(status);

        ResponseEntity<EmailConnectionStatus> response = controller.getConnectionStatus(jwt, null, "42");

        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().connected()).isFalse();
    }

    @Test
    void getConnectionStatus_missingJwt_throwsUnauthorized() {
        assertThatThrownBy(() -> controller.getConnectionStatus(null, "patient@example.com", null))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("Missing or invalid authentication token");
    }

    @Test
    void disconnectGmail_returnsNoContent() throws Exception {
        ResponseEntity<Void> response = controller.disconnectGmail(jwt, "patient@example.com", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(emailCredentialService).disconnectGmail("patient@example.com");
    }

    @Test
    void getGmailConnectUrl_returnsSignedStartUrl() throws Exception {
        when(emailCredentialService.createGmailOAuthStartToken("patient@example.com", "http://localhost:3000/usps-test"))
                .thenReturn("signed-start-token");

        var request = mock(jakarta.servlet.http.HttpServletRequest.class);
        when(request.getContextPath()).thenReturn("");

        ResponseEntity<com.careconnect.dto.GmailConnectUrlResponse> response = controller.getGmailConnectUrl(
                jwt,
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
