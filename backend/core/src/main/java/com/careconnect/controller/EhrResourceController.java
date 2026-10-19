package com.careconnect.controller;

import com.careconnect.config.EpicProperties;
import com.careconnect.dto.ehr.EhrResourceListItem;
import com.careconnect.model.User;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.ehr.EhrResourceRepository;
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

    private final SecurityUtil securityUtil;
    private final EhrResourceRepository resourceRepo;
    private final ObjectMapper objectMapper;

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
            @RequestParam(value = "sort", required = false, defaultValue = "latest") final String sort) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final String src = normalizeSource(source);
        final String qLower = (q == null || q.isBlank()) ? null : q.toLowerCase(Locale.ROOT);

        final List<EhrResourceListItem> items = resourceRepo.findByUserIdAndSource(me.getId(), src).stream()
                .filter(r -> !PATIENT_TYPE.equals(r.getResourceType()))
                .map(r -> toItem(r, src))
                .filter(it -> category == null || category.isBlank()
                        || category.equalsIgnoreCase(it.category()))
                .filter(it -> qLower == null
                        || (it.title() != null && it.title().toLowerCase(Locale.ROOT).contains(qLower))
                        || (it.resourceType() != null
                            && it.resourceType().toLowerCase(Locale.ROOT).contains(qLower)))
                .sorted(comparatorFor(sort))
                .collect(Collectors.toList());

        final Instant maxSynced = resourceRepo.findMaxLastSyncedAt(me.getId(), src);
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
            @RequestParam(value = "source", required = false) final String source) {
        final User me = securityUtil.resolveCurrentUser();
        if (me == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        final String src = normalizeSource(source);
        final Optional<EhrResource> patientRow = resourceRepo.findByUserIdAndSource(me.getId(), src).stream()
                .filter(r -> PATIENT_TYPE.equals(r.getResourceType()))
                .findFirst();
        if (patientRow.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        final JsonNode fhir = parsePayload(patientRow.get().getPayloadJson());
        final Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", parseName(fhir));
        body.put("birthDate", textOf(fhir, "birthDate"));
        body.put("gender", textOf(fhir, "gender"));
        body.put("source", src);
        return ResponseEntity.ok(body);
    }

    // --- helpers ---

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
