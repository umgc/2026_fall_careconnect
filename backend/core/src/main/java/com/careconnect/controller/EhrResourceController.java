package com.careconnect.controller;

import com.careconnect.config.AthenaProperties;
import com.careconnect.config.EpicProperties;
import com.careconnect.dto.ehr.EhrResourceListItem;
import com.careconnect.dto.ehr.EhrSourceView;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.security.EpicAccessPolicy;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.service.ehr.EhrResourceCategory;
import com.careconnect.util.SecurityUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.headers.Header;
import io.swagger.v3.oas.annotations.media.ArraySchema;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * Source-generic read surface over the {@code ehr_resource} mirror for the Unified Health Data
 * screen. Read-only; scoped to the caller's own rows (userId from the JWT, never a client-supplied
 * id). Backs the browse/list and the demographics info card. Contract:
 * Cononical_0_Epic-Unified-Health-Data-Integration_v1_2 §5–§6.
 *
 * <p>Deliberately NOT gated on {@code careconnect.epic.enabled}: the surface is source-agnostic
 * ({@code ?source=}) so it serves future connectors, and it simply returns an empty list when the
 * caller has no mirrored rows. {@code EPIC} is the only live source today, so it is the default.
 */
@Slf4j
@RestController
@RequestMapping("/api/ehr")
@RequiredArgsConstructor
@Tag(name = "Unified Health Data",
        description = "Source-generic read surface over the mirrored EHR records, scoped to the "
                + "authenticated caller. Backs the Unified Health Data screen.")
public class EhrResourceController {

    private static final String PATIENT_TYPE = "Patient";

    /** Token selecting all-sources (union) mode on the read surface (WBS 5.2.83). */
    private static final String ALL_SOURCES = "ALL";

    /**
     * Precedence for the demographics primary-source rule (WBS 5.2.83): when {@code ?source=ALL}
     * and more than one source mirrors a Patient row, the card shows the first source present in
     * this order. EPIC is the richest/most-authoritative today; Oracle Health is last (newest,
     * not yet live).
     */
    private static final List<String> SOURCE_PRECEDENCE = List.of(
            EpicProperties.SOURCE_EPIC,
            AthenaProperties.SOURCE_ATHENA,
            MedicareProperties.SOURCE_MEDICARE,
            "ORACLE_HEALTH");

    private final SecurityUtil securityUtil;
    private final EhrResourceRepository resourceRepo;
    private final ObjectMapper objectMapper;
    private final EpicAccessPolicy epicAccessPolicy;
    private final EhrSourceRepository ehrSourceRepository;
    private final ConsentGrantRepository consentGrants;

    /**
     * List the caller's mirrored records, filterable by category / free text and sortable. All
     * params optional: {@code source} (default EPIC, normalized to stored casing), {@code category}
     * (UI category, e.g. Conditions), {@code q} (matches title / resourceType),
     * {@code sort} (latest|earliest|az|za, default latest). The Patient row is excluded — its
     * demographics are served by {@link #patient(String)}. The newest sync time is returned in the
     * {@code X-Last-Synced-At} header (the screen's "Last updated").
     */
    @GetMapping("/resources")
    @Operation(
            summary = "List the caller's mirrored EHR records",
            description = "Returns the authenticated caller's mirrored records (the Patient "
                    + "demographics row is excluded; see GET /api/ehr/patient). All query params are "
                    + "optional. The newest sync time is returned in the X-Last-Synced-At response "
                    + "header (the screen's \"Last updated\").")
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Records returned (empty list when the caller has no mirrored rows)",
                    headers = @Header(
                            name = "X-Last-Synced-At",
                            description = "ISO-8601 instant of the newest sync for the source; "
                                    + "omitted when the caller has no mirrored rows",
                            schema = @Schema(type = "string", format = "date-time")),
                    content = @Content(
                            mediaType = "application/json",
                            array = @ArraySchema(schema = @Schema(implementation = EhrResourceListItem.class)))),
            @ApiResponse(responseCode = "401", description = "No authenticated caller", content = @Content)
    })
    public ResponseEntity<List<EhrResourceListItem>> resources(
            @Parameter(description = "Source system; defaults to EPIC (the only live source). "
                    + "Case-insensitive — normalized to the stored casing.", example = "EPIC")
            @RequestParam(value = "source", required = false) final String source,
            @Parameter(description = "Filter to a single UI category (e.g. Conditions, Medications). "
                    + "Omit for all categories.", example = "Conditions")
            @RequestParam(value = "category", required = false) final String category,
            @Parameter(description = "Free-text search matched against the record title and "
                    + "resourceType (case-insensitive).")
            @RequestParam(value = "q", required = false) final String q,
            @Parameter(description = "Sort order: latest | earliest | az | za.",
                    schema = @Schema(allowableValues = {"latest", "earliest", "az", "za"},
                            defaultValue = "latest"))
            @RequestParam(value = "sort", required = false, defaultValue = "latest") final String sort,
            @Parameter(description = "Patient whose records to read; defaults to the caller. A "
                    + "caregiver may pass a patient's user id and reads it only with an active link "
                    + "and the patient's EHR_VIEW consent (otherwise a uniform 404).")
            @RequestParam(value = "patientUserId", required = false) final Long patientUserId) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final Long target = patientUserId != null ? patientUserId : me.getId();
        epicAccessPolicy.requireEhrReadAccess(me, target);
        // All-sources (union) mode when source=ALL; otherwise the single-source path (default EPIC).
        final boolean allSources = isAllSources(source);
        final String src = allSources ? null : normalizeSource(source);
        final String qLower = (q == null || q.isBlank()) ? null : q.toLowerCase(Locale.ROOT);
        // Medicare data needs its own MEDICARE_VIEW consent; the EHR_VIEW check above does not imply
        // it (the two are parallel, independent scopes). Drop MEDICARE-sourced rows for a caller who
        // lacks it, rather than refusing the whole request, so the other sources still return.
        final boolean maySeeMedicare = mayReadMedicare(me, target);

        final List<EhrResource> rows = (allSources
                ? resourceRepo.findByUserId(target)
                : resourceRepo.findByUserIdAndSource(target, src)).stream()
                .filter(r -> maySeeMedicare
                        || !MedicareProperties.SOURCE_MEDICARE.equalsIgnoreCase(r.getSource()))
                .collect(Collectors.toList());
        final List<EhrResourceListItem> items = rows.stream()
                .filter(r -> !PATIENT_TYPE.equals(r.getResourceType()))
                // Stamp provenance from the row's own source in union mode so each item keeps its
                // real source; the single-source path echoes the requested (normalized) source.
                .map(r -> toItem(r, allSources ? r.getSource() : src))
                .filter(it -> category == null || category.isBlank()
                        || category.equalsIgnoreCase(it.category()))
                .filter(it -> qLower == null
                        || (it.title() != null && it.title().toLowerCase(Locale.ROOT).contains(qLower))
                        || (it.resourceType() != null
                            && it.resourceType().toLowerCase(Locale.ROOT).contains(qLower)))
                .sorted(comparatorFor(sort))
                .collect(Collectors.toList());

        final Instant maxSynced = allSources
                ? resourceRepo.findMaxLastSyncedAt(target)
                : resourceRepo.findMaxLastSyncedAt(target, src);
        final ResponseEntity.BodyBuilder builder = ResponseEntity.ok();
        if (maxSynced != null) {
            builder.header("X-Last-Synced-At", maxSynced.toString());
        }
        return builder.body(items);
    }

    /**
     * Patient demographics for the info card: {@code name}, {@code birthDate}, {@code gender} parsed
     * from the mirrored Patient resource's raw FHIR payload. 404 when no Patient row exists for the
     * source.
     */
    @GetMapping("/patient")
    @Operation(
            summary = "Patient demographics for the info card",
            description = "Returns name, birthDate and gender parsed from the caller's mirrored "
                    + "Patient resource, plus the resolved source.")
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Demographics returned",
                    content = @Content(
                            mediaType = "application/json",
                            schema = @Schema(
                                    example = "{\"name\":\"Jane Doe\",\"birthDate\":\"1948-07-21\","
                                            + "\"gender\":\"female\",\"source\":\"EPIC\"}"))),
            @ApiResponse(responseCode = "401", description = "No authenticated caller", content = @Content),
            @ApiResponse(responseCode = "404",
                    description = "No Patient row mirrored for the source", content = @Content)
    })
    public ResponseEntity<Map<String, Object>> patient(
            @Parameter(description = "Source system; defaults to EPIC (the only live source). "
                    + "Case-insensitive — normalized to the stored casing.", example = "EPIC")
            @RequestParam(value = "source", required = false) final String source,
            @Parameter(description = "Patient whose demographics to read; defaults to the caller. A "
                    + "caregiver may pass a patient's user id and reads it only with an active link "
                    + "and the patient's EHR_VIEW consent (otherwise a uniform 404).")
            @RequestParam(value = "patientUserId", required = false) final Long patientUserId) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final Long target = patientUserId != null ? patientUserId : me.getId();
        epicAccessPolicy.requireEhrReadAccess(me, target);
        // Medicare demographics also require MEDICARE_VIEW: exclude a MEDICARE Patient row from the
        // primary-source pick (and from a direct single-source read) for a caller who lacks it.
        final boolean maySeeMedicare = mayReadMedicare(me, target);
        // All-sources mode applies the primary-source rule: when more than one source mirrors a
        // Patient row, return the one highest in SOURCE_PRECEDENCE. Single-source mode is unchanged.
        final boolean allSources = isAllSources(source);
        final Optional<EhrResource> patientRow;
        if (allSources) {
            patientRow = resourceRepo.findByUserId(target).stream()
                    .filter(r -> PATIENT_TYPE.equals(r.getResourceType()))
                    .filter(r -> maySeeMedicare
                            || !MedicareProperties.SOURCE_MEDICARE.equalsIgnoreCase(r.getSource()))
                    .min(Comparator.comparingInt(r -> sourcePrecedence(r.getSource())));
        } else {
            final String src = normalizeSource(source);
            patientRow = resourceRepo.findByUserIdAndSource(target, src).stream()
                    .filter(r -> PATIENT_TYPE.equals(r.getResourceType()))
                    .filter(r -> maySeeMedicare
                            || !MedicareProperties.SOURCE_MEDICARE.equalsIgnoreCase(r.getSource()))
                    .findFirst();
        }
        if (patientRow.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        final EhrResource row = patientRow.get();
        final JsonNode fhir = parsePayload(row.getPayloadJson());
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", parseName(fhir));
        body.put("birthDate", textOf(fhir, "birthDate"));
        body.put("gender", textOf(fhir, "gender"));
        // Report the source actually chosen (the stored code), so the primary source is explicit.
        body.put("source", row.getSource());
        return ResponseEntity.ok(body);
    }

    /**
     * EHR source catalog — the {@code ehr_source} registry the frontend maps stored
     * {@code ehr_resource.source} codes against (WBS 5.2.82). Additive and source-neutral: it
     * lets the client drive its {@code RecordSource} handling from the DB single source of truth
     * instead of hardcoding tokens, so backend and frontend source codes cannot silently drift.
     */
    @GetMapping("/sources")
    @Operation(
            summary = "List the EHR source catalog",
            description = "Returns the seeded ehr_source registry as {code, displayName, enabled}, "
                    + "the canonical tokens the frontend maps ehr_resource.source values against.")
    @ApiResponses({
            @ApiResponse(responseCode = "200", description = "Source catalog returned"),
            @ApiResponse(responseCode = "401", description = "No authenticated caller", content = @Content)
    })
    public ResponseEntity<List<EhrSourceView>> sources() {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final List<EhrSourceView> catalog = ehrSourceRepository.findAll().stream()
                .map(s -> new EhrSourceView(
                        s.getCode(),
                        s.getDisplayName(),
                        Boolean.TRUE.equals(s.getEnabled())))
                .sorted(Comparator.comparing(EhrSourceView::code))
                .collect(Collectors.toList());
        return ResponseEntity.ok(catalog);
    }

    // --- helpers ---

    /** True when the caller explicitly requested the union across all sources ({@code source=ALL}). */
    private static boolean isAllSources(final String source) {
        return source != null && ALL_SOURCES.equalsIgnoreCase(source.trim());
    }

    /** Rank of a stored source code in {@link #SOURCE_PRECEDENCE}; unknown sources sort last. */
    private static int sourcePrecedence(final String source) {
        final int idx = SOURCE_PRECEDENCE.indexOf(source == null ? "" : source);
        return idx < 0 ? Integer.MAX_VALUE : idx;
    }

    /**
     * Whether {@code caller} may see the target patient's {@code MEDICARE}-sourced rows on this
     * surface: true when the caller is the patient reading their own record, or a caregiver the
     * patient has given an active {@code MEDICARE_VIEW} grant. {@code EHR_VIEW} (enforced separately
     * by {@link EpicAccessPolicy}) does not imply Medicare access — the two are parallel, independent
     * consent scopes (see {@link MedicareAccessPolicy}). {@code target} is a user id, so the grant is
     * checked directly rather than via {@code MedicareAccessPolicy} (which keys on patient id and
     * refuses the whole request); here we filter out Medicare rows so the other sources still return.
     */
    private boolean mayReadMedicare(final User caller, final Long target) {
        if (caller.getId() != null && caller.getId().equals(target)) {
            return true;
        }
        return consentGrants.existsActiveGrant(
                target, caller.getId(), MedicareAccessPolicy.SCOPE_MEDICARE_VIEW, Instant.now());
    }

    private EhrResourceListItem toItem(final EhrResource r, final String src) {
        return new EhrResourceListItem(
                r.getResourceType(),
                r.getResourceFhirId(),
                EhrResourceCategory.categoryFor(r.getResourceType()),
                r.getTitle(),
                r.getStatusValue(),
                r.getOccurredAt(),
                r.getLastSyncedAt() != null ? r.getLastSyncedAt().toString() : null,
                src);
    }

    /** Default to EPIC (the only live source) and normalize casing to the stored value. */
    private static String normalizeSource(final String source) {
        if (source == null || source.isBlank()) {
            return EpicProperties.SOURCE_EPIC;
        }
        return source.trim().toUpperCase(Locale.ROOT);
    }

    private static Comparator<EhrResourceListItem> comparatorFor(final String sort) {
        final Comparator<EhrResourceListItem> byOccurred =
                Comparator.comparing(it -> it.occurredAt() == null ? "" : it.occurredAt());
        final Comparator<EhrResourceListItem> byTitle =
                Comparator.comparing(it -> it.title() == null ? "" : it.title().toLowerCase(Locale.ROOT));
        switch (sort == null ? "latest" : sort.toLowerCase(Locale.ROOT)) {
            case "earliest":
                return byOccurred;
            case "az":
                return byTitle;
            case "za":
                return byTitle.reversed();
            case "latest":
            default:
                return byOccurred.reversed();
        }
    }

    private JsonNode parsePayload(final String json) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readTree(json);
        } catch (final Exception ignored) {
            return null;
        }
    }

    private static String parseName(final JsonNode patient) {
        if (patient == null) {
            return null;
        }
        final JsonNode names = patient.get("name");
        if (names == null || !names.isArray() || names.isEmpty()) {
            return null;
        }
        final JsonNode n = names.get(0);
        if (n.hasNonNull("text")) {
            return n.get("text").asText();
        }
        final StringBuilder sb = new StringBuilder();
        final JsonNode given = n.get("given");
        if (given != null && given.isArray()) {
            for (final JsonNode g : given) {
                if (sb.length() > 0) {
                    sb.append(' ');
                }
                sb.append(g.asText());
            }
        }
        if (n.hasNonNull("family")) {
            if (sb.length() > 0) {
                sb.append(' ');
            }
            sb.append(n.get("family").asText());
        }
        return sb.length() > 0 ? sb.toString() : null;
    }

    private static String textOf(final JsonNode node, final String field) {
        final JsonNode v = node == null ? null : node.get(field);
        return v != null && !v.isNull() ? v.asText() : null;
    }
}
