package com.careconnect.service;

import com.careconnect.dto.ImapConnectRequest;
import com.careconnect.email.EmailDomainDetector;
import com.careconnect.email.EmailProvider;
import com.careconnect.exception.AppException;
import com.careconnect.model.EmailCredential;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.security.TokenCryptor;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Stores IMAP app-password credentials for providers without native OAuth
 * (Yahoo, Apple, AOL, Zoho, Proton, custom domains, etc.).
 */
@Service
@RequiredArgsConstructor
public class ImapEmailCredentialService {

    private final EmailCredentialRepository credRepo;
    private final TokenCryptor tokenCryptor;
    private final EmailCredentialLifecycleService credentialLifecycle;
    private final EmailDomainDetector domainDetector;
    private final EmailAddressValidationService validationService;

    @Transactional
    public EmailCredential connect(final ImapConnectRequest request) {
        if (request == null || request.userId() == null || request.userId().isBlank()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "userId is required");
        }
        if (request.email() == null || request.appPassword() == null || request.appPassword().isBlank()) {
            throw new AppException(HttpStatus.BAD_REQUEST, "email and appPassword are required");
        }
        final var validation = validationService.validate(request.email(), false);
        if (!validation.valid()) {
            throw new AppException(HttpStatus.BAD_REQUEST, validation.error());
        }

        final EmailCredential.Provider detected = domainDetector.detectProvider(request.email());
        final EmailCredential.Provider stored =
                domainDetector.authModeFor(detected) == EmailProvider.AuthMode.OAUTH
                        ? EmailCredential.Provider.IMAP
                        : detected;

        final EmailCredential ec = new EmailCredential();
        ec.setUserId(request.userId());
        ec.setProvider(stored);
        ec.setAuthMode(EmailCredential.AuthMode.IMAP);
        ec.setEmailAddress(request.email().trim());
        ec.setImapUsername(request.email().trim());
        ec.setImapHost(request.imapHost() == null || request.imapHost().isBlank()
                ? domainDetector.defaultImapHost(detected, request.email())
                : request.imapHost().trim());
        ec.setImapPort(request.imapPort() == null ? 993 : request.imapPort());
        ec.setRefreshTokenEnc(tokenCryptor.encrypt(request.appPassword()));
        ec.setAccessTokenEnc(tokenCryptor.encrypt("imap-session"));
        ec.setStatus(EmailCredential.Status.ACTIVE);
        ec.setSyncEnabled(true);
        return credentialLifecycle.activateAfterConnect(credRepo.save(ec));
    }
}
