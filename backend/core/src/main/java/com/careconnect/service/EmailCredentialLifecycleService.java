package com.careconnect.service;

import com.careconnect.dto.EmailConnectionStatusResponse;
import com.careconnect.email.EmailDomainDetector;
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
 * Halts mail sync on OAuth/IMAP revocation, notifies the user once, and exposes
 * reconnect status for every provider (Task 3.14.9 / #126).
 */
@Service
public class EmailCredentialLifecycleService {

    private static final Logger log = LoggerFactory.getLogger(EmailCredentialLifecycleService.class);
    private static final Duration REAUTH_NOTIFY_COOLDOWN = Duration.ofHours(24);
    public static final String RECONNECT_PATH = "/oauth/google/start";
    public static final String NOTIFICATION_TYPE = "EMAIL_REAUTH";

    private final EmailCredentialRepository credentialRepository;
    private final NotificationService notificationService;
    private final EmailDomainDetector domainDetector;

    public EmailCredentialLifecycleService(
            final EmailCredentialRepository credentialRepository,
            final NotificationService notificationService,
            final EmailDomainDetector domainDetector) {
        this.credentialRepository = credentialRepository;
        this.notificationService = notificationService;
        this.domainDetector = domainDetector;
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
                .findFirstByUserIdOrderByIdDesc(userId);
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
                .findFirstByUserIdOrderByIdDesc(userId);
        if (existing.isEmpty()) {
            return EmailConnectionStatusResponse.disconnected();
        }
        final EmailCredential credential = existing.get();
        final boolean hasSecret = (credential.getAccessTokenEnc() != null
                && !credential.getAccessTokenEnc().isEmpty())
                || (credential.getRefreshTokenEnc() != null
                && !credential.getRefreshTokenEnc().isEmpty());
        final EmailCredential.Status status = credential.getStatus();
        final boolean needsReconnect = status == EmailCredential.Status.NEEDS_REAUTH
                || status == EmailCredential.Status.DISCONNECTED
                || !credential.isSyncEnabled()
                || !hasSecret;
        final boolean connected = hasSecret && status == EmailCredential.Status.ACTIVE
                && credential.isSyncEnabled();
        final EmailCredential.Provider provider = credential.getProvider() == null
                ? EmailCredential.Provider.GMAIL
                : credential.getProvider();
        return new EmailConnectionStatusResponse(
                connected,
                needsReconnect,
                credential.isSyncEnabled(),
                status.name(),
                provider.name(),
                credential.getAuthMode().name(),
                credential.getExpiresAt(),
                credential.getLastError(),
                domainDetector.reconnectPathFor(provider),
                credential.getEmailAddress());
    }

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
            final String providerName = credential.getProvider() == null
                    ? "GMAIL"
                    : credential.getProvider().name();
            final String reconnect = domainDetector.reconnectPathFor(
                    credential.getProvider() == null
                            ? EmailCredential.Provider.GMAIL
                            : credential.getProvider());
            notificationService.sendNotificationToUser(
                    numericUserId,
                    "Email reconnection required",
                    "USPS mail sync stopped because mailbox access was revoked or expired. "
                            + "Reconnect your email to resume Informed Delivery.",
                    NOTIFICATION_TYPE,
                    Map.of(
                            "action", "reconnect",
                            "reconnectPath", reconnect,
                            "provider", providerName));
            credential.setReauthNotifiedAt(Instant.now());
            credentialRepository.save(credential);
        } catch (final NumberFormatException ex) {
            log.debug("Skipping EMAIL_REAUTH notification; userId={} is not numeric",
                    credential.getUserId());
        } catch (final Exception ex) {
            log.warn("Failed to notify user {} about email reauth: {}",
                    credential.getUserId(), ex.getMessage());
        }
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
}
