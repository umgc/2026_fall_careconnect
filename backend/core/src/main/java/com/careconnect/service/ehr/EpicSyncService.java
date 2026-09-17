package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.indexing.EpicFhirIndexedPayload;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.ai.indexing.chunker.EpicResourceChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CompletableFuture;

/**
 * Orchestrates the Epic read + mirror + index pass (Phases 1–2).
 *
 * <p>On connect it fetches the core clinical set, applies the {@link EhrStatusGate} (R3), upserts
 * each surviving resource into {@code ehr_resource} (provenance-tagged, never clobbering
 * self-entered rows), and emits {@code EPIC_FHIR_INDEXED} inside the same transaction (transactional
 * outbox) so the existing {@code IndexWorker} embeds them into {@code retrieval_index_chunk} with
 * {@code source_kind='epic'}. Ask AI then answers over Epic data automatically.
 *
 * <p>Gated on {@code careconnect.epic.enabled} (co-gated with {@link EpicFhirClient}).
 */
@Slf4j
@Service
@ConditionalOnProperty(name = "careconnect.epic.enabled", havingValue = "true")
public class EpicSyncService {

    /** Core clinical set fetched on connect (1_0 §5 #1–13, read-first). Typed fallback after {@code $everything}. */
    private static final List<String> SYNC_RESOURCE_TYPES = List.of(
            "AllergyIntolerance", "Condition", "MedicationRequest", "MedicationStatement",
            "Observation", "DiagnosticReport", "Immunization", "Procedure", "DocumentReference");

    /** Demographics resource, mirrored via a direct read (not a patient search). */
    private static final String PATIENT_TYPE = "Patient";

    /** Types we mirror out of the {@code $everything} bundle (clinical set + demographics); everything else (Practitioner, Organization, …) is ignored. */
    private static final Set<String> MIRRORABLE_TYPES;
    static {
        final var m = new java.util.HashSet<>(SYNC_RESOURCE_TYPES);
        m.add(PATIENT_TYPE);
        MIRRORABLE_TYPES = Set.copyOf(m);
    }

    /**
     * Per-type required search parameters. Epic R4 rejects a bare {@code ?patient=} search for some
     * types with HTTP 400 ("required search parameter missing"); each entry is a list of parameter
     * sets and we issue one fetch per set, merging (deduped by fhir id). {@code Observation} requires
     * a {@code category} (or {@code code}) — we sweep the standard US Core categories. Types absent
     * here are fetched patient-only (a single empty set).
     *
     * <p>NOTE: if a type still 400s in your Epic environment, {@code GET /api/epic/resync} returns
     * Epic's exact {@code responseBody} naming the missing parameter — add the fix here.
     */
    private static final Map<String, List<Map<String, String>>> REQUIRED_SEARCH_PARAMS = Map.of(
            "Observation", List.of(
                    Map.of("category", "laboratory"),
                    Map.of("category", "vital-signs"),
                    Map.of("category", "social-history"),
                    Map.of("category", "core-characteristics")));

    /** The param sets to try for a type: its required-param sweep, or a single patient-only search. */
    private static List<Map<String, String>> searchParamSets(final String resourceType) {
        return REQUIRED_SEARCH_PARAMS.getOrDefault(resourceType, List.of(Map.of()));
    }

    private final EpicFhirClient fhirClient;
    private final EhrResourceRepository resourceRepo;
    private final EhrStatusGate statusGate;
    private final EpicResourceChunker chunker;
    private final IndexingEventEmitter eventEmitter;
    private final RetrievalIndexService retrievalIndexService;
    private final EhrAuditService audit;
    private final ObjectMapper objectMapper;
    private final ObjectProvider<EpicSyncService> selfProvider;
    private final EpicOAuthService oauth;

    public EpicSyncService(EpicFhirClient fhirClient,
                           EhrResourceRepository resourceRepo,
                           EhrStatusGate statusGate,
                           EpicResourceChunker chunker,
                           IndexingEventEmitter eventEmitter,
                           RetrievalIndexService retrievalIndexService,
                           EhrAuditService audit,
                           ObjectMapper objectMapper,
                           ObjectProvider<EpicSyncService> selfProvider,
                           EpicOAuthService oauth) {
        this.fhirClient = fhirClient;
        this.resourceRepo = resourceRepo;
        this.statusGate = statusGate;
        this.chunker = chunker;
        this.eventEmitter = eventEmitter;
        this.retrievalIndexService = retrievalIndexService;
        this.audit = audit;
        this.objectMapper = objectMapper;
        this.selfProvider = selfProvider;
        this.oauth = oauth;
    }

    /**
     * Kick off the initial sync off the request thread (the OAuth callback returns immediately).
     * Routes through the Spring proxy so {@link #syncNow(Long)} runs in its own transaction.
     */
    public void enqueueInitialSync(final Long userId) {
        CompletableFuture.runAsync(() -> {
            try {
                selfProvider.getObject().syncNow(userId);
            } catch (RuntimeException ex) {
                log.warn("Epic initial sync failed for user {}: {}", userId, ex.getClass().getSimpleName());
                audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_SYNC", EhrResourceOutcome.ERROR);
            }
        });
    }

    /**
     * Fetch → status-gate → mirror → emit index events. NOT wrapped in a single transaction:
     * each resource is persisted in its own transaction (see {@link #upsertAndEmit}) so one bad row
     * (e.g. a column-constraint violation) rolls back only that resource instead of marking the
     * whole sync rollback-only and aborting every import.
     */
    public int syncNow(final Long userId) {
        // Epic grants only the scopes enabled on the app registration, which can be a subset of
        // what we request. Attempting a resource type whose read scope was not granted returns a
        // guaranteed 403; skip those. And a failure on any single type (403 or transient) must not
        // abort the whole sync, so each fetch is isolated — permitted types still import.
        final Set<String> grantedScopes = oauth.findCredential(userId)
                .map(c -> parseScopes(c.getScopes()))
                .orElseGet(Set::of);

        // Dedupe across the $everything pass and the typed fallback: "<type>|<fhirId>".
        final Set<String> seen = new java.util.HashSet<>();
        final int[] tally = new int[2]; // [0] stored, [1] failed

        // 1) PRIMARY — Patient/$everything: demographics + all compartment resources in one call.
        // Sidesteps the per-type required-param quirks (below) and the demographics gap. Optional in
        // some Epic environments (may 404/501 or be capped), so a failure is non-fatal: the typed
        // fallback carries the sync.
        try {
            final List<JsonNode> everything = new java.util.ArrayList<>();
            EpicFhirClient.extractEntries(fhirClient.everything(userId), everything);
            for (final JsonNode resource : everything) {
                final String type = resourceTypeOf(resource);
                if (type == null || !MIRRORABLE_TYPES.contains(type)) {
                    continue; // OperationOutcome, Practitioner, Organization, … — not mirrored.
                }
                mirror(userId, type, resource, seen, tally);
            }
        } catch (final RuntimeException ex) {
            log.info("Epic $everything unavailable for user {}, falling back to typed fetch: {}",
                    userId, ex.getClass().getSimpleName());
        }

        int skipped = 0;

        // 1b) Demographics as an explicit read if $everything did not already supply the Patient.
        if (!seenType(seen, PATIENT_TYPE)
                && (grantedScopes.isEmpty() || grantedScopes.contains("patient/Patient.read"))) {
            try {
                final String patientId = oauth.patientFhirId(userId);
                if (patientId != null && !patientId.isBlank()) {
                    for (final JsonNode resource : fhirClient.read(userId, PATIENT_TYPE, patientId)) {
                        mirror(userId, PATIENT_TYPE, resource, seen, tally);
                    }
                }
            } catch (final RuntimeException ex) {
                skipped++;
                log.warn("Epic Patient read failed for user {}: {}", userId, ex.getClass().getSimpleName());
            }
        }

        // 2) FALLBACK — typed per-type fetch for anything $everything did not already mirror.
        for (final String resourceType : SYNC_RESOURCE_TYPES) {
            if (!grantedScopes.isEmpty()
                    && !grantedScopes.contains("patient/" + resourceType + ".read")) {
                skipped++;
                log.debug("Epic sync skipping {} for user {} (scope not granted)", resourceType, userId);
                continue;
            }
            try {
                // One fetch per required-param set (Observation sweeps categories; most types get a
                // single patient-only search). Epic 400s a bare Observation search, hence the sweep.
                for (final Map<String, String> params : searchParamSets(resourceType)) {
                    for (final JsonNode resource : fhirClient.fetch(userId, resourceType, params)) {
                        mirror(userId, resourceType, resource, seen, tally);
                    }
                }
            } catch (final RuntimeException ex) {
                skipped++;
                log.warn("Epic sync skipped resource type {} for user {}: {}",
                        resourceType, userId, ex.getClass().getSimpleName());
            }
        }

        final int stored = tally[0];
        final int failed = tally[1];
        audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_SYNC", null,
                String.valueOf(stored), EhrResourceOutcome.OK);
        log.info("Epic sync stored/updated {} resources for user {} ({} resource types skipped, "
                + "{} individual resources failed)", stored, userId, skipped, failed);
        return stored;
    }

    /**
     * Status-gate, dedupe, and mirror one fetched resource in its own transaction, updating the
     * {@code tally} ([0]=stored, [1]=failed). Skips (silently) any entry whose {@code resourceType}
     * does not match {@code expectedType} — this drops the informational {@code OperationOutcome}
     * Epic includes in search bundles (and any {@code _include}d resource), which otherwise slips
     * through with no {@code id} and stores nothing while masking the real result.
     */
    private void mirror(final Long userId, final String expectedType, final JsonNode resource,
                        final Set<String> seen, final int[] tally) {
        final String actualType = resourceTypeOf(resource);
        if (actualType == null || !actualType.equals(expectedType)) {
            return;
        }
        final String fhirId = resource.hasNonNull("id") ? resource.get("id").asText() : null;
        if (fhirId == null || fhirId.isBlank()) {
            return;
        }
        if (!seen.add(actualType + "|" + fhirId)) {
            return; // already mirrored this run (e.g. from $everything, or a category overlap).
        }
        if (!statusGate.isAllowed(resource)) {
            return;
        }
        try {
            // Persist each resource in its OWN transaction (routed through the Spring proxy) so a
            // single failing row does not poison the whole sync.
            if (selfProvider.getObject().upsertAndEmit(userId, actualType, resource)) {
                tally[0]++;
            }
        } catch (final RuntimeException ex) {
            tally[1]++;
            log.warn("Epic sync skipped one {} resource for user {}: {}",
                    actualType, userId, ex.getClass().getSimpleName());
        }
    }

    private static String resourceTypeOf(final JsonNode resource) {
        return resource != null && resource.hasNonNull("resourceType")
                ? resource.get("resourceType").asText() : null;
    }

    /** True if any resource of {@code type} was already mirrored this run. */
    private static boolean seenType(final Set<String> seen, final String type) {
        final String prefix = type + "|";
        for (final String key : seen) {
            if (key.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    /** Split the space-delimited SMART scope string into a set for membership checks. */
    private static Set<String> parseScopes(final String scopes) {
        if (scopes == null || scopes.isBlank()) {
            return Set.of();
        }
        return java.util.Arrays.stream(scopes.trim().split("\\s+"))
                .collect(java.util.stream.Collectors.toUnmodifiableSet());
    }

    /**
     * Upsert one resource and emit its index event, atomically in its OWN transaction (public +
     * {@code @Transactional}, invoked through the Spring proxy from {@link #syncNow}). Isolating each
     * resource means a constraint violation on one row rolls back only that row — the surrounding
     * sync loop catches the exception and continues with the next resource.
     */
    @Transactional
    public boolean upsertAndEmit(final Long userId, final String resourceType, final JsonNode resource) {
        final String fhirId = resource.hasNonNull("id") ? resource.get("id").asText() : null;
        if (fhirId == null || fhirId.isBlank()) {
            return false;
        }
        final String canonical = canonicalJson(resource);
        final String contentHash = ContentHashUtil.sha256(canonical);

        final EhrResource entity = resourceRepo
                .findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                        userId, EpicProperties.SOURCE_EPIC, resourceType, fhirId)
                .orElseGet(EhrResource::new);
        entity.setUserId(userId);
        entity.setSource(EpicProperties.SOURCE_EPIC);
        entity.setResourceType(resourceType);
        entity.setResourceFhirId(fhirId);
        entity.setStatusValue(statusGate.statusOf(resource));
        entity.setTitle(buildTitle(resourceType, resource));
        entity.setOccurredAt(occurredAt(resource));
        entity.setContentHash(contentHash);
        entity.setPayloadJson(canonical);
        final EhrResource saved = resourceRepo.save(entity);

        // Only emit for resource types the chunker can index (skip Patient/Practitioner, etc.).
        if (EpicResourceChunker.recordTypeFor(resourceType).isPresent()) {
            eventEmitter.emitEpicFhirIndexed(new EpicFhirIndexedPayload(
                    saved.getId(), userId, contentHash, null));
        }
        return true;
    }

    /**
     * De-index and delete all Epic-origin data for a user (Disconnect). Removes chunks first
     * (via the source-replacement lock) then the mirror rows.
     *
     * @return number of chunk sources removed
     */
    @Transactional
    public int removeEpicData(final Long userId) {
        int removed = 0;
        final List<EhrResource> rows = resourceRepo.findByUserIdAndSource(userId, EpicProperties.SOURCE_EPIC);
        for (final EhrResource row : rows) {
            final Optional<RetrievalRecordType> recordType =
                    EpicResourceChunker.recordTypeFor(row.getResourceType());
            if (recordType.isPresent()) {
                retrievalIndexService.removeIndexedSource(
                        userId, "epic-" + row.getResourceFhirId(), recordType.get());
                removed++;
            }
        }
        resourceRepo.deleteByUserIdAndSource(userId, EpicProperties.SOURCE_EPIC);
        audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_PURGE", null,
                String.valueOf(removed), EhrResourceOutcome.OK);
        return removed;
    }

    private String canonicalJson(final JsonNode resource) {
        try {
            return objectMapper.writeValueAsString(resource);
        } catch (final Exception e) {
            return resource.toString();
        }
    }

    private static String buildTitle(final String resourceType, final JsonNode resource) {
        final String label = textOf(resource.get("code"));
        final String med = textOf(resource.get("medicationCodeableConcept"));
        final String best = med != null ? med : label;
        return best != null ? resourceType + ": " + best : resourceType;
    }

    private static String textOf(final JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        if (node.hasNonNull("text")) {
            return node.get("text").asText();
        }
        final JsonNode coding = node.get("coding");
        if (coding != null && coding.isArray() && !coding.isEmpty() && coding.get(0).hasNonNull("display")) {
            return coding.get(0).get("display").asText();
        }
        return null;
    }

    private static String occurredAt(final JsonNode resource) {
        for (final String field : new String[]{
                "effectiveDateTime", "onsetDateTime", "authoredOn", "recordedDate", "date", "issued"}) {
            final JsonNode v = resource.get(field);
            if (v != null && v.isTextual()) {
                return v.asText();
            }
        }
        return null;
    }

    /** Outcome constants (kept local to avoid importing the entity into the hot path). */
    private static final class EhrResourceOutcome {
        static final String OK = "OK";
        static final String ERROR = "ERROR";
    }
}
