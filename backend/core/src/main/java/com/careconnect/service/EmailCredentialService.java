package com.careconnect.service;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.exception.EmailCredentialNeedsReauthException;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.OAuthRedirectValidator;
import com.careconnect.security.OAuthStateSigner;
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
    private final SecurityUtil securityUtil;
    private final AuthorizationService authorizationService;
    private final OAuthStateSigner oauthStateSigner;
    private final OAuthRedirectValidator oauthRedirectValidator;
    private final UspsPatientResolver patientResolver;

    private static boolean hasStoredAccessToken(EmailCredential credential) {
        return credential.getAccessTokenEnc() != null && !credential.getAccessTokenEnc().isBlank();
    }

    public EmailConnectionStatus getGmailConnectionStatus(String patientIdentifier)
            throws UnauthorizedException {
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

    /**
     * Issues a short-lived start token after patient-scoped authorization.
     * The token is consumed by {@code /oauth/google/start} in an external browser.
     */
    public String createGmailOAuthStartToken(String patientIdentifier, String returnUrl)
            throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        User patientUser = resolvePatientUser(patientIdentifier, currentUser);
        authorizationService.requirePatientAccess(currentUser, patientUser.getId());

        String sanitizedReturnUrl = oauthRedirectValidator.sanitizeReturnUrl(returnUrl);
        return oauthStateSigner.signStartToken(String.valueOf(patientUser.getId()), sanitizedReturnUrl);
    }

    private User resolvePatientUser(String patientIdentifier, User currentUser)
            throws UnauthorizedException {
        return patientResolver.resolvePatient(patientIdentifier, null, currentUser);
    }
}
