package com.careconnect.service;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;

@Service
@RequiredArgsConstructor
public class EmailCredentialService {

    private final EmailCredentialRepository credRepo;
    private final GoogleOAuthService googleOAuthService;
    private final UserRepository userRepository;
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;

    public EmailConnectionStatus getGmailConnectionStatus(String patientIdentifier) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientIdentifier, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String userId = String.valueOf(patientUser.getId());
        Optional<EmailCredential> credOpt = credRepo
                .findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL);

        if (credOpt.isEmpty()) {
            return EmailConnectionStatus.notConnected(EmailCredential.Provider.GMAIL);
        }

        EmailCredential credential = credOpt.get();
        if (!hasStoredAccessToken(credential)) {
            return EmailConnectionStatus.needsReconnect(
                    EmailCredential.Provider.GMAIL,
                    "Gmail connection is incomplete. Please reconnect your account.");
        }

        try {
            EmailCredential refreshed = googleOAuthService.ensureFreshToken(credential);
            if (refreshed == null || !hasStoredAccessToken(refreshed)) {
                return EmailConnectionStatus.needsReconnect(
                        EmailCredential.Provider.GMAIL,
                        "Gmail access expired. Please reconnect your Google account.");
            }
            Instant expiresAt = refreshed.getExpiresAt();
            return EmailConnectionStatus.connected(EmailCredential.Provider.GMAIL, expiresAt);
        } catch (EmailCredentialNeedsReauthException ex) {
            return EmailConnectionStatus.needsReconnect(
                    EmailCredential.Provider.GMAIL,
                    ex.getMessage() != null
                            ? ex.getMessage()
                            : "Gmail access expired. Please reconnect your Google account.");
        }
    }

    @Transactional
    public void disconnectGmail(String patientIdentifier) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientIdentifier, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String userId = String.valueOf(patientUser.getId());
        credRepo.findFirstByUserIdAndProviderOrderByIdDesc(userId, EmailCredential.Provider.GMAIL)
                .ifPresent(cred -> {
                    googleOAuthService.revokeIfPossible(cred);
                    credRepo.delete(cred);
                });
    }

    private User resolvePatientUser(String patientIdentifier, User currentUser) throws UnauthorizedException {
        if (patientIdentifier == null || patientIdentifier.isBlank() || "demo-user".equals(patientIdentifier)) {
            return currentUser;
        }
        return userRepository.findByEmail(patientIdentifier)
                .or(() -> parseNumericUserId(patientIdentifier).flatMap(userRepository::findById))
                .orElseThrow(() -> new UnauthorizedException(
                        "No patient found for identifier: " + patientIdentifier));
    }

    private static Optional<Long> parseNumericUserId(String value) {
        try {
            return Optional.of(Long.parseLong(value));
        } catch (NumberFormatException e) {
            return Optional.empty();
        }
    }

    private static boolean hasStoredAccessToken(EmailCredential credential) {
        return credential.getAccessTokenEnc() != null && !credential.getAccessTokenEnc().isBlank();
    }
}
