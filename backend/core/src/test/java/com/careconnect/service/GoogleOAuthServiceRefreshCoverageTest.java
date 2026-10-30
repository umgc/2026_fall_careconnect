package com.careconnect.service;

import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.security.TokenCryptor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class GoogleOAuthServiceRefreshCoverageTest {

    private RestTemplate http;
    private EmailCredentialRepository repo;
    private TokenCryptor crypto;
    private EmailCredentialLifecycleService lifecycle;
    private GoogleOAuthService service;

    @BeforeEach
    void setUp() {
        http = mock(RestTemplate.class);
        repo = mock(EmailCredentialRepository.class);
        crypto = mock(TokenCryptor.class);
        lifecycle = mock(EmailCredentialLifecycleService.class);
        service = new GoogleOAuthService(http, repo, crypto, lifecycle);
        service.clientId = "cid";
        service.clientSecret = "secret";
        service.redirectUri = "http://localhost/cb";
        when(lifecycle.allowsSync(any())).thenReturn(true);
    }

    private static EmailCredential expired(String refreshEnc) {
        EmailCredential c = new EmailCredential();
        c.setUserId("u1");
        c.setRefreshTokenEnc(refreshEnc);
        c.setExpiresAt(Instant.now().minusSeconds(60));
        return c;
    }

    @Test
    void refreshGuardsAndFailureModes() {
        assertThat(service.ensureFreshToken(null)).isNull();

        when(lifecycle.allowsSync(any())).thenReturn(false);
        EmailCredential blocked = expired("r");
        blocked.setLastError("revoked");
        assertThatThrownBy(() -> service.ensureFreshToken(blocked))
                .isInstanceOf(EmailCredentialNeedsReauthException.class);
        when(lifecycle.allowsSync(any())).thenReturn(true);

        when(crypto.decrypt("unreadable")).thenReturn(null);
        assertThatThrownBy(() -> service.ensureFreshToken(expired("unreadable")))
                .isInstanceOf(EmailCredentialNeedsReauthException.class);

        when(crypto.decrypt("r")).thenReturn("refresh");
        when(http.postForEntity(anyString(), any(HttpEntity.class), any(Class.class)))
                .thenThrow(new RuntimeException("invalid_grant: revoked"));
        assertThatThrownBy(() -> service.ensureFreshToken(expired("r")))
                .isInstanceOf(EmailCredentialNeedsReauthException.class);

        when(http.postForEntity(anyString(), any(HttpEntity.class), any(Class.class)))
                .thenThrow(new IllegalStateException("network down"));
        assertThatThrownBy(() -> service.ensureFreshToken(expired("r")))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test
    @SuppressWarnings("unchecked")
    void nonSuccessResponseRequiresReauth() {
        when(crypto.decrypt("r")).thenReturn("refresh");
        when(http.postForEntity(anyString(), any(HttpEntity.class), any(Class.class)))
                .thenReturn(ResponseEntity.status(HttpStatus.NO_CONTENT).build());
        assertThatThrownBy(() -> service.ensureFreshToken(expired("r")))
                .isInstanceOf(EmailCredentialNeedsReauthException.class);
    }

    @Test
    void lookupDisconnectAndRevoke() {
        EmailCredential cred = expired("r");
        when(repo.findFirstByUserIdAndProviderOrderByIdDesc("u1", EmailCredential.Provider.GMAIL))
                .thenReturn(Optional.of(cred));
        assertThat(service.findLatestCredential("u1", EmailCredential.Provider.GMAIL)).contains(cred);
        service.disconnect("u1", EmailCredential.Provider.GMAIL);
        verify(repo).delete(cred);

        service.revokeIfPossible(null);
        when(crypto.decrypt("r")).thenReturn("refresh");
        service.revokeIfPossible(cred);
        verify(http).postForEntity(eq("https://oauth2.googleapis.com/revoke"), any(HttpEntity.class), eq(String.class));
        when(crypto.decrypt("boom")).thenThrow(new RuntimeException("x"));
        service.revokeIfPossible(expired("boom"));
    }
}
