package com.careconnect.service.ehr.athena;

import com.careconnect.config.AthenaProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceQueryRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ehr.EhrSourceResolver;
import com.careconnect.service.ehr.EhrStatusGate;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Pulls a linked patient's athenahealth record into the {@code ehr_resource} mirror, and the
 * verbatim bodies into the canonical {@code ehr_raw_payload} store, the same dual write the Epic
 * integration does.
 *
 * <p>Each resource type is requested only when the portal app has been granted its
 * {@code system/<Type>.read} scope; asking without the scope is a guaranteed 403. Each record is
 * saved in its own transaction, so one bad record skips only itself. When athena has returned a
 * type's complete result, mirrored records it no longer returns are removed, so a record later
 * deleted at athena or marked entered-in-error does not linger in the patient's list.
 *
 * <p>Records are not yet indexed for Ask AI. That wiring lands with the Epic integration's indexing
 * changes, and needs clinical scopes athena has not granted yet.
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.athena.enabled", havingValue = "true")
public class AthenaSyncService {

    /**
     * Clinical types pulled on every sync. DocumentReference is deliberately absent: documents are
     * out of scope, so they are never requested or stored. MedicationStatement is absent because
     * athena does not offer it.
     */
    static final List<String> SYNC_TYPES = List.of(
            "AllergyIntolerance", "Condition", "MedicationRequest", "Observation",
            "DiagnosticReport", "Immunization", "Procedure", "Encounter", "CarePlan", "Goal",
            "CareTeam", "FamilyMemberHistory", "Coverage", "Device");

    /** Parameters athena's CapabilityStatement requires beyond {@code patient}, per type. */
    private static final Map<String, Map<String, String>> REQUIRED_PARAMS = Map.of(
            "MedicationRequest", Map.of("intent", "order"));

    private static final String PATIENT = "Patient";
    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;

    // Column lengths on ehr_resource; an over-long value would otherwise fail the whole row.
    private static final int STATUS_MAX = 48;
    private static final int TITLE_MAX = 512;
    private static final int OCCURRED_AT_MAX = 40;

    private final AthenaFhirClient fhir;
    private final AthenaTokenProvider tokens;
    private final EhrResourceRepository resources;
    private final EhrResourceQueryRepository resourceQueries;
    private final EhrRawPayloadRepository rawPayloads;
    private final EhrStatusGate statusGate;
    private final PatientRepository patients;
    private final EhrSourceResolver sources;
    private final ObjectMapper objectMapper;
    private final ObjectProvider<AthenaSyncService> self;

    /** Who and what one sync is for: the CareConnect ids, and the athena chart and its practice. */
    private record Chart(Long userId, Long patientId, Long sourceId, String practice, String athenaPatientId) {
    }

    // Per instance. Two instances syncing the same user at once are held apart by
    // uq_ehr_resource_identity: the losing insert fails and is skipped like any other bad record.
    private final Set<Long> inFlight = ConcurrentHashMap.newKeySet();

    /**
     * Sync one linked user's record.
     *
     * @throws AthenaSyncInProgressException if a sync for this user is already running here
     * @throws IllegalStateException         if the user has no patient profile or no athena link
     */
    public AthenaSyncResult sync(final Long userId) {
        if (!inFlight.add(userId)) {
            throw new AthenaSyncInProgressException();
        }
        try {
            return run(userId);
        } finally {
            inFlight.remove(userId);
        }
    }

    private AthenaSyncResult run(final Long userId) {
        final Long patientId = patients.findByUserId(userId)
                .map(Patient::getId)
                .orElseThrow(() -> new IllegalStateException("user " + userId + " has no patient profile"));
        final String athenaPatientId = fhir.linkedPatientId(userId)
                .orElseThrow(() -> new IllegalStateException(
                        "user " + userId + " is not linked to an athenahealth chart"));
        // Non-null: a link can only exist once the source is registered.
        final Long sourceId = sources.idForCode(SOURCE);
        // The chart's own practice, from its id. Empty means it is no longer one this deployment may
        // read (the configured list changed after linking), so nothing is requested.
        final Optional<String> practice = fhir.practiceFor(athenaPatientId);
        if (practice.isEmpty()) {
            log.warn("athena sync for user {}: the linked chart is outside the configured practices", userId);
            return AthenaSyncResult.unavailable();
        }

        final Set<String> granted;
        try {
            granted = tokens.grantedScopes();
        } catch (IllegalStateException ex) {
            log.warn("athena sync for user {} could not obtain a token", userId);
            return AthenaSyncResult.unavailable();
        }

        final Chart chart = new Chart(userId, patientId, sourceId, practice.get(), athenaPatientId);
        final List<AthenaSyncResult.TypeResult> results = new ArrayList<>();
        results.add(syncDemographics(chart, granted));
        for (final String type : SYNC_TYPES) {
            results.add(syncType(chart, type, granted));
        }
        log.info("athena sync for user {}: {}", userId, results);
        return AthenaSyncResult.completed(results);
    }

    private AthenaSyncResult.TypeResult syncDemographics(final Chart chart, final Set<String> granted) {
        if (!granted.contains(scopeFor(PATIENT))) {
            return new AthenaSyncResult.TypeResult(PATIENT, AthenaSyncResult.Outcome.NOT_GRANTED, 0);
        }
        final JsonNode patient;
        try {
            patient = fhir.read(chart.userId(), chart.practice(), PATIENT, chart.athenaPatientId());
        } catch (AthenaFhirException ex) {
            return new AthenaSyncResult.TypeResult(PATIENT, outcomeFor(ex.getKind()), 0);
        }
        return store(chart, PATIENT, List.of(patient), false);
    }

    private AthenaSyncResult.TypeResult syncType(final Chart chart, final String type, final Set<String> granted) {
        if (!granted.contains(scopeFor(type))) {
            return new AthenaSyncResult.TypeResult(type, AthenaSyncResult.Outcome.NOT_GRANTED, 0);
        }
        final Map<String, String> params = new LinkedHashMap<>(REQUIRED_PARAMS.getOrDefault(type, Map.of()));
        params.put("patient", chart.athenaPatientId());
        final AthenaFhirClient.SearchResult found;
        try {
            found = fhir.search(chart.userId(), chart.practice(), type, params);
        } catch (AthenaFhirException ex) {
            return new AthenaSyncResult.TypeResult(type, outcomeFor(ex.getKind()), 0);
        }
        return store(chart, type, found.resources(), found.complete());
    }

    /**
     * Mirror what athena returned for one type, each record in its own transaction.
     *
     * @param complete whether {@code fetched} is everything athena holds for this type; only then
     *                 can a mirrored record's absence mean it is gone
     */
    private AthenaSyncResult.TypeResult store(final Chart chart, final String type, final List<JsonNode> fetched,
                                              final boolean complete) {
        final Set<String> current = new HashSet<>();
        int stored = 0;
        int failed = 0;
        for (final JsonNode resource : fetched) {
            final String fhirId = resource.path("id").asText("");
            if (fhirId.isBlank() || !statusGate.isAllowed(resource)) {
                continue;
            }
            current.add(fhirId);
            try {
                // Through the proxy, so @Transactional applies per record.
                self.getObject().mirror(chart.userId(), chart.patientId(), chart.sourceId(), type, resource);
                stored++;
            } catch (RuntimeException ex) {
                failed++;
                log.warn("athena sync could not store one {} for user {}: {}",
                        type, chart.userId(), ex.getClass().getSimpleName());
            }
        }
        if (complete) {
            prune(chart.userId(), type, current);
        }
        if (stored > 0) {
            return new AthenaSyncResult.TypeResult(type, AthenaSyncResult.Outcome.STORED, stored);
        }
        return new AthenaSyncResult.TypeResult(type,
                failed > 0 ? AthenaSyncResult.Outcome.FAILED : AthenaSyncResult.Outcome.EMPTY, 0);
    }

    /** Upsert one record into the mirror and, when its content changed, into the raw payload store. */
    @Transactional
    public void mirror(final Long userId, final Long patientId, final Long sourceId,
                       final String resourceType, final JsonNode resource) {
        final String fhirId = resource.path("id").asText();
        final InlineBinary.Stripped stripped = InlineBinary.strip(resource);
        final JsonNode body = stripped.body();
        final String json = toJson(body);
        final String hash = ContentHashUtil.sha256(json);

        final EhrResource row = resources
                .findByUserIdAndSourceAndResourceTypeAndResourceFhirId(userId, SOURCE, resourceType, fhirId)
                .orElseGet(EhrResource::new);
        final boolean changed = !hash.equals(row.getContentHash());
        row.setUserId(userId);
        row.setSource(SOURCE);
        row.setResourceType(resourceType);
        row.setResourceFhirId(fhirId);
        row.setStatusValue(truncate(statusGate.statusOf(body), STATUS_MAX));
        row.setTitle(truncate(AthenaResourceSummary.title(resourceType, body), TITLE_MAX));
        row.setOccurredAt(truncate(AthenaResourceSummary.occurredAt(body), OCCURRED_AT_MAX));
        row.setContentHash(hash);
        row.setPayloadJson(json);
        // Set explicitly: an unchanged row is not dirty, so @PreUpdate alone would never move it.
        row.setLastSyncedAt(Instant.now());
        resources.save(row);

        // ehr_raw_payload exists so a mapping can be re-derived; an unchanged body adds nothing.
        if (changed) {
            rawPayloads.save(EhrRawPayload.builder()
                    .patientId(patientId)
                    .sourceId(sourceId)
                    .resourceType(resourceType)
                    .externalResourceId(fhirId)
                    .payload(json)
                    .photoStripped(stripped.stripped())
                    .retrievedAt(OffsetDateTime.now())
                    .build());
        }
    }

    /** Remove mirrored records of {@code type} that athena no longer returns. */
    private void prune(final Long userId, final String type, final Set<String> current) {
        final List<EhrResource> gone = resourceQueries
                .findByUserIdAndSourceAndResourceType(userId, SOURCE, type).stream()
                .filter(row -> !current.contains(row.getResourceFhirId()))
                .toList();
        if (!gone.isEmpty()) {
            resources.deleteAll(gone);
            log.info("athena sync removed {} {} record(s) for user {} that athena no longer returns",
                    gone.size(), type, userId);
        }
    }

    private static String scopeFor(final String resourceType) {
        return "system/" + resourceType + ".read";
    }

    private static AthenaSyncResult.Outcome outcomeFor(final AthenaFhirException.Kind kind) {
        return switch (kind) {
            case SCOPE_DENIED -> AthenaSyncResult.Outcome.SCOPE_DENIED;
            case REJECTED -> AthenaSyncResult.Outcome.REJECTED;
            case UNAVAILABLE -> AthenaSyncResult.Outcome.UNAVAILABLE;
        };
    }

    private String toJson(final JsonNode node) {
        try {
            return objectMapper.writeValueAsString(node);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("could not serialize an athena resource", ex);
        }
    }

    private static String truncate(final String value, final int max) {
        return value == null || value.length() <= max ? value : value.substring(0, max);
    }
}
