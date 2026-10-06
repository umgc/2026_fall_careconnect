package com.careconnect.service.ehr;

import ca.uhn.fhir.parser.IParser;
import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrCoverageRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.model.ehr.EhrVisitRecord;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.extern.slf4j.Slf4j;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.ExplanationOfBenefit;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Date;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Consumer;

import static com.careconnect.service.ehr.EhrService.ctxR4;

/**
 * Serves the Medicare reads from the FHIR resources Blue Button returned, so the app gets real FHIR
 * (the Health Data screen's mapper reads FHIR) without asking CMS again on every screen load.
 *
 * <ul>
 *   <li><b>History:</b> {@code ehr_raw_payload} is append-only, as it is for the other EHR
 *       sources. A resource gets a new row only when its content changed; its newest row is the
 *       current copy, and that is what is served. Rows are typed by FHIR resource type.</li>
 *   <li><b>Freshness</b> comes from the audit log (NFR-SEC-07 records one event per retrieval
 *       attempt): the last SUCCESS or EMPTY retrieval of that resource type. If that is a day old,
 *       or there is none, the next read asks Blue Button again, for changes since then when there
 *       is a cache to apply them to. A retrieval that finds nothing new still counts, so the cache
 *       is fresh again for a day.</li>
 *   <li><b>{@code fetchedAt}</b> is that last successful retrieval: what the app shows as "last
 *       updated".</li>
 * </ul>
 * Each retrieved resource is also mirrored into its canonical table ({@code ehr_source_identity},
 * {@code ehr_coverage_record}, {@code ehr_visit_record}), as before.
 */
@Slf4j
@Service
public class MedicareRecordCache {

    /** How long retrieved data is served before Blue Button is asked again. */
    static final Duration MAX_AGE = Duration.ofDays(1);

    static final String PATIENT = "Patient";
    static final String COVERAGE = "Coverage";
    static final String EOB = "ExplanationOfBenefit";

    private static final String MEDICARE = MedicareProperties.SOURCE_MEDICARE;
    private static final Set<EhrRetrievalOutcome> ANSWERED =
            EnumSet.of(EhrRetrievalOutcome.SUCCESS, EhrRetrievalOutcome.EMPTY);

    /** The resources to return, and when they were last retrieved from Medicare. */
    public record CachedRead(List<JsonNode> resources, OffsetDateTime fetchedAt) {
    }

    /** One Blue Button retrieval; {@code since} is null for a full retrieval. */
    @FunctionalInterface
    interface Fetch<R extends Resource> {
        List<R> fetch(String accessToken, Date since);
    }

    private final MedicareService medicare;
    private final MedicareConnectionService connections;
    private final EhrService ehrService;
    private final EhrRawPayloadRepository rawPayloads;
    private final EhrSourceIdentityRepository identities;
    private final EhrAuditEventRepository auditEvents;
    private final EhrAuditLogger audit;
    private final Clock clock;
    private final ObjectMapper json = new ObjectMapper();
    private final IParser parser = ctxR4.newJsonParser();

    @Autowired
    public MedicareRecordCache(
            final MedicareService medicare,
            final MedicareConnectionService connections,
            final EhrService ehrService,
            final EhrRawPayloadRepository rawPayloads,
            final EhrSourceIdentityRepository identities,
            final EhrAuditEventRepository auditEvents,
            final EhrAuditLogger audit) {
        this(medicare, connections, ehrService, rawPayloads, identities, auditEvents, audit, Clock.systemUTC());
    }

    MedicareRecordCache(
            final MedicareService medicare,
            final MedicareConnectionService connections,
            final EhrService ehrService,
            final EhrRawPayloadRepository rawPayloads,
            final EhrSourceIdentityRepository identities,
            final EhrAuditEventRepository auditEvents,
            final EhrAuditLogger audit,
            final Clock clock) {
        this.medicare = medicare;
        this.connections = connections;
        this.ehrService = ehrService;
        this.rawPayloads = rawPayloads;
        this.identities = identities;
        this.auditEvents = auditEvents;
        this.audit = audit;
        this.clock = clock;
    }

    /** The beneficiary's {@code Patient} resource (Blue Button returns one; there is no incremental read). */
    public CachedRead patient(final EhrPatientCrosswalk crosswalk, final Long actorUserId) {
        return read(crosswalk, actorUserId, PATIENT,
                (token, since) -> List.of(medicare.requestMedicarePatientInfo(token)),
                patient -> mirrorIdentity(crosswalk, patient));
    }

    public CachedRead coverage(final EhrPatientCrosswalk crosswalk, final Long actorUserId) {
        return read(crosswalk, actorUserId, COVERAGE,
                (token, since) -> since == null
                        ? medicare.requestMedicareCoverageInfo(token)
                        : medicare.requestMedicareCoverageInfo(token, since),
                coverage -> ehrService.updateCoverageRepository(
                        new EhrCoverageRecord(crosswalk.getPatientId(), coverage, crosswalk.getSourceId())));
    }

    public CachedRead visits(final EhrPatientCrosswalk crosswalk, final Long actorUserId) {
        return read(crosswalk, actorUserId, EOB,
                (token, since) -> since == null
                        ? medicare.requestMedicareEOBInfo(token)
                        : medicare.requestMedicareEOBInfo(token, since),
                eob -> ehrService.updateVisitRepository(
                        new EhrVisitRecord(crosswalk.getPatientId(), eob, crosswalk.getSourceId())));
    }

    private <R extends Resource> CachedRead read(
            final EhrPatientCrosswalk crosswalk,
            final Long actorUserId,
            final String resourceType,
            final Fetch<R> fetch,
            final Consumer<R> mirror) {
        final Long patientId = crosswalk.getPatientId();
        final Long sourceId = crosswalk.getSourceId();
        final Map<String, EhrRawPayload> current = currentCopies(patientId, sourceId, resourceType);
        final Optional<EhrAuditEvent> lastEvent = auditEvents
                .findFirstByPatientIdAndSourceAndResourceTypeAndOutcomeInOrderByEventTimeDesc(
                        patientId, MEDICARE, resourceType, ANSWERED);
        // A retrieval that returned records, with none of them stored now, means the cache was
        // emptied since: an unlink deletes the payloads but keeps the audit log, so a relink inside
        // the day would otherwise be served nothing (DEF-MCR-15). Ask again in full.
        final boolean emptiedSince = current.isEmpty() && lastEvent
                .map(e -> e.getOutcome() == EhrRetrievalOutcome.SUCCESS
                        && e.getRecordCount() != null && e.getRecordCount() > 0)
                .orElse(false);
        final Optional<OffsetDateTime> lastAnswered = emptiedSince
                ? Optional.empty()
                : lastEvent.map(EhrAuditEvent::getEventTime);
        final OffsetDateTime now = OffsetDateTime.now(clock);

        if (lastAnswered.isPresent() && Duration.between(lastAnswered.get(), now).compareTo(MAX_AGE) < 0) {
            return new CachedRead(toJson(current.values()), lastAnswered.get());
        }

        // Ask only for what changed when there is a cache to apply the changes to.
        final Date since = lastAnswered.isPresent() && !current.isEmpty()
                ? Date.from(lastAnswered.get().toInstant())
                : null;
        final String token = connections.requireAccessToken(crosswalk);
        final List<R> results;
        try {
            results = fetch.fetch(token, since);
        } catch (RuntimeException e) {
            // Rethrown: a rejected token becomes ERR-MCR-05 in MedicareErrorAdvice.
            audit.log(patientId, MEDICARE, resourceType, EhrRetrievalOutcome.FAILURE, actorUserId, null,
                    Map.of("error", e.getClass().getSimpleName(), "incremental", since != null), now);
            throw e;
        }

        int changed = 0;
        for (final R resource : results) {
            final boolean photoStripped = stripPhoto(resource);
            final String externalId = resource.getIdElement().getIdPart();
            final String body = parser.encodeResourceToString(resource);
            final EhrRawPayload existing = externalId == null ? null : current.get(externalId);
            if (existing == null || !sameJson(existing.getPayload(), body)) {
                final EhrRawPayload row = new EhrRawPayload();
                row.setPatientId(patientId);
                row.setSourceId(sourceId);
                row.setResourceType(resourceType);
                row.setExternalResourceId(externalId);
                row.setPayload(body);
                row.setPhotoStripped(photoStripped);
                row.setRetrievedAt(now);
                final EhrRawPayload saved = rawPayloads.save(row);
                current.put(externalId != null ? externalId : "row:" + saved.getId(), saved);
                changed++;
            }
            mirror.accept(resource);
        }
        // Counts and flags only: never tokens or clinical content (NFR-SEC-03). Stamped with the
        // time captured before the request, which the next "changes since" read starts from, so a
        // record CMS updates while this one is in flight is not skipped (DEF-MCR-16).
        audit.log(patientId, MEDICARE, resourceType,
                results.isEmpty() ? EhrRetrievalOutcome.EMPTY : EhrRetrievalOutcome.SUCCESS,
                actorUserId, results.size(), Map.of("incremental", since != null, "changed", changed), now);
        return new CachedRead(toJson(current.values()), now);
    }

    /** The newest stored row per external resource id, newest first. */
    private Map<String, EhrRawPayload> currentCopies(final Long patientId, final Long sourceId, final String resourceType) {
        final Map<String, EhrRawPayload> current = new LinkedHashMap<>();
        for (final EhrRawPayload row : rawPayloads
                .findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDescIdDesc(patientId, sourceId, resourceType)) {
            final String key = row.getExternalResourceId() != null ? row.getExternalResourceId() : "row:" + row.getId();
            current.putIfAbsent(key, row);
        }
        return current;
    }

    /** Mirrors the beneficiary's demographics, updating the existing identity row if there is one. */
    private void mirrorIdentity(final EhrPatientCrosswalk crosswalk, final Patient patient) {
        final EhrSourceIdentity identity = new EhrSourceIdentity(crosswalk.getPatientId(), patient, crosswalk.getSourceId());
        identities.findByPatientIdAndSourceId(crosswalk.getPatientId(), crosswalk.getSourceId())
                .ifPresent(existing -> identity.setId(existing.getId()));
        identities.save(identity);
    }

    /** Inline binary ({@code Patient.photo}) is never stored (see the ehr_raw_payload schema notes). */
    private static boolean stripPhoto(final Resource resource) {
        if (resource instanceof Patient patient && patient.hasPhoto()) {
            patient.setPhoto(null);
            return true;
        }
        return false;
    }

    /** Compared as JSON, not text: jsonb does not keep key order or whitespace. */
    private boolean sameJson(final String stored, final String fetched) {
        try {
            return json.readTree(stored).equals(json.readTree(fetched));
        } catch (Exception e) {
            return false;
        }
    }

    private List<JsonNode> toJson(final Collection<EhrRawPayload> rows) {
        final List<JsonNode> nodes = new ArrayList<>(rows.size());
        for (final EhrRawPayload row : rows) {
            try {
                nodes.add(json.readTree(row.getPayload()));
            } catch (Exception e) {
                // Row id only; the payload is PHI.
                log.warn("Skipping unreadable cached {} payload (row {})", row.getResourceType(), row.getId());
            }
        }
        return nodes;
    }
}
