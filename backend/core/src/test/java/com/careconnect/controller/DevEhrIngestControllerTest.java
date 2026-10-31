package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.service.ehr.OracleSandboxIngestService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/** Unit tests for {@link DevEhrIngestController}: auth guard + delegation to the ingest service. */
class DevEhrIngestControllerTest {

    private final SecurityUtil securityUtil = mock(SecurityUtil.class);
    private final OracleSandboxIngestService ingestService = mock(OracleSandboxIngestService.class);
    private final DevEhrIngestController controller =
            new DevEhrIngestController(securityUtil, ingestService);

    @Test
    void returns401WhenNoAuthenticatedUser() {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        final ResponseEntity<Map<String, Object>> resp = controller.ingest();
        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        verifyNoInteractions(ingestService);
    }

    @Test
    void ingestsForTheAuthenticatedUser() {
        final User me = mock(User.class);
        when(me.getId()).thenReturn(7L);
        when(securityUtil.resolveCurrentUser()).thenReturn(me);
        final Map<String, Object> body = Map.of("ORACLE_HEALTH", Map.of("mirrorRows", 2));
        when(ingestService.ingestAll(7L)).thenReturn(body);

        final ResponseEntity<Map<String, Object>> resp = controller.ingest();

        assertThat(resp.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(resp.getBody()).isEqualTo(body);
    }
}
