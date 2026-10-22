package com.careconnect.controller;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.PatientRepository;
import com.careconnect.service.ehr.CernerAuthStateStore;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerPatientLinkService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.time.Instant;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CernerOAuthControllerTest {

    @Mock private CernerOAuthService oauth;
    @Mock private CernerAuthStateStore states;
    @Mock private CernerPatientLinkService links;
    @Mock private SecurityUtil security;
    @Mock private PatientRepository patients;
    @Mock private CernerProperties config;

    private CernerOAuthController controller;

    @BeforeEach
    void setUp() {
        controller = new CernerOAuthController(oauth, states, links, security, patients, config);
    }

    @Test
    void authorizeBuildsPkceUrlForTheSignedInPatient() {
        User user = User.builder().id(7L).build();
        when(security.resolveCurrentUser()).thenReturn(user);
        when(patients.findByUserId(7L)).thenReturn(Optional.of(Patient.builder().id(42L).build()));
        when(states.issue(eq(7L), anyString(), eq("web"))).thenReturn("state-1");
        when(oauth.buildAuthorizeUrl(eq("state-1"), anyString(), eq("launch-1")))
                .thenReturn("https://authorization.cerner.com/authorize?state=state-1");

        ResponseEntity<Map<String, String>> response = controller.authorize("launch-1", "web");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsEntry(
                "authUrl", "https://authorization.cerner.com/authorize?state=state-1");
    }

    @Test
    void callbackStoresCredentialAndCrosswalkThenRedirects() {
        CernerAuthStateStore.Entry state = new CernerAuthStateStore.Entry(
                7L, "verifier-1", "web", Instant.now().plusSeconds(60));
        EhrCredential credential = EhrCredential.builder()
                .userId(7L)
                .source(CernerProperties.SOURCE_ORACLE_HEALTH)
                .patientFhirId("12724066")
                .build();
        when(states.consume("state-1")).thenReturn(state);
        when(config.getWebReturnUrl()).thenReturn("https://careconnect.example/settings");
        when(oauth.exchangeAndStore(7L, "code-1", "verifier-1")).thenReturn(credential);

        ResponseEntity<Void> response = controller.callback("code-1", "state-1", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);
        assertThat(response.getHeaders().getLocation()).hasToString(
                "https://careconnect.example/settings?status=ok");
        verify(links).link(7L, "12724066");
    }
}
