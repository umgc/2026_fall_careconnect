package com.careconnect.controller;

import com.careconnect.service.CallSummaryService;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Read-side endpoint for retrieving a call summary by its database identifier.
 *
 * <p>Implements WBS 3.11.6 ({@code GET /api/summaries/{id}}). Path is
 * versioned under {@code /api/v3/} to match the surrounding controller
 * conventions on this codebase (see {@code CallController} at
 * {@code /api/v3/calls}).
 *
 * <p>The response shape matches
 * {@link CallSummaryService#getLatestSummary(String)} so consumers can treat
 * the two read endpoints as interchangeable: legacy callers hitting
 * {@code GET /api/v3/calls/{callId}/summary} and new callers hitting
 * {@code GET /api/v3/summaries/{id}} deserialize identically.
 *
 * <p><b>RBAC status (as of this PR):</b> per Brandon Jackson's RBAC guide
 * rule 5, role annotations should be added only after the access matrix is
 * confirmed. Proposed access for this endpoint is
 * {@code hasAnyRole('CAREGIVER','PATIENT','ADMIN')} \u2014 awaiting Brandon's
 * sign-off. In addition, {@code @EnableMethodSecurity} is not yet present
 * in the codebase, so any {@code @PreAuthorize} on this endpoint would be
 * a silent no-op until method security is enabled in
 * {@code SecurityConfig}. The annotation will be added in a follow-up PR
 * once both prerequisites are in place.
 */
@RestController
@RequestMapping("/api/v3/summaries")
@RequiredArgsConstructor
public class CallSummaryController {

    private final CallSummaryService callSummaryService;

    /**
     * Returns the stored summary payload for the given database identifier,
     * or 404 when no matching row exists.
     *
     * @param id database identifier of the summary row
     * @return 200 with the summary response map, 404 when not found
     */
    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getSummaryById(
            @PathVariable("id") final Long id) {
        return callSummaryService.getSummaryById(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }
}