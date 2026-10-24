package com.careconnect.service.ehr;

import com.careconnect.config.OracleProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Set;

/**
 * Source-agnostic projector that mirrors stored {@code ehr_raw_payload} rows into the
 * {@code ehr_resource} read model (WBS 5.2.86 Phase B / "Option B"). This is the one piece that
 * makes a source appear on the Unified Health screen: Epic and athenahealth dual-write the mirror
 * at ingest time, but Oracle Health (Cerner) and Medicare only write raw payloads, so their records
 * never surface through the {@code ?source=ALL} union read ({@link EhrResourceController}) until a
 * mirror row exists. This projector closes that gap for both of them with one component, reading the
 * shared raw-payload table — no dependency on Team C's Cerner adapter and no vendor credentials.
 *
 * <p>Deliberately scoped to the sources that are NOT natively mirrored ({@link #MIRRORABLE_SOURCES}
 * = Oracle Health + Medicare) so it never double-writes Epic/athenahealth rows. The mirror-row
 * shaping (title / occurredAt / status / content-hash / dedup upsert) mirrors
 * {@code EpicSyncService.upsertAndEmit}; the derivation helpers are duplicated here rather than
 * extracted so the Epic ingest path stays byte-identical.
 */
@Slf4j
@Service
public class EhrMirrorProjector {

    /** Sources whose records reach the mirror only through this projector (never Epic/athenahealth). */
    private static final Set<String> MIRRORABLE_SOURCES = Set.of(
            OracleProperties.SOURCE_ORACLE, MedicareProperties.SOURCE_MEDICARE);

    private static final String PATIENT_TYPE = "Patient";

    private final EhrResourceRepository resourceRepo;
    private final EhrRawPayloadRepository rawPayloadRepo;
    private final EhrSourceRepository sourceRepo;
    private final PatientRepository patientRepository;
    private final EhrStatusGate statusGate;
    private final ObjectMapper objectMapper;

    public EhrMirrorProjector(final EhrResourceRepository resourceRepo,
                              final EhrRawPayloadRepository rawPayloadRepo,
                              final EhrSourceRepository sourceRepo,
                              final PatientRepository patientRepository,
                              final EhrStatusGate statusGate,
                              final ObjectMapper objectMapper) {
        this.resourceRepo = resourceRepo;
        this.rawPayloadRepo = rawPayloadRepo;
        this.sourceRepo = sourceRepo;
        this.patientRepository = patientRepository;
        this.statusGate = statusGate;
        this.objectMapper = objectMapper;
    }

    /**
     * Project every mirrorable source's raw payloads for one user into {@code ehr_resource}.
     *
     * @return number of mirror rows written/updated across all mirrorable sources
     */
    @Transactional
    public int projectForUser(final Long userId) {
        final Patient patient = patientRepository.findByUserId(userId).orElse(null);
        if (patient == null) {
            log.warn("Mirror projection skipped: no patient row for user {}", userId);
            return 0;
        }
        int total = 0;
        for (final String sourceCode : MIRRORABLE_SOURCES) {
            total += projectForSource(userId, patient.getId(), sourceCode);
        }
        return total;
    }

    /**
     * Project all raw payloads of one source for one (user, patient) into {@code ehr_resource}.
     * Idempotent: a row whose content hash is unchanged is left untouched.
     *
     * @return number of mirror rows written/updated for this source
     */
    @Transactional
    public int projectForSource(final Long userId, final Long patientId, final String sourceCode) {
        if (!MIRRORABLE_SOURCES.contains(sourceCode)) {
            // Guard: Epic/athenahealth already dual-write the mirror; never project them here.
            return 0;
        }
        final Long sourceId = sourceRepo.findByCode(sourceCode).map(EhrSource::getId).orElse(null);
        if (sourceId == null) {
            log.warn("Mirror projection skipped: source {} not in catalog", sourceCode);
            return 0;
        }
        final List<EhrRawPayload> rows =
                rawPayloadRepo.findByPatientIdAndSourceIdOrderByRetrievedAtDesc(patientId, sourceId);
        int written = 0;
        for (final EhrRawPayload raw : rows) {
            if (project(userId, patientId, sourceCode, raw)) {
                written++;
            }
        }
        log.info("Mirror projection: {} ehr_resource row(s) written/updated for user {} source {}",
                written, userId, sourceCode);
        return written;
    }

    /** Mirror one raw payload into its {@code ehr_resource} row. Returns true when a row was saved. */
    private boolean project(final Long userId, final Long patientId,
                            final String sourceCode, final EhrRawPayload raw) {
        final JsonNode resource = parse(raw.getPayload());
        if (resource == null) {
            return false;
        }
        final String resourceType = raw.getResourceType() != null
                ? raw.getResourceType() : resourceTypeOf(resource);
        if (resourceType == null) {
            return false;
        }
        if (!statusGate.isAllowed(resource)) {
            return false; // cancelled / entered-in-error / draft — not mirrored.
        }
        final String fhirId = raw.getExternalResourceId() != null && !raw.getExternalResourceId().isBlank()
                ? raw.getExternalResourceId()
                : (resource.hasNonNull("id") ? resource.get("id").asText() : null);
        if (fhirId == null || fhirId.isBlank()) {
            return false;
        }
        final String canonical = canonicalJson(resource);
        final String contentHash = ContentHashUtil.sha256(canonical);

        final EhrResource entity = resourceRepo
                .findByUserIdAndSourceAndResourceTypeAndResourceFhirId(userId, sourceCode, resourceType, fhirId)
                .orElseGet(EhrResource::new);
        // Idempotent: an existing row with the same content hash needs no rewrite.
        if (entity.getId() != null && contentHash != null && contentHash.equals(entity.getContentHash())) {
            return false;
        }
        entity.setUserId(userId);
        entity.setPatientId(patientId);
        entity.setSource(sourceCode);
        entity.setResourceType(resourceType);
        entity.setResourceFhirId(fhirId);
        entity.setStatusValue(statusGate.statusOf(resource));
        entity.setTitle(buildTitle(resourceType, resource));
        entity.setOccurredAt(occurredAt(resource));
        entity.setContentHash(contentHash);
        entity.setPayloadJson(canonical);
        resourceRepo.save(entity);
        return true;
    }

    private JsonNode parse(final String json) {
        if (json == null || json.isBlank()) {
            return null;
        }
        try {
            return objectMapper.readTree(json);
        } catch (final Exception ex) {
            log.warn("Mirror projection could not parse a raw payload: {}", ex.getClass().getSimpleName());
            return null;
        }
    }

    private String canonicalJson(final JsonNode resource) {
        try {
            return objectMapper.writeValueAsString(resource);
        } catch (final Exception ex) {
            return resource.toString();
        }
    }

    private static String resourceTypeOf(final JsonNode resource) {
        return resource != null && resource.hasNonNull("resourceType")
                ? resource.get("resourceType").asText() : null;
    }

    // --- Mirror-row field derivation (parity with EpicSyncService.buildTitle / occurredAt) ---

    private static String buildTitle(final String resourceType, final JsonNode resource) {
        final String med = textOf(resource.get("medicationCodeableConcept"));
        final String label = textOf(resource.get("code"));
        final String named = stringOf(resource.get("title")) != null
                ? stringOf(resource.get("title")) : stringOf(resource.get("name"));
        final String described = textOf(resource.get("description"));
        final String relationship = textOf(resource.get("relationship"));
        final String visit = textOf(resource.get("type")) != null
                ? textOf(resource.get("type")) : textOf(resource.get("class"));
        final String best = firstNonNull(med, label, named, described, relationship, visit);
        return best != null ? resourceType + ": " + best : resourceType;
    }

    private static String occurredAt(final JsonNode resource) {
        for (final String field : new String[]{
                "effectiveDateTime", "onsetDateTime", "authoredOn", "recordedDate", "date", "issued",
                "startDate", "created"}) {
            final JsonNode v = resource.get(field);
            if (v != null && v.isTextual()) {
                return v.asText();
            }
        }
        final JsonNode period = resource.get("period");
        if (period != null && period.hasNonNull("start")) {
            return period.get("start").asText();
        }
        return null;
    }

    private static String stringOf(final JsonNode node) {
        return node != null && node.isTextual() && !node.asText().isBlank() ? node.asText() : null;
    }

    @SafeVarargs
    private static <T> T firstNonNull(final T... values) {
        for (final T v : values) {
            if (v != null) {
                return v;
            }
        }
        return null;
    }

    private static String textOf(final JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        final JsonNode target = node.isArray() ? (node.isEmpty() ? null : node.get(0)) : node;
        if (target == null || target.isNull()) {
            return null;
        }
        if (target.hasNonNull("text")) {
            return target.get("text").asText();
        }
        final JsonNode coding = target.get("coding");
        if (coding != null && coding.isArray() && !coding.isEmpty() && coding.get(0).hasNonNull("display")) {
            return coding.get(0).get("display").asText();
        }
        if (target.hasNonNull("display")) {
            return target.get("display").asText();
        }
        return null;
    }
}
