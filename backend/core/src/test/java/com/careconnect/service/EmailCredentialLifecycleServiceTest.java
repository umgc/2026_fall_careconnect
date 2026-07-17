package com.careconnect.service;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepo;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.repository.USPSDigestCacheRepo;
import com.careconnect.security.TokenCryptor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class EmailCredentialLifecycleServiceTest {

    @Mock private EmailCredentialRepository credentialRepository;
    @Mock private NotificationService notificationService;
    @Mock private EmailCredentialRepo uspsCredRepo;
    @Mock private USPSDigestCacheRepo cacheRepo;
    @Mock private GmailClient gmailClient;
    @Mock private OutlookClient outlookClient;
    @Mock private GmailParser gmailParser;
    @Mock private OutlookParser outlookParser;
    @Mock private GoogleOAuthService googleOAuthService;

    private EmailCredentialLifecycleService lifecycle;
    private TokenCryptor cryptor;

    @BeforeEach
    void setUp() {
        lifecycle = new EmailCredentialLifecycleService(credentialRepository, notificationService);
        cryptor = new TokenCryptor("unit-test-secret-32-bytes-long!!!");
    }

    @Test
    void markNeedsReauth_haltsSyncAndNotifiesNumericUser() {
        final EmailCredential credential = new EmailCredential();
        credential.setUserId("42");
        credential.setProvider(EmailCredential.Provider.GMAIL);
        credential.setAccessTokenEnc("enc");
        when(credentialRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(notificationService.sendNotificationToUser(
                anyLong(), anyString(), anyString(), anyString(), anyMap()))
                .thenReturn(List.of());

        lifecycle.markNeedsReauth(credential, "invalid_grant");

        assertThat(credential.getStatus()).isEqualTo(EmailCredential.Status.NEEDS_REAUTH);
        assertThat(credential.isSyncEnabled()).isFalse();
        assertThat(credential.getLastError()).contains("invalid_grant");
        assertThat(credential.getReauthNotifiedAt()).isNotNull();
        verify(notificationService).sendNotificationToUser(
                eq(42L),
                eq("Gmail reconnection required"),
                anyString(),
                eq(EmailCredentialLifecycleService.NOTIFICATION_TYPE),
                anyMap());
    }

    @Test
    void connectionStatus_needsReconnectWhenHalted() {
        final EmailCredential credential = new EmailCredential();
        credential.setUserId("42");
        credential.setProvider(EmailCredential.Provider.GMAIL);
        credential.setAccessTokenEnc("enc");
        credential.setStatus(EmailCredential.Status.NEEDS_REAUTH);
        credential.setSyncEnabled(false);
        credential.setLastError("revoked");
        when(credentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                "42", EmailCredential.Provider.GMAIL))
                .thenReturn(Optional.of(credential));

        final EmailConnectionStatusResponse status = lifecycle.connectionStatus("42");

        assertThat(status.connected()).isFalse();
        assertThat(status.needsReconnect()).isTrue();
        assertThat(status.reconnectPath()).isEqualTo("/oauth/google/start");
        assertThat(status.status()).isEqualTo("NEEDS_REAUTH");
    }

    @Test
    void uspsDigestService_haltsWhenCredentialNeedsReauth() {
        final EmailCredential credential = new EmailCredential();
        credential.setUserId("42");
        credential.setProvider(EmailCredential.Provider.GMAIL);
        credential.setAccessTokenEnc(cryptor.encrypt("token"));
        credential.setStatus(EmailCredential.Status.NEEDS_REAUTH);
        credential.setSyncEnabled(false);
        when(uspsCredRepo.findFirstByUserIdAndProviderOrderByIdDesc(
                "42", EmailCredential.Provider.GMAIL))
                .thenReturn(Optional.of(credential));
        when(cacheRepo.findFirstByUserIdAndExpiresAtAfterOrderByDigestDateDesc(any(), any()))
                .thenReturn(Optional.empty());

        final USPSDigestService digestService = new USPSDigestService(
                uspsCredRepo,
                cacheRepo,
                gmailClient,
                outlookClient,
                gmailParser,
                outlookParser,
                cryptor,
                googleOAuthService,
                lifecycle);

        assertThatThrownBy(() -> digestService.latestForUser("42"))
                .isInstanceOf(EmailCredentialNeedsReauthException.class);
        verify(gmailClient, never()).fetchLatestDigest(any());
        verify(googleOAuthService, never()).ensureFreshToken(any());
    }

    @Test
    void disconnect_clearsTokensAndHaltsSync() {
        final EmailCredential credential = new EmailCredential();
        credential.setUserId("42");
        credential.setAccessTokenEnc("enc");
        credential.setRefreshTokenEnc("ref");
        credential.setExpiresAt(Instant.now().plusSeconds(60));
        when(credentialRepository.findFirstByUserIdAndProviderOrderByIdDesc(
                "42", EmailCredential.Provider.GMAIL))
                .thenReturn(Optional.of(credential));
        when(credentialRepository.save(any())).thenAnswer(inv -> inv.getArgument(0));

        final EmailCredential result = lifecycle.disconnect("42");

        assertThat(result.getStatus()).isEqualTo(EmailCredential.Status.DISCONNECTED);
        assertThat(result.isSyncEnabled()).isFalse();
        assertThat(result.getAccessTokenEnc()).isNull();
        assertThat(result.getRefreshTokenEnc()).isNull();
    }
}
