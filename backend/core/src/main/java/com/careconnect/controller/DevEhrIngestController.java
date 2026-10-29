package com.careconnect.controller;

import com.careconnect.model.User;
import com.careconnect.service.ehr.OracleSandboxIngestService;
import com.careconnect.util.SecurityUtil;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Dev-only trigger for the standalone Oracle Health + Medicare ingest (WBS 5.2.86, "Option B").
 *
 * <p>Pulls Oracle/Cerner records from the open FHIR sandbox and generates a synthetic Medicare set,
 * mirrors both into {@code ehr_resource}, and so makes them appear on the Unified Health
 * {@code ?source=ALL} union for the signed-in patient — no merge of Team C's code, no credentials.
 * Gated on {@code careconnect.oracle.enabled} so it never exists outside dev.
 */
@Slf4j
@RestController
@RequestMapping("/api/dev/ehr")
@ConditionalOnProperty(name = "careconnect.oracle.enabled", havingValue = "true")
@Tag(name = "Dev — EHR ingest", description = "Dev-only standalone Oracle/Medicare ingest for Unified Health")
public class DevEhrIngestController {

    private final SecurityUtil securityUtil;
    private final OracleSandboxIngestService ingestService;

    public DevEhrIngestController(final SecurityUtil securityUtil,
                                  final OracleSandboxIngestService ingestService) {
        this.securityUtil = securityUtil;
        this.ingestService = ingestService;
    }

    @PostMapping("/ingest")
    @Operation(summary = "Ingest + mirror Oracle Health and Medicare for the signed-in patient",
            description = "Open-sandbox Oracle fetch + synthetic Medicare set, projected into ehr_resource. "
                    + "Returns a per-source count of raw payloads stored and mirror rows produced.")
    public ResponseEntity<Map<String, Object>> ingest() {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        log.info("Dev EHR ingest requested by user {}", me.getId());
        return ResponseEntity.ok(ingestService.ingestAll(me.getId()));
    }
}
