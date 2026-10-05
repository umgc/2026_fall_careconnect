package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.indexing.EpicFhirIndexedPayload;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.ai.indexing.chunker.EpicResourceChunker;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
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
            "Observation", "DiagnosticReport", "Immunization", "Procedure", "DocumentReference",
            "Encounter",
            // Care-planning + longitudinal context (US Core). Patient-only search except where a
            // required param is listed in REQUIRED_SEARCH_PARAMS below.
            "CarePlan", "Goal", "CareTeam", "FamilyMemberHistory", "Coverage", "Device");

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
                    Map.of("category", "core-characteristics")),
            // US Core CarePlan search requires a category; "assess-plan" is the US Core value.
            "CarePlan", List.of(Map.of("category", "assess-plan")));

    /** The param sets to try for a type: its required-param sweep, or a single patient-only search. */
    private static List<Map<String, String>> searchParamSets(final String resourceType) {
        return REQUIRED_SEARCH_PARAMS.getOrDefault(resourceType, List.of(Map.of()));
    }

    /**
     * Return {@code base} with a {@code _lastUpdated} filter added (DELTA mode), or {@code base}
     * unchanged when {@code lastUpdatedFilter} is null (FULL mode). Never mutates the shared,
     * immutable param maps declared in {@link #REQUIRED_SEARCH_PARAMS}.
     */
    private static Map<String, String> withLastUpdated(final Map<String, String> base,
                                                       final String lastUpdatedFilter) {
        if (lastUpdatedFilter == null) {
            return base;
        }
        final Map<String, String> merged = new java.util.LinkedHashMap<>(base);
        merged.put("_lastUpdated", lastUpdatedFilter);
        return merged;
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
    private final EpicProperties epicProperties;
    // Canonical dual-write (Team E brief S2/S3): crosswalk + raw payload, keyed on the canonical
    // patient_id resolved from the connecting user. FK-backed, so a wrong id is rejected.
    private final PatientRepository patientRepository;
    private final EhrSourceResolver sourceResolver;
    private final EhrPatientCrosswalkRepository crosswalkRepo;
    private final EhrRawPayloadRepository rawPayloadRepo;

    public EpicSyncService(EpicFhirClient fhirClient,
                           EhrResourceRepository resourceRepo,
                           EhrStatusGate statusGate,
                           EpicResourceChunker chunker,
                           IndexingEventEmitter eventEmitter,
                           RetrievalIndexService retrievalIndexService,
                           EhrAuditService audit,
                           ObjectMapper objectMapper,
                           ObjectProvider<EpicSyncService> selfProvider,
                           EpicOAuthService oauth,
                           EpicProperties epicProperties,
                           PatientRepository patientRepository,
                           EhrSourceResolver sourceResolver,
                           EhrPatientCrosswalkRepository crosswalkRepo,
                           EhrRawPayloadRepository rawPayloadRepo) {
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
        this.epicProperties = epicProperties;
        this.patientRepository = patientRepository;
        this.sourceResolver = sourceResolver;
        this.crosswalkRepo = crosswalkRepo;
        this.rawPayloadRepo = rawPayloadRepo;
    }

    /** How much of the patient record a sync pass pulls. */
    public enum SyncMode {
        /** Full import: {@code $everything} + demographics read + the typed per-type sweep. */
        FULL,
        /**
         * Incremental: typed sweep only, filtered with {@code _lastUpdated=gt<watermark>} so Epic
         * returns just the resources changed since the last sync. Falls back to {@link #FULL} when
         * no prior sync watermark exists.
         */
        DELTA
    }

    /**
     * Kick off the initial sync off the request thread (the OAuth callback returns immediately).
     * Routes through the Spring proxy so {@link #syncNow(Long)} runs in its own transaction. The
     * first connect is always a {@link SyncMode#FULL} import.
     */
    public void enqueueInitialSync(final Long userId) {
        CompletableFuture.runAsync(() -> {
            try {
                selfProvider.getObject().syncNow(userId, SyncMode.FULL);
            } catch (RuntimeException ex) {
                log.warn("Epic initial sync failed for user {}: {}", userId, ex.getClass().getSimpleName());
                audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_SYNC", EhrResourceOutcome.ERROR);
            }
        });
    }

    /** Full sync (back-compat entry point). */
    public int syncNow(final Long userId) {
        return syncNow(userId, SyncMode.FULL);
    }

    /**
     * Fetch → status-gate → mirror → emit index events. NOT wrapped in a single transaction:
     * each resource is persisted in its own transaction (see {@link #upsertAndEmit}) so one bad row
     * (e.g. a column-constraint violation) rolls back only that resource instead of marking the
     * whole sync rollback-only and aborting every import.
     *
     * <p>In {@link SyncMode#DELTA} the {@code $everything} pass and the demographics read are
     * skipped and each typed search carries {@code _lastUpdated=gt<watermark>}, so only resources
     * changed since the last sync are fetched (the {@code contentHash} guard in {@link #upsertAndEmit}
     * already no-ops unchanged rows). With no prior watermark, DELTA degrades to a FULL import.
     */
    public int syncNow(final Long userId, final SyncMode mode) {
        // Resolve the effective mode: DELTA needs a watermark (the newest last_synced_at we hold for
        // this user's Epic rows). Without one there is nothing to be incremental against, so do FULL.
        final Instant watermark = mode == SyncMode.DELTA
                ? resourceRepo.findMaxLastSyncedAt(userId, EpicProperties.SOURCE_EPIC)
                : null;
        final SyncMode effectiveMode = (mode == SyncMode.DELTA && watermark != null)
                ? SyncMode.DELTA : SyncMode.FULL;
        // Back-date the cursor by a safety margin to absorb clock skew between our clock and Epic's
        // resource meta.lastUpdated (a re-fetch of a few unchanged rows is cheap; a miss is not).
        final String lastUpdatedFilter = effectiveMode == SyncMode.DELTA
                ? "gt" + DateTimeFormatter.ISO_INSTANT.format(
                        watermark.minus(epicProperties.getDeltaSafetyMargin()))
                : null;
        log.info("Epic sync mode={} (requested={}) for user {}{}", effectiveMode, mode, userId,
                lastUpdatedFilter != null ? " since " + lastUpdatedFilter : "");

        // Canonical dual-write targets (Team E brief S2/S3), resolved once per sync. Null when the
        // user has no patient row (e.g. a caregiver) or the EPIC source is unseeded — the canonical
        // writes (crosswalk + raw payload) are then skipped and only the interim ehr_resource mirror
        // is written, so Ask AI still works and nothing in the existing flow breaks.
        final Long patientId = patientRepository.findByUserId(userId).map(Patient::getId).orElse(null);
        final Long sourceId = sourceResolver.idForCode(EpicProperties.SOURCE_EPIC);
        if (patientId == null || sourceId == null) {
            log.warn("Epic canonical dual-write disabled for user {} (patientId={}, sourceId={}); "
                    + "writing interim ehr_resource only", userId, patientId, sourceId);
        } else {
            // Self-heal the crosswalk each sync (idempotent); the primary write is on connect.
            upsertCrosswalk(patientId, sourceId, oauth.patientFhirId(userId));
        }

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
        // fallback carries the sync. Skipped in DELTA (it has no _lastUpdated filter and would refetch
        // the whole compartment).
        if (effectiveMode == SyncMode.FULL) {
            try {
                for (final JsonNode resource : fhirClient.everything(userId)) {
                    final String type = resourceTypeOf(resource);
                    if (type == null || !MIRRORABLE_TYPES.contains(type)) {
                        continue; // OperationOutcome, Practitioner, Organization, … — not mirrored.
                    }
                    mirror(userId, patientId, sourceId, type, resource, seen, tally);
                }
            } catch (final RuntimeException ex) {
                log.info("Epic $everything unavailable for user {}, falling back to typed fetch: {}",
                        userId, ex.getClass().getSimpleName());
            }
        }

        int skipped = 0;

        // 1b) Demographics as an explicit read if $everything did not already supply the Patient.
        // Skipped in DELTA — demographics rarely change and there is no cheap changed-since read.
        if (effectiveMode == SyncMode.FULL
                && !seenType(seen, PATIENT_TYPE)
                && (grantedScopes.isEmpty() || grantedScopes.contains("patient/Patient.read"))) {
            try {
                final String patientFhirId = oauth.patientFhirId(userId);
                if (patientFhirId != null && !patientFhirId.isBlank()) {
                    for (final JsonNode resource : fhirClient.read(userId, PATIENT_TYPE, patientFhirId)) {
                        mirror(userId, patientId, sourceId, PATIENT_TYPE, resource, seen, tally);
                    }
                }
            } catch (final RuntimeException ex) {
                skipped++;
                log.warn("Epic Patient read failed for user {}: {}", userId, ex.getClass().getSimpleName());
            }
        }

        // 2) FALLBACK — typed per-type fetch for anything $everything did not already mirror (and the
        // sole fetch path in DELTA, where each search is filtered by _lastUpdated).
        for (final String resourceType : SYNC_RESOURCE_TYPES) {
            if (!grantedScopes.isEmpty()
                    && !grantedScopes.contains("patient/" + resourceType + ".read")) {
                skipped++;
                log.debug("Epic sync skipping {} for user {} (scope not granted)", resourceType, userId);
                continue;
            }
            // One fetch per required-param set (Observation sweeps categories; most types get a
            // single patient-only search). Each param set is isolated: Epic rejects a category the
            // app isn't authorized for with a 400 ("not valid for any authorized sub-resource"), and
            // that must not abort the remaining categories/types.
            for (final Map<String, String> baseParams : searchParamSets(resourceType)) {
                final Map<String, String> params = withLastUpdated(baseParams, lastUpdatedFilter);
                try {
                    for (final JsonNode resource : fhirClient.fetch(userId, resourceType, params)) {
                        mirror(userId, patientId, sourceId, resourceType, resource, seen, tally);
                    }
                } catch (final RuntimeException ex) {
                    skipped++;
                    log.warn("Epic sync skipped {} params={} for user {}: {}",
                            resourceType, params, userId, ex.getClass().getSimpleName());
                }
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
    private void mirror(final Long userId, final Long patientId, final Long sourceId,
                        final String expectedType, final JsonNode resource,
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
            if (selfProvider.getObject().upsertAndEmit(userId, patientId, sourceId, actualType, resource)) {
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
    public boolean upsertAndEmit(final Long userId, final Long patientId, final Long sourceId,
                                 final String resourceType, final JsonNode resource) {
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
        // Additive canonical key (Q1): derive patient_id from the same user_id resolution so the two
        // cannot disagree. Null for a user with no patient row; user_id stays the dedup/scope key.
        entity.setPatientId(patientId);
        entity.setSource(EpicProperties.SOURCE_EPIC);
        entity.setResourceType(resourceType);
        entity.setResourceFhirId(fhirId);
        entity.setStatusValue(statusGate.statusOf(resource));
        entity.setTitle(buildTitle(resourceType, resource));
        entity.setOccurredAt(occurredAt(resource));
        entity.setContentHash(contentHash);
        entity.setPayloadJson(canonical);
        final EhrResource saved = resourceRepo.save(entity);

        // Canonical raw-payload store (Team E brief S3): one row per resource fetched, written in
        // the same per-resource transaction so it shares the fail-isolation. Skipped when the
        // canonical ids could not be resolved (see syncNow).
        if (patientId != null && sourceId != null) {
            writeRawPayload(patientId, sourceId, resourceType, fhirId, resource);
        }

        // Only emit for resource types the chunker can index (skip Patient/Practitioner, etc.).
        if (EpicResourceChunker.recordTypeFor(resourceType).isPresent()) {
            eventEmitter.emitEpicFhirIndexed(new EpicFhirIndexedPayload(
                    saved.getId(), userId, contentHash, null));
        }
        return true;
    }

    /**
     * Append the verbatim FHIR body to {@code ehr_raw_payload} (Team E brief S3). Inline binary
     * ({@code Patient.photo}) is stripped first and {@code photo_stripped} set so the row stays
     * honest about not being byte-identical; {@code payload_size_bytes} is left to {@code @PrePersist}.
     * The payload is handed to the {@code @JdbcTypeCode(JSON)} column as JSON text, never a Map and
     * never double-encoded.
     */
    private void writeRawPayload(final Long patientId, final Long sourceId,
                                 final String resourceType, final String fhirId,
                                 final JsonNode resource) {
        JsonNode body = resource;
        boolean photoStripped = false;
        if (resource.hasNonNull("photo") && resource instanceof ObjectNode) {
            final ObjectNode copy = ((ObjectNode) resource).deepCopy();
            copy.remove("photo");
            body = copy;
            photoStripped = true;
        }
        rawPayloadRepo.save(EhrRawPayload.builder()
                .patientId(patientId)
                .sourceId(sourceId)
                .resourceType(resourceType)
                .externalResourceId(fhirId)
                .payload(canonicalJson(body))
                .photoStripped(photoStripped)
                .retrievedAt(OffsetDateTime.now())
                .build());
    }

    /**
     * Link the connecting user's CareConnect patient to their external Epic {@code Patient.id}
     * (Team E brief S2). Resolves the canonical ids and upserts {@code ehr_patient_crosswalk}.
     * Called on connect from the OAuth callback; idempotent, so a re-sync re-affirms it.
     */
    public void linkPatientCrosswalk(final Long userId, final String externalPatientId) {
        final Long patientId = patientRepository.findByUserId(userId).map(Patient::getId).orElse(null);
        final Long sourceId = sourceResolver.idForCode(EpicProperties.SOURCE_EPIC);
        upsertCrosswalk(patientId, sourceId, externalPatientId);
    }

    /**
     * Upsert one {@code (patient_id, source_id) -> external_patient_id} crosswalk row, honoring both
     * unique constraints. A conflicting external id for an existing link is left in place and logged
     * rather than overwritten — that is a schema conversation for Team E, not a connector workaround
     * (brief S2). Fail-soft: a unique-constraint violation (external id already claimed by another
     * patient) is logged, never thrown.
     */
    private void upsertCrosswalk(final Long patientId, final Long sourceId,
                                 final String externalPatientId) {
        if (patientId == null || sourceId == null
                || externalPatientId == null || externalPatientId.isBlank()) {
            return;
        }
        try {
            final Optional<EhrPatientCrosswalk> existing =
                    crosswalkRepo.findByPatientIdAndSourceId(patientId, sourceId);
            if (existing.isPresent()) {
                if (!externalPatientId.equals(existing.get().getExternalPatientId())) {
                    log.warn("Epic crosswalk conflict for patient {} source {}: existing external id "
                            + "differs from incoming — leaving existing in place (raise with Team E)",
                            patientId, sourceId);
                }
                return;
            }
            crosswalkRepo.save(EhrPatientCrosswalk.builder()
                    .patientId(patientId)
                    .sourceId(sourceId)
                    .externalPatientId(externalPatientId)
                    .build());
        } catch (final RuntimeException ex) {
            // e.g. uq_ehr_crosswalk_source_external: this external id already maps to another patient.
            log.warn("Epic crosswalk upsert failed for patient {} source {}: {}",
                    patientId, sourceId, ex.getClass().getSimpleName());
        }
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

        // Canonical cleanup on disconnect (EPIC Status.md §2 / Q2; Cononical_0 v1.2 §7): also delete
        // the raw-payload history and the patient crosswalk for this (patient_id, source_id) so no
        // canonical rows are orphaned on unlink. Scoped to the EPIC source id, so other connectors'
        // rows are untouched. Fail-soft on an unresolved patient/source — the interim mirror is
        // already gone, and a missing canonical id just means there was nothing canonical to clean.
        final Long patientId = patientRepository.findByUserId(userId).map(Patient::getId).orElse(null);
        final Long sourceId = sourceResolver.idForCode(EpicProperties.SOURCE_EPIC);
        if (patientId != null && sourceId != null) {
            final int rawDeleted = rawPayloadRepo.deleteByPatientIdAndSourceId(patientId, sourceId);
            final int crosswalkDeleted = crosswalkRepo.deleteByPatientIdAndSourceId(patientId, sourceId);
            log.info("Epic disconnect canonical cleanup for user {} (patient {}): {} raw-payload row(s), "
                    + "{} crosswalk row(s) removed", userId, patientId, rawDeleted, crosswalkDeleted);
        } else {
            log.warn("Epic disconnect canonical cleanup skipped for user {}: patientId or sourceId "
                    + "unresolved (patientId={}, sourceId={})", userId, patientId, sourceId);
        }

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
        final String med = textOf(resource.get("medicationCodeableConcept"));
        final String label = textOf(resource.get("code"));
        // CarePlan.title / CareTeam.name are plain strings; Goal.description /
        // FamilyMemberHistory.relationship are CodeableConcepts.
        final String named = stringOf(resource.get("title")) != null
                ? stringOf(resource.get("title")) : stringOf(resource.get("name"));
        final String described = textOf(resource.get("description"));
        final String relationship = textOf(resource.get("relationship"));
        // Encounter (visit) has no code/medication — fall back to its type, then class.
        final String visit = textOf(resource.get("type")) != null
                ? textOf(resource.get("type")) : textOf(resource.get("class"));
        final String best = firstNonNull(med, label, named, described, relationship, visit);
        return best != null ? resourceType + ": " + best : resourceType;
    }

    /** A plain textual JSON field (e.g. CarePlan.title, CareTeam.name), or null. */
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
        // CodeableConcept may arrive as an array (e.g. Encounter.type) — use the first element.
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
        // Bare Coding (e.g. Encounter.class = {system, code, display}).
        if (target.hasNonNull("display")) {
            return target.get("display").asText();
        }
        return null;
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
        // Encounter (visit) carries its date in the nested period, not a scalar field.
        final JsonNode period = resource.get("period");
        if (period != null && period.hasNonNull("start")) {
            return period.get("start").asText();
        }
        return null;
    }

    /** Outcome constants (kept local to avoid importing the entity into the hot path). */
    private static final class EhrResourceOutcome {
        static final String OK = "OK";
        static final String ERROR = "ERROR";
    }
}
