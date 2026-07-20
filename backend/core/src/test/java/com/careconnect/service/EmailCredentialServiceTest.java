package com.careconnect.service;

import com.careconnect.dto.EmailConnectionStatus;
import com.careconnect.model.EmailCredential;
import com.careconnect.model.User;
import com.careconnect.repository.EmailCredentialRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.OAuthRedirectValidator;
import com.careconnect.security.OAuthStateSigner;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class EmailCredentialServiceTest {

    @Mock private EmailCredentialRepository credRepo;
    @Mock private GoogleOAuthService googleOAuthService;
    @Mock private UserRepository userRepository;
    @Mock private SecurityUtil securityUtil;
    @Mock private AuthorizationService authorizationService;
    @Mock private OAuthStateSigner oauthStateSigner;
    @Mock private OAuthRedirectValidator oauthRedirectValidator;

    @InjectMocks
    private EmailCredentialService service;

    private User patientUser;

    @BeforeEach
    void setUp() {
        patientUser = new User();
        patientUser.setId(42L);
        patientUser.setEmail("patient@example.com");
        patientUser.setRole(Role.PATIENT);
    }

    @Nested
    @DisplayName("Patient self-service")
    class PatientSelfService {

        @Test
        @DisplayName("patient can read own Gmail status without explicit patientEmail param")
        void patientCanReadOwnStatus() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

            EmailCredential credential = new EmailCredential();
            credential.setUserId("42");
            credential.setProvider(EmailCredential.Provider.GMAIL);
            credential.setAccessTokenEnc("enc");
            credential.setExpiresAt(Instant.now().plusSeconds(3600));

            when(credRepo.findFirstByUserIdAndProviderOrderByIdDesc("42", EmailCredential.Provider.GMAIL))
                    .thenReturn(Optional.of(credential));
            when(googleOAuthService.ensureFreshToken(credential)).thenReturn(credential);

            EmailConnectionStatus status = service.getGmailConnectionStatus(null);

            assertThat(status.connected()).isTrue();
            verify(authorizationService).requirePatientAccess(patientUser, 42L);
        }

        @Test
        @DisplayName("patient can request own Gmail connect URL")
        void patientCanRequestConnectUrl() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
            when(oauthRedirectValidator.sanitizeReturnUrl("http://localhost/usps-test"))
                    .thenReturn("http://localhost/usps-test");
            when(oauthStateSigner.signStartToken("42", "http://localhost/usps-test"))
                    .thenReturn("signed-start");

            String token = service.createGmailOAuthStartToken(null, "http://localhost/usps-test");

            assertThat(token).isEqualTo("signed-start");
            verify(authorizationService).requirePatientAccess(patientUser, 42L);
        }

        @Test
        @DisplayName("patient can disconnect own Gmail account")
        void patientCanDisconnectOwnGmail() throws Exception {
            when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);

            EmailCredential credential = new EmailCredential();
            credential.setUserId("42");
            credential.setProvider(EmailCredential.Provider.GMAIL);
            when(credRepo.findFirstByUserIdAndProviderOrderByIdDesc("42", EmailCredential.Provider.GMAIL))
                    .thenReturn(Optional.of(credential));

            service.disconnectGmail(null);

            verify(authorizationService).requirePatientAccess(patientUser, 42L);
            verify(googleOAuthService).revokeIfPossible(credential);
            verify(credRepo).delete(credential);
        }

        @Test
        @DisplayName("patient cannot access another patient's Gmail status")
        void patientCannotAccessOtherPatient() throws Exception {
            User otherPatient = new User();
            otherPatient.setId(99L);
            otherPatient.setEmail("other@example.com");
            otherPatient.setRole(Role.PATIENT);

            when(securityUtil.resolveCurrentUser()).thenReturn(patientUser);
            when(userRepository.findByEmail("other@example.com")).thenReturn(Optional.of(otherPatient));
            doThrow(new UnauthorizedException("Patients can only access their own data"))
                    .when(authorizationService).requirePatientAccess(patientUser, 99L);

            assertThatThrownBy(() -> service.getGmailConnectionStatus("other@example.com"))
                    .isInstanceOf(UnauthorizedException.class)
                    .hasMessageContaining("only access their own data");
        }
    }
}
