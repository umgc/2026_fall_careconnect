package com.careconnect.service;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.Optional;

/**
 * Halts mail sync on OAuth revocation, notifies the user once, and exposes
 * reconnect status (Task 3.14.9 / #126).
 */
@Service
public class EmailCredentialLifecycleService {

    public static final String RECONNECT_PATH = "/oauth/google/start";
    public static final String NOTIFICATION_TYPE = "GMAIL_REAUTH";
    private static final Logger log = LoggerFactory.getLogger(EmailCredentialLifecycleService.class);
    private static final Duration REAUTH_NOTIFY_COOLDOWN = Duration.ofHours(24);
    private final EmailCredentialRepository credentialRepository;
    private final NotificationService notificationService;

    public EmailCredentialLifecycleService(
            final EmailCredentialRepository credentialRepository,
            final NotificationService notificationService) {
        this.credentialRepository = credentialRepository;
        this.notificationService = notificationService;
    }

    private static String truncate(final String reason) {
        if (reason == null) {
            return "Credential revoked or expired";
        }
        final String trimmed = reason.trim();
        if (trimmed.length() <= 512) {
            return trimmed;
        }
        return trimmed.substring(0, 512);
    }

    public boolean allowsSync(final EmailCredential credential) {
        return credential != null && credential.allowsSync();
    }

    @Transactional
    public EmailCredential markNeedsReauth(final EmailCredential credential, final String reason) {
        if (credential == null) {
            return null;
        }
        final boolean alreadyHalted = credential.getStatus() == EmailCredential.Status.NEEDS_REAUTH
                && !credential.isSyncEnabled();
        credential.setStatus(EmailCredential.Status.NEEDS_REAUTH);
        credential.setSyncEnabled(false);
        credential.setLastError(truncate(reason));
        credential.setLastErrorAt(Instant.now());
        final EmailCredential saved = credentialRepository.save(credential);
        if (!alreadyHalted) {
            notifyUserOnce(saved);
        } else {
            // still notify if cooldown elapsed
            notifyUserOnce(saved);
        }
        log.warn("Email credential sync halted for userId={} provider={} reason={}",
                saved.getUserId(), saved.getProvider(), reason);
        return saved;
    }

    @Transactional
    public EmailCredential activateAfterConnect(final EmailCredential credential) {
        if (credential == null) {
            return null;
        }
        credential.setStatus(EmailCredential.Status.ACTIVE);
        credential.setSyncEnabled(true);
        credential.setLastError(null);
        credential.setLastErrorAt(null);
        credential.setReauthNotifiedAt(null);
        return credentialRepository.save(credential);
    }

    @Transactional
    public EmailCredential disconnect(final String userId) {
        final Optional<EmailCredential> existing = credentialRepository
                .findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL);
        if (existing.isEmpty()) {
            return null;
        }
        final EmailCredential credential = existing.get();
        credential.setAccessTokenEnc(null);
        credential.setRefreshTokenEnc(null);
        credential.setExpiresAt(null);
        credential.setStatus(EmailCredential.Status.DISCONNECTED);
        credential.setSyncEnabled(false);
        credential.setLastError("Disconnected by user");
        credential.setLastErrorAt(Instant.now());
        return credentialRepository.save(credential);
    }

    @Transactional(readOnly = true)
    public EmailConnectionStatusResponse connectionStatus(final String userId) {
        final Optional<EmailCredential> existing = credentialRepository
                .findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL);
        if (existing.isEmpty()) {
            return EmailConnectionStatusResponse.disconnected();
        }
        final EmailCredential credential = existing.get();
        final boolean hasToken = credential.getAccessTokenEnc() != null
                && !credential.getAccessTokenEnc().isEmpty();
        final EmailCredential.Status status = credential.getStatus();
        final boolean needsReconnect = status == EmailCredential.Status.NEEDS_REAUTH
                || status == EmailCredential.Status.DISCONNECTED
                || !credential.isSyncEnabled()
                || !hasToken;
        final boolean connected = hasToken && status == EmailCredential.Status.ACTIVE
                && credential.isSyncEnabled();
        return new EmailConnectionStatusResponse(
                connected,
                needsReconnect,
                credential.isSyncEnabled(),
                status.name(),
                credential.getProvider() == null ? "GMAIL" : credential.getProvider().name(),
                credential.getExpiresAt(),
                credential.getLastError(),
                RECONNECT_PATH);
    }

    /**
     * Backward-compatible "is connected" used by legacy boolean status endpoint:
     * true only when sync is allowed (ACTIVE + token present).
     */
    @Transactional(readOnly = true)
    public boolean isActivelyConnected(final String userId) {
        return connectionStatus(userId).connected();
    }

    void notifyUserOnce(final EmailCredential credential) {
        if (credential == null || credential.getUserId() == null) {
            return;
        }
        final Instant last = credential.getReauthNotifiedAt();
        if (last != null && last.isAfter(Instant.now().minus(REAUTH_NOTIFY_COOLDOWN))) {
            return;
        }
        try {
            final Long numericUserId = Long.parseLong(credential.getUserId().trim());
            notificationService.sendNotificationToUser(
                    numericUserId,
                    "Gmail reconnection required",
                    "USPS mail sync stopped because Google access was revoked or expired. "
                            + "Reconnect Gmail to resume Informed Delivery.",
                    NOTIFICATION_TYPE,
                    Map.of(
                            "action", "reconnect",
                            "reconnectPath", RECONNECT_PATH,
                            "provider", "GMAIL"));
            credential.setReauthNotifiedAt(Instant.now());
            credentialRepository.save(credential);
        } catch (final NumberFormatException ex) {
            log.debug("Skipping GMAIL_REAUTH notification; userId={} is not numeric",
                    credential.getUserId());
        } catch (final Exception ex) {
            log.warn("Failed to notify user {} about Gmail reauth: {}",
                    credential.getUserId(), ex.getMessage());
        }
    }
}
