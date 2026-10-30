package com.careconnect.controller;

import com.careconnect.config.EpicProperties;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.security.EpicAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.service.consent.ConsentService;
import com.careconnect.service.ehr.EpicAuthStateStore;
import com.careconnect.service.ehr.EpicOAuthService;
import com.careconnect.service.ehr.EpicSyncService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.time.Instant;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class EpicOAuthControllerFlowCoverageTest {

    @Mock private EpicOAuthService epic;
    @Mock private EpicAuthStateStore stateStore;
    @Mock private SecurityUtil securityUtil;
    @Mock private ConsentService consentService;
    @Mock private EpicSyncService syncService;
    @Mock private EhrResourceRepository resourceRepo;
    @Mock private EpicProperties cfg;
    @Mock private EpicAccessPolicy epicAccessPolicy;

    private EpicOAuthController controller;
    private final User patient = User.builder().id(4L).role(Role.PATIENT).build();

    @BeforeEach
    void setUp() {
        controller = new EpicOAuthController(epic, stateStore, securityUtil, consentService, syncService,
                resourceRepo, new ObjectMapper(), cfg, epicAccessPolicy);
        when(cfg.getWebReturnUrl()).thenReturn("http://web/epic");
        when(cfg.getAppReturnDeepLink()).thenReturn("careconnect://epic");
    }

    @Test
    void patientAuthorizeStatusAndDisconnect() {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(stateStore.issue(anyLong(), anyString(), any())).thenReturn("state-1");
        when(epic.buildAuthorizeUrl(anyString(), anyString())).thenReturn("http://epic/authorize");
        assertThat(controller.authorize("web").getBody()).containsEntry("authUrl", "http://epic/authorize");

        EhrCredential cred = new EhrCredential();
        cred.setStatus(EhrCredential.Status.ACTIVE);
        cred.setCreatedAt(Instant.now());
        when(epic.findCredential(4L)).thenReturn(Optional.of(cred));
        assertThat(controller.status().getBody()).containsEntry("connected", true);

        when(syncService.removeEpicData(4L)).thenReturn(3);
        assertThat(controller.disconnect().getBody()).containsEntry("chunksRemoved", 3);
    }

    @Test
    void unauthenticatedCallersAreRejected() {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        assertThat(controller.authorize(null).getStatusCode().value()).isEqualTo(401);
        assertThat(controller.status().getStatusCode().value()).isEqualTo(401);
        assertThat(controller.disconnect().getStatusCode().value()).isEqualTo(401);
    }

    @Test
    void callbackFailureRedirectsWithErrorStatus() {
        when(stateStore.consume("s")).thenReturn(
                new EpicAuthStateStore.Entry(4L, "verifier", "web", Instant.now().plusSeconds(60)));
        when(epic.exchangeAndStore(anyLong(), anyString(), anyString())).thenThrow(new IllegalStateException("tls"));
        assertThat(controller.callback("code", "s", null).getHeaders().getLocation().toString())
                .isEqualTo("http://web/epic?status=error");
    }
}
