package com.careconnect.controller;

import com.careconnect.exception.AppException;
import com.careconnect.model.CallSummary;
import com.careconnect.model.User;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.Role;
import com.careconnect.service.CallSessionService;
import com.careconnect.service.CallSummaryService;
import com.careconnect.service.CaregiverService;

import java.util.Map;
import java.util.Optional;

import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
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
 * <p><b>Authorization:</b> two-layer check.
 * <ol>
 *   <li>{@code @PreAuthorize} gates the endpoint at the role level to
 *       {@code CAREGIVER}, {@code PATIENT}, or {@code ADMIN}. Silent
 *       no-op until Brandon's {@code feature/bjackson-rbac-infrastructure}
 *       branch enables {@code @EnableMethodSecurity} in
 *       {@code SecurityConfig}.</li>
 *   <li>The endpoint authorizes only admin, durable historical call
 *       participants, or callers with a current patient relationship via
 *       existing scope APIs. Telemetry targets, transcript access, and
 *       summary generator ownership are not authorization sources.</li>
 * </ol>
 */
@RestController
@RequestMapping("/api/v3/summaries")
@RequiredArgsConstructor
public class CallSummaryController {

    private static final String MSG_ACCESS_DENIED = "Access denied";

    private final CallSummaryService callSummaryService;
    private final CallSessionService callSessionService;
    private final CaregiverService caregiverService;
    private final UserRepository userRepository;

    /**
     * Returns the stored summary payload for the given database identifier,
     * or 404 when no matching row exists, or 403 when the caller lacks
     * access to this summary.
     *
     * @param id database identifier of the summary row
     * @return 200 with the summary response map, 404 when not found,
     *         403 when the caller is not admin / historical participant /
     *         current patient relationship
     */
    @PreAuthorize("hasAnyRole('CAREGIVER', 'PATIENT', 'ADMIN')")
    @GetMapping("/{id}")
    public ResponseEntity<Map<String, Object>> getSummaryById(
            @PathVariable("id") final Long id) {
        final Optional<CallSummary> entity = callSummaryService.getSummaryEntityById(id);
        if (entity.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        final CallSummary summary = entity.get();
        final User currentUser = getCurrentUser();

        if (!canAccessSummary(currentUser, summary)) {
            throw new AppException(HttpStatus.FORBIDDEN, MSG_ACCESS_DENIED);
        }

        return callSummaryService.getSummaryById(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    private boolean canAccessSummary(final User currentUser, final CallSummary summary) {
        if (currentUser.getRole() == Role.ADMIN) {
            return true;
        }
        try {
            callSessionService.requireHistoricalParticipant(
                    summary.getCallId(), currentUser.getId());
            return true;
        } catch (AppException ignored) {
            // Fall through to current patient relationship.
        }
        if (summary.getPatientId() == null) {
            return false;
        }
        try {
            return caregiverService.hasAccessToPatient(
                    currentUser.getId(), summary.getPatientId());
        } catch (RuntimeException accessFailure) {
            return false;
        }
    }

    /**
     * Resolves the current authenticated user via the security context and
     * user repository, mirroring {@code CallController.getCurrentUser}.
     */
    private User getCurrentUser() {
        final Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        final String userEmail = authentication.getName();
        return userRepository
                .findByEmail(userEmail)
                .orElseThrow(() -> new AppException(HttpStatus.UNAUTHORIZED, "User not authenticated"));
    }
}
