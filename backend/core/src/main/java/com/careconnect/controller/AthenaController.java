package com.careconnect.controller;

import com.careconnect.config.AthenaProperties;
import com.careconnect.dto.ehr.AthenaConnectRequest;
import com.careconnect.dto.ehr.AthenaConnectionResponse;
import com.careconnect.dto.ehr.AthenaDisconnectResponse;
import com.careconnect.dto.ehr.AthenaResourceDetail;
import com.careconnect.dto.ehr.AthenaResourcePage;
import com.careconnect.dto.ehr.EhrResourceListItem;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.ehr.EhrResourceQueryRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ehr.EhrResourceCategory;
import com.careconnect.service.ehr.athena.AthenaConnectionService;
import com.careconnect.service.ehr.athena.AthenaSyncInProgressException;
import com.careconnect.service.ehr.athena.AthenaSyncResult;
import com.careconnect.service.ehr.athena.AthenaSyncService;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Slice;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.time.LocalDate;
import java.util.Map;

/**
 * The athenahealth surface: connection lifecycle plus a paged read of the patient's own records.
 *
 * <ul>
 *   <li>{@code GET /status}, {@code POST /connect}, {@code POST /sync}, {@code POST /disconnect}</li>
 *   <li>{@code GET /resources?page&size&from&to}: newest first, no total count</li>
 *   <li>{@code GET /resources/{type}/{id}}: one record with its stored FHIR resource</li>
 * </ul>
 *
 * <p>There is no {@code /authorize} or {@code /callback}: 2-legged OAuth has no patient login, so
 * connecting is a consent step rather than a redirect. Patient role only, and every read is scoped to
 * the caller's own rows by the user id in the JWT, never by a request parameter. Errors carry a
 * {@code code} for the client to localize, never display text.
 */
@RestController
@RequestMapping("/api/athena")
@RequiredArgsConstructor
@PreAuthorize("hasRole('PATIENT')")
@ConditionalOnProperty(name = "careconnect.athena.enabled", havingValue = "true")
public class AthenaController {

    static final int MAX_PAGE_SIZE = 100;

    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    private final SecurityUtil securityUtil;
    private final AthenaConnectionService connections;
    private final AthenaSyncService syncService;
    private final EhrResourceQueryRepository resourceQueries;
    private final EhrResourceRepository resources;
    private final ObjectMapper objectMapper;

    @GetMapping("/status")
    public ResponseEntity<?> status() {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(connections.status(me.getId()));
    }

    /** Record consent, link the athena chart and run the first sync. Requires {@code {"consent": true}}. */
    @PostMapping("/connect")
    public ResponseEntity<?> connect(@RequestBody(required = false) final AthenaConnectRequest request) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (request == null || !Boolean.TRUE.equals(request.consent())) {
            return error(HttpStatus.BAD_REQUEST, "CONSENT_REQUIRED");
        }
        try {
            return ResponseEntity.ok(connections.connect(me.getId()));
        } catch (AthenaSyncInProgressException ex) {
            return error(HttpStatus.CONFLICT, "SYNC_IN_PROGRESS");
        }
    }

    /** Manual refresh. */
    @PostMapping("/sync")
    public ResponseEntity<?> sync() {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (!connections.isConnected(me.getId())) {
            return error(HttpStatus.CONFLICT, AthenaConnectionResponse.NOT_CONNECTED);
        }
        try {
            final AthenaSyncResult result = syncService.sync(me.getId());
            if (result.status() == AthenaSyncResult.Status.SOURCE_UNAVAILABLE) {
                return error(HttpStatus.SERVICE_UNAVAILABLE, "SOURCE_UNAVAILABLE");
            }
            return ResponseEntity.ok(result);
        } catch (AthenaSyncInProgressException ex) {
            return error(HttpStatus.CONFLICT, "SYNC_IN_PROGRESS");
        }
    }

    /** Unlink and delete athena data. Responds only after the deletes have committed. */
    @PostMapping("/disconnect")
    public ResponseEntity<?> disconnect() {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(new AthenaDisconnectResponse(true, connections.disconnect(me.getId())));
    }

    /**
     * The caller's athena records, newest first.
     *
     * @param from first day to include (ISO date), optional
     * @param to   last day to include (ISO date), optional
     */
    @GetMapping("/resources")
    public ResponseEntity<?> resources(
            @RequestParam(defaultValue = "0") final int page,
            @RequestParam(defaultValue = "20") final int size,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) final LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) final LocalDate to) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (!connections.isConnected(me.getId())) {
            return error(HttpStatus.CONFLICT, AthenaConnectionResponse.NOT_CONNECTED);
        }
        if (page < 0 || size < 1 || size > MAX_PAGE_SIZE) {
            return error(HttpStatus.BAD_REQUEST, "INVALID_PAGE");
        }
        // Four-digit years only: the bounds are compared as ISO text, and to + 1 day must not overflow.
        final boolean reversed = from != null && to != null && from.isAfter(to);
        if (reversed || outsideFourDigitYears(from) || outsideFourDigitYears(to)) {
            return error(HttpStatus.BAD_REQUEST, "INVALID_DATE_RANGE");
        }
        final Slice<EhrResource> slice = resourceQueries.findPage(
                me.getId(), SOURCE,
                from == null ? null : from.toString(),
                to == null ? null : to.plusDays(1).toString(),
                PageRequest.of(page, size));
        return ResponseEntity.ok(new AthenaResourcePage(
                slice.getContent().stream().map(AthenaController::toItem).toList(),
                page, size, slice.hasNext()));
    }

    @GetMapping("/resources/{type}/{id}")
    public ResponseEntity<?> resource(@PathVariable("type") final String type, @PathVariable("id") final String id) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        if (!connections.isConnected(me.getId())) {
            return error(HttpStatus.CONFLICT, AthenaConnectionResponse.NOT_CONNECTED);
        }
        return resources.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(me.getId(), SOURCE, type, id)
                .<ResponseEntity<?>>map(row -> ResponseEntity.ok(toDetail(row)))
                .orElseGet(() -> error(HttpStatus.NOT_FOUND, "NOT_FOUND"));
    }

    /**
     * An unreadable body or a badly typed parameter is the caller's mistake. Handled here so it is a
     * 400 with a code like every other athena error: the global handler would make the first a 500.
     */
    @ExceptionHandler({HttpMessageNotReadableException.class, MethodArgumentTypeMismatchException.class})
    public ResponseEntity<Map<String, String>> invalidRequest() {
        return error(HttpStatus.BAD_REQUEST, "INVALID_REQUEST");
    }

    private static EhrResourceListItem toItem(final EhrResource row) {
        return new EhrResourceListItem(
                row.getResourceType(),
                row.getResourceFhirId(),
                EhrResourceCategory.categoryFor(row.getResourceType()),
                row.getTitle(),
                row.getStatusValue(),
                row.getOccurredAt(),
                row.getLastSyncedAt() == null ? null : row.getLastSyncedAt().toString(),
                row.getSource());
    }

    private AthenaResourceDetail toDetail(final EhrResource row) {
        final EhrResourceListItem item = toItem(row);
        return new AthenaResourceDetail(item.resourceType(), item.resourceId(), item.category(), item.title(),
                item.status(), item.occurredAt(), item.lastSyncedAt(), item.source(), parse(row.getPayloadJson()));
    }

    private JsonNode parse(final String json) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            return null;
        }
    }

    private static boolean outsideFourDigitYears(final LocalDate date) {
        return date != null && (date.getYear() < 1 || date.getYear() > 9999);
    }

    private static ResponseEntity<Map<String, String>> error(final HttpStatus status, final String code) {
        return ResponseEntity.status(status).body(Map.of("code", code));
    }
}
