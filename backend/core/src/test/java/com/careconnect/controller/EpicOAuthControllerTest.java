package com.careconnect.controller;

import com.careconnect.config.EpicProperties;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrCredential;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ConsentService;
import com.careconnect.service.ehr.EpicAuthStateStore;
import com.careconnect.service.ehr.EpicOAuthService;
import com.careconnect.service.ehr.EpicSyncService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.client.RestClientResponseException;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link EpicOAuthController} — authentication gating, the callback redirect targets
 * (web vs. mobile deep link, success vs. error), and the diagnostic {@code /resync} error mapping.
 * Collaborators are mocked and the controller is driven directly (no Spring context). Closes review
 * Gap 1 (EpicOAuthControllerTest was missing).
 */
class EpicOAuthControllerTest {

    private final EpicOAuthService epic = mock(EpicOAuthService.class);
    private final EpicAuthStateStore stateStore = mock(EpicAuthStateStore.class);
    private final SecurityUtil securityUtil = mock(SecurityUtil.class);
    private final ConsentService consentService = mock(ConsentService.class);
    private final EpicSyncService syncService = mock(EpicSyncService.class);
    private final EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
    private final EpicProperties cfg = mock(EpicProperties.class);

    private EpicOAuthController newController() {
        return new EpicOAuthController(epic, stateStore, securityUtil, consentService,
                syncService, resourceRepo, new ObjectMapper(), cfg);
    }

    private User userWithId(long id) {
        User me = mock(User.class);
        when(me.getId()).thenReturn(id);
        return me;
    }

    private EpicAuthStateStore.Entry entry(long userId, String returnMode) {
        return new EpicAuthStateStore.Entry(
                userId, "verifier", returnMode, Instant.now().plusSeconds(300));
    }

    // ---- auth gating -----------------------------------------------------

    @Test
    void resync_returnsUnauthorized_whenNoCurrentUser() {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        ResponseEntity<Map<String, Object>> resp = newController().resync("auto");

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.UNAUTHORIZED.value());
    }

    // ---- callback redirect targets --------------------------------------

    @Test
    void callback_webMode_success_redirectsToWebUrlWithOk_andRunsConnectSteps() {
        when(stateStore.consume("st")).thenReturn(entry(7L, "web"));
        when(cfg.getWebReturnUrl()).thenReturn("https://web.example/#/epic-linked");
        EhrCredential cred = new EhrCredential();
        cred.setPatientFhirId("Patient/1");
        when(epic.exchangeAndStore(7L, "code", "verifier")).thenReturn(cred);

        ResponseEntity<Void> resp = newController().callback("code", "st", null);

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.FOUND.value());
        assertThat(resp.getHeaders().getLocation()).isNotNull();
        assertThat(resp.getHeaders().getLocation().toString())
                .isEqualTo("https://web.example/#/epic-linked?status=ok");
        verify(consentService).recordEhrImportConsent(7L);
        verify(syncService).linkPatientCrosswalk(7L, "Patient/1");
        verify(syncService).enqueueInitialSync(7L);
    }

    @Test
    void callback_withErrorParam_redirectsToDeepLinkWithError_andDoesNotExchange() {
        when(stateStore.consume("st")).thenReturn(entry(7L, null)); // no returnMode -> deep link
        when(cfg.getAppReturnDeepLink()).thenReturn("careconnect://epic/linked");

        ResponseEntity<Void> resp = newController().callback(null, "st", "access_denied");

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.FOUND.value());
        assertThat(resp.getHeaders().getLocation().toString())
                .isEqualTo("careconnect://epic/linked?status=error");
        verify(epic, never()).exchangeAndStore(anyLong(), anyString(), anyString());
    }

    @Test
    void callback_unknownState_returnsBadRequest() {
        when(stateStore.consume("bad")).thenReturn(null);
        when(cfg.getAppReturnDeepLink()).thenReturn("careconnect://epic/linked");

        ResponseEntity<Void> resp = newController().callback(null, "bad", null);

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.BAD_REQUEST.value());
    }

    // ---- resync result / error mapping ----------------------------------

    @Test
    void resync_success_returnsStoredCountAndOk() {
        User me = userWithId(7L); // build the stubbed user before the outer when(), not nested in it
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        when(syncService.syncNow(7L, EpicSyncService.SyncMode.DELTA)).thenReturn(5);

        ResponseEntity<Map<String, Object>> resp = newController().resync("auto");

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.OK.value());
        assertThat(resp.getBody()).containsEntry("ok", true);
        assertThat(resp.getBody()).containsEntry("stored", 5);
        assertThat(resp.getBody()).containsEntry("mode", "DELTA");
    }

    @Test
    void resync_upstreamFailure_diagnosticsVerbose_returns502WithCauseAndCorrelationId() {
        User me = userWithId(7L);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        when(cfg.isDiagnosticsVerbose()).thenReturn(true); // dev/sandbox: echo the cause
        RestClientResponseException upstream = new RestClientResponseException(
                "403 Forbidden", 403, "Forbidden", null,
                "{\"error\":\"access_denied\"}".getBytes(StandardCharsets.UTF_8),
                StandardCharsets.UTF_8);
        when(syncService.syncNow(7L, EpicSyncService.SyncMode.DELTA)).thenThrow(upstream);

        ResponseEntity<Map<String, Object>> resp = newController().resync("auto");

        // Upstream Epic failure -> real 502 (not 200), with the cause echoed in verbose builds.
        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.BAD_GATEWAY.value());
        assertThat(resp.getBody()).containsEntry("ok", false);
        assertThat(resp.getBody()).containsEntry("httpStatus", 403);
        assertThat(resp.getBody()).containsEntry("responseBody", "{\"error\":\"access_denied\"}");
        assertThat(resp.getBody().get("error").toString()).contains("RestClientResponseException");
        assertThat(resp.getBody().get("correlationId")).isNotNull();
    }

    @Test
    void resync_upstreamFailure_diagnosticsOff_returns502Generic_withoutLeakingInternals() {
        User me = userWithId(7L);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        // cfg.isDiagnosticsVerbose() defaults to false (production).
        RestClientResponseException upstream = new RestClientResponseException(
                "403 Forbidden", 403, "Forbidden", null,
                "{\"error\":\"access_denied\"}".getBytes(StandardCharsets.UTF_8),
                StandardCharsets.UTF_8);
        when(syncService.syncNow(7L, EpicSyncService.SyncMode.DELTA)).thenThrow(upstream);

        ResponseEntity<Map<String, Object>> resp = newController().resync("auto");

        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.BAD_GATEWAY.value());
        assertThat(resp.getBody()).containsEntry("ok", false);
        assertThat(resp.getBody()).containsEntry("error", "sync_failed");
        assertThat(resp.getBody().get("correlationId")).isNotNull();
        // No internals leak: no exception class, message, root cause, Epic status, or response body.
        assertThat(resp.getBody()).doesNotContainKeys(
                "message", "rootCause", "httpStatus", "responseBody");
    }

    @Test
    void resync_internalFailure_returns500Generic() {
        User me = userWithId(7L);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        when(syncService.syncNow(7L, EpicSyncService.SyncMode.DELTA))
                .thenThrow(new IllegalStateException("No Epic credential for user 7"));

        ResponseEntity<Map<String, Object>> resp = newController().resync("auto");

        // Non-upstream (our side) -> 500, still generic with a correlation id.
        assertThat(resp.getStatusCode().value()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR.value());
        assertThat(resp.getBody()).containsEntry("ok", false);
        assertThat(resp.getBody()).containsEntry("error", "sync_failed");
        assertThat(resp.getBody().get("correlationId")).isNotNull();
    }
}
