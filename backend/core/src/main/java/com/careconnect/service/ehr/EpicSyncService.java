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

    /** Core clinical set fetched on connect (1_0 §5 #1–13, read-first). */
    private static final List<String> SYNC_RESOURCE_TYPES = List.of(
            "AllergyIntolerance", "Condition", "MedicationRequest", "MedicationStatement",
            "Observation", "DiagnosticReport", "Immunization", "Procedure", "DocumentReference");

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

        int stored = 0;
        int skipped = 0;
        int failed = 0;
        for (final String resourceType : SYNC_RESOURCE_TYPES) {
            if (!grantedScopes.isEmpty()
                    && !grantedScopes.contains("patient/" + resourceType + ".read")) {
                skipped++;
                log.debug("Epic sync skipping {} for user {} (scope not granted)", resourceType, userId);
                continue;
            }
            try {
                final List<JsonNode> resources = fhirClient.fetch(userId, resourceType, java.util.Map.of());
                for (final JsonNode resource : resources) {
                    if (!statusGate.isAllowed(resource)) {
                        continue;
                    }
                    try {
                        // Persist each resource in its OWN transaction (routed through the Spring
                        // proxy) so a single failing row does not poison the whole sync.
                        if (selfProvider.getObject().upsertAndEmit(userId, resourceType, resource)) {
                            stored++;
                        }
                    } catch (final RuntimeException ex) {
                        failed++;
                        log.warn("Epic sync skipped one {} resource for user {}: {}",
                                resourceType, userId, ex.getClass().getSimpleName());
                    }
                }
            } catch (final RuntimeException ex) {
                skipped++;
                log.warn("Epic sync skipped resource type {} for user {}: {}",
                        resourceType, userId, ex.getClass().getSimpleName());
            }
        }
        audit.record(userId, EpicProperties.SOURCE_EPIC, "EPIC_SYNC", null,
                String.valueOf(stored), EhrResourceOutcome.OK);
        log.info("Epic sync stored/updated {} resources for user {} ({} resource types skipped, "
                + "{} individual resources failed)", stored, userId, skipped, failed);
        return stored;
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
