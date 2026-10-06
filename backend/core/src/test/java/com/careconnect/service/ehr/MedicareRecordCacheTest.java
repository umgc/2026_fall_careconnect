package com.careconnect.service.ehr;

import ca.uhn.fhir.parser.IParser;
import com.careconnect.model.ehr.EhrAuditEvent;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrRetrievalOutcome;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.service.ehr.MedicareRecordCache.CachedRead;
import com.fasterxml.jackson.databind.JsonNode;
import org.hl7.fhir.r4.model.Attachment;
import org.hl7.fhir.r4.model.Bundle;
import org.hl7.fhir.r4.model.Coverage;
import org.hl7.fhir.r4.model.Enumerations;
import org.hl7.fhir.r4.model.HumanName;
import org.hl7.fhir.r4.model.Patient;
import org.hl7.fhir.r4.model.Resource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

import static com.careconnect.service.ehr.EhrService.ctxR4;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * The Medicare read cache: FHIR served from ehr_raw_payload, refreshed from Blue Button once a day.
 * <p>
 * Resources come from a parsed Bundle with fullUrl and a version, as Blue Button sends them, so the
 * id handling is tested against what HAPI really produces. Test IDs TC-MCR-CACHE-001..010 are
 * permanent. Never renumber, never reuse.
 */
@ExtendWith(MockitoExtension.class)
class MedicareRecordCacheTest {

    private static final OffsetDateTime NOW = OffsetDateTime.parse("2026-10-06T12:00:00Z");
    private static final String BASE = "https://sandbox.bluebutton.cms.gov/v3/fhir/";
    private static final long PATIENT_ID = 2L;
    private static final long SOURCE_ID = 9L;
    private static final long ACTOR = 6L;
    private static final IParser PARSER = ctxR4.newJsonParser();

    @Mock
    MedicareService medicare;
    @Mock
    MedicareConnectionService connections;
    @Mock
    EhrService ehrService;
    @Mock
    EhrRawPayloadRepository rawPayloads;
    @Mock
    EhrSourceIdentityRepository identities;
    @Mock
    EhrAuditEventRepository auditEvents;
    @Mock
    EhrAuditLogger audit;

    private MedicareRecordCache cache;
    private EhrPatientCrosswalk crosswalk;
    private final AtomicLong rowIds = new AtomicLong(100);

    @BeforeEach
    void setUp() {
        cache = new MedicareRecordCache(medicare, connections, ehrService, rawPayloads, identities, auditEvents,
                audit, Clock.fixed(NOW.toInstant(), ZoneOffset.UTC));
        crosswalk = new EhrPatientCrosswalk();
        crosswalk.setPatientId(PATIENT_ID);
        crosswalk.setSourceId(SOURCE_ID);
    }

    // ---- fixtures ----

    /** Resources as HAPI hands them over from a Blue Button search Bundle: fullUrl plus a version. */
    @SuppressWarnings("unchecked")
    private static <R extends Resource> List<R> fromBundle(final R... resources) {
        final Bundle bundle = new Bundle();
        bundle.setType(Bundle.BundleType.SEARCHSET);
        for (final R r : resources) {
            final String id = r.getIdElement().getIdPart();
            r.getMeta().setVersionId("7");
            bundle.addEntry().setFullUrl(BASE + r.fhirType() + "/" + id).setResource(r);
        }
        final Bundle parsed = PARSER.parseResource(Bundle.class, PARSER.encodeResourceToString(bundle));
        final List<R> out = new ArrayList<>();
        parsed.getEntry().forEach(e -> out.add((R) e.getResource()));
        return out;
    }

    private static Coverage coverage(final String id, final String plan) {
        final Coverage c = new Coverage();
        c.setId(id);
        c.setStatus(Coverage.CoverageStatus.ACTIVE);
        c.getMeta().setLastUpdated(Date.from(NOW.minusDays(30).toInstant()));
        c.addClass_().setValue(plan);
        return c;
    }

    private static Patient patient(final String id) {
        final Patient p = new Patient();
        p.setId(id);
        p.getMeta().setLastUpdated(Date.from(NOW.minusDays(30).toInstant()));
        p.addName(new HumanName().setFamily("Doe").addGiven("Jane"));
        p.setGender(Enumerations.AdministrativeGender.FEMALE);
        p.setBirthDateElement(new org.hl7.fhir.r4.model.DateType("1950-03-09"));
        return p;
    }

    /** A row as an earlier retrieval stored it: the resource as Blue Button sent it. */
    private EhrRawPayload stored(final String externalId, final Resource sent, final OffsetDateTime retrievedAt) {
        final Resource resource = fromBundle(sent).get(0);
        final EhrRawPayload row = new EhrRawPayload();
        row.setId(rowIds.incrementAndGet());
        row.setPatientId(PATIENT_ID);
        row.setSourceId(SOURCE_ID);
        row.setResourceType(resource.fhirType());
        row.setExternalResourceId(externalId);
        row.setPayload(PARSER.encodeResourceToString(resource));
        row.setRetrievedAt(retrievedAt);
        return row;
    }

    private void cached(final String type, final EhrRawPayload... rows) {
        when(rawPayloads.findByPatientIdAndSourceIdAndResourceTypeOrderByRetrievedAtDescIdDesc(PATIENT_ID, SOURCE_ID, type))
                .thenReturn(List.of(rows));
    }

    private void lastAnswered(final String type, final OffsetDateTime at) {
        when(auditEvents.findFirstByPatientIdAndSourceAndResourceTypeAndOutcomeInOrderByEventTimeDesc(
                eq(PATIENT_ID), eq("MEDICARE"), eq(type), any()))
                .thenReturn(Optional.ofNullable(at).map(t -> EhrAuditEvent.builder().eventTime(t).build()));
    }

    private void saveReturnsRowWithId() {
        when(rawPayloads.save(any(EhrRawPayload.class))).thenAnswer(inv -> {
            final EhrRawPayload row = inv.getArgument(0);
            row.setId(rowIds.incrementAndGet());
            return row;
        });
    }

    private static List<String> plans(final CachedRead read) {
        return read.resources().stream()
                .map(r -> r.path("class").path(0).path("value").asText())
                .toList();
    }

    // ---- tests ----

    @Test
    @DisplayName("TC-MCR-CACHE-001: a first read fetches everything, stores FHIR-typed rows keyed by id part, mirrors and audits SUCCESS")
    void firstReadFetchesAndStores() {
        cached(MedicareRecordCache.COVERAGE);
        lastAnswered(MedicareRecordCache.COVERAGE, null);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        when(medicare.requestMedicareCoverageInfo("tok"))
                .thenReturn(fromBundle(coverage("part-a--1", "A"), coverage("part-b--1", "B")));
        saveReturnsRowWithId();

        final CachedRead read = cache.coverage(crosswalk, ACTOR);

        final ArgumentCaptor<EhrRawPayload> rows = ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloads, times(2)).save(rows.capture());
        assertThat(rows.getAllValues()).extracting(EhrRawPayload::getResourceType).containsOnly("Coverage");
        assertThat(rows.getAllValues()).extracting(EhrRawPayload::getExternalResourceId)
                .containsExactly("part-a--1", "part-b--1");
        assertThat(rows.getAllValues()).extracting(EhrRawPayload::getRetrievedAt).containsOnly(NOW);
        verify(ehrService, times(2)).updateCoverageRepository(any());
        verify(audit).log(eq(PATIENT_ID), eq("MEDICARE"), eq("Coverage"), eq(EhrRetrievalOutcome.SUCCESS),
                eq(ACTOR), eq(2), anyMap());

        assertThat(read.fetchedAt()).isEqualTo(NOW);
        assertThat(read.resources()).extracting(r -> r.path("resourceType").asText()).containsOnly("Coverage");
        assertThat(plans(read)).containsExactly("A", "B");
    }

    @Test
    @DisplayName("TC-MCR-CACHE-002: data retrieved under a day ago is served from the cache, without calling Blue Button")
    void freshCacheIsServed() {
        // Regression: this branch used to compare an OffsetDateTime with a LocalDateTime and throw.
        final OffsetDateTime twoHoursAgo = NOW.minusHours(2);
        cached(MedicareRecordCache.COVERAGE, stored("part-a--1", coverage("part-a--1", "A"), NOW.minusDays(3)));
        lastAnswered(MedicareRecordCache.COVERAGE, twoHoursAgo);

        final CachedRead read = cache.coverage(crosswalk, ACTOR);

        assertThat(plans(read)).containsExactly("A");
        assertThat(read.fetchedAt()).as("fetchedAt is the last retrieval, not this request").isEqualTo(twoHoursAgo);
        verifyNoInteractions(medicare, connections, audit);
        verify(rawPayloads, never()).save(any());
    }

    @Test
    @DisplayName("TC-MCR-CACHE-003: a day-old cache asks only for changes since the last retrieval; unchanged resources add no row")
    void staleCacheFetchesChangesSinceLastRetrieval() {
        final OffsetDateTime twoDaysAgo = NOW.minusDays(2);
        final Coverage a = coverage("part-a--1", "A");
        cached(MedicareRecordCache.COVERAGE,
                stored("part-a--1", a, twoDaysAgo),
                stored("part-b--1", coverage("part-b--1", "B"), twoDaysAgo));
        lastAnswered(MedicareRecordCache.COVERAGE, twoDaysAgo);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        // part-a comes back unchanged, part-b with a new plan.
        when(medicare.requestMedicareCoverageInfo("tok", Date.from(twoDaysAgo.toInstant())))
                .thenReturn(fromBundle(coverage("part-a--1", "A"), coverage("part-b--1", "B2")));
        saveReturnsRowWithId();

        final CachedRead read = cache.coverage(crosswalk, ACTOR);

        final ArgumentCaptor<EhrRawPayload> rows = ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloads).save(rows.capture());
        assertThat(rows.getValue().getExternalResourceId()).isEqualTo("part-b--1");
        assertThat(plans(read)).as("one current copy per resource, newest content").containsExactlyInAnyOrder("A", "B2");
        assertThat(read.fetchedAt()).isEqualTo(NOW);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-004: a refresh that finds nothing new is audited EMPTY, so the cache counts as fresh again")
    void emptyRefreshStillCounts() {
        final OffsetDateTime twoDaysAgo = NOW.minusDays(2);
        cached(MedicareRecordCache.COVERAGE, stored("part-a--1", coverage("part-a--1", "A"), twoDaysAgo));
        lastAnswered(MedicareRecordCache.COVERAGE, twoDaysAgo);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        when(medicare.requestMedicareCoverageInfo(eq("tok"), any(Date.class))).thenReturn(List.of());

        final CachedRead read = cache.coverage(crosswalk, ACTOR);

        verify(audit).log(eq(PATIENT_ID), eq("MEDICARE"), eq("Coverage"), eq(EhrRetrievalOutcome.EMPTY),
                eq(ACTOR), eq(0), anyMap());
        assertThat(plans(read)).containsExactly("A");
        assertThat(read.fetchedAt()).isEqualTo(NOW);
        verify(rawPayloads, never()).save(any());
    }

    @Test
    @DisplayName("TC-MCR-CACHE-005: a failed retrieval is audited as FAILURE and rethrown, and nothing is stored")
    void failureIsAuditedAndRethrown() {
        cached(MedicareRecordCache.COVERAGE);
        lastAnswered(MedicareRecordCache.COVERAGE, null);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        when(medicare.requestMedicareCoverageInfo("tok")).thenThrow(new IllegalStateException("boom"));

        assertThatThrownBy(() -> cache.coverage(crosswalk, ACTOR)).isInstanceOf(IllegalStateException.class);

        verify(audit).log(eq(PATIENT_ID), eq("MEDICARE"), eq("Coverage"), eq(EhrRetrievalOutcome.FAILURE),
                eq(ACTOR), isNull(), anyMap());
        verify(rawPayloads, never()).save(any());
    }

    @Test
    @DisplayName("TC-MCR-CACHE-006: a resource read from a Bundle is matched on its id part, so a new version updates rather than duplicates")
    void idPartMatchesAcrossVersions() {
        final Coverage fromBlueButton = fromBundle(coverage("part-a--1", "A2")).get(0);
        // What HAPI gives for a Bundle entry: the full URL and the version, not the bare id.
        assertThat(fromBlueButton.getId()).startsWith(BASE).contains("_history");
        assertThat(fromBlueButton.getIdElement().getIdPart()).isEqualTo("part-a--1");

        final OffsetDateTime twoDaysAgo = NOW.minusDays(2);
        cached(MedicareRecordCache.COVERAGE, stored("part-a--1", coverage("part-a--1", "A"), twoDaysAgo));
        lastAnswered(MedicareRecordCache.COVERAGE, twoDaysAgo);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        when(medicare.requestMedicareCoverageInfo(eq("tok"), any(Date.class))).thenReturn(List.of(fromBlueButton));
        saveReturnsRowWithId();

        assertThat(plans(cache.coverage(crosswalk, ACTOR))).containsExactly("A2");
    }

    @Test
    @DisplayName("TC-MCR-CACHE-007: Patient.photo is stripped before storage and flagged, and the identity row is updated in place")
    void patientPhotoStrippedAndIdentityUpdated() {
        final Patient withPhoto = patient("bene-1");
        withPhoto.addPhoto(new Attachment().setContentType("image/png").setData(new byte[] {1, 2, 3}));
        cached(MedicareRecordCache.PATIENT);
        lastAnswered(MedicareRecordCache.PATIENT, null);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        when(medicare.requestMedicarePatientInfo("tok")).thenReturn(fromBundle(withPhoto).get(0));
        saveReturnsRowWithId();
        final EhrSourceIdentity existing = new EhrSourceIdentity();
        existing.setId(55L);
        when(identities.findByPatientIdAndSourceId(PATIENT_ID, SOURCE_ID)).thenReturn(Optional.of(existing));

        final CachedRead read = cache.patient(crosswalk, ACTOR);

        final ArgumentCaptor<EhrRawPayload> row = ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloads).save(row.capture());
        assertThat(row.getValue().getPhotoStripped()).isTrue();
        assertThat(row.getValue().getPayload()).doesNotContain("\"photo\"");
        assertThat(read.resources().get(0).has("photo")).isFalse();

        final ArgumentCaptor<EhrSourceIdentity> identity = ArgumentCaptor.forClass(EhrSourceIdentity.class);
        verify(identities).save(identity.capture());
        assertThat(identity.getValue().getId()).isEqualTo(55L);
    }

    @Test
    @DisplayName("TC-MCR-CACHE-008: a Patient with a cached copy but no identity row is mirrored as a new row, not a crash")
    void missingIdentityRowIsCreated() {
        // E.g. after the retention purge removed the snapshot but not the payload.
        final OffsetDateTime twoDaysAgo = NOW.minusDays(2);
        cached(MedicareRecordCache.PATIENT, stored("bene-1", patient("bene-1"), twoDaysAgo));
        lastAnswered(MedicareRecordCache.PATIENT, twoDaysAgo);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        final Patient renamed = patient("bene-1");
        renamed.getNameFirstRep().setFamily("Roe");
        when(medicare.requestMedicarePatientInfo("tok")).thenReturn(fromBundle(renamed).get(0));
        saveReturnsRowWithId();
        when(identities.findByPatientIdAndSourceId(PATIENT_ID, SOURCE_ID)).thenReturn(Optional.empty());

        cache.patient(crosswalk, ACTOR);

        final ArgumentCaptor<EhrSourceIdentity> identity = ArgumentCaptor.forClass(EhrSourceIdentity.class);
        verify(identities).save(identity.capture());
        assertThat(identity.getValue().getId()).isNull();
        assertThat(identity.getValue().getDateOfBirth()).hasToString("1950-03-09");
    }

    @Test
    @DisplayName("TC-MCR-CACHE-009: cached rows with no recorded retrieval (e.g. audit purged) trigger a full retrieval, not an incremental one")
    void noRecordedRetrievalMeansFullFetch() {
        cached(MedicareRecordCache.EOB);
        lastAnswered(MedicareRecordCache.EOB, null);
        when(connections.requireAccessToken(crosswalk)).thenReturn("tok");
        when(medicare.requestMedicareEOBInfo("tok")).thenReturn(List.of());

        cache.visits(crosswalk, ACTOR);

        verify(medicare).requestMedicareEOBInfo("tok");
        verify(medicare, never()).requestMedicareEOBInfo(anyString(), any(Date.class));
    }

    @Test
    @DisplayName("TC-MCR-CACHE-010: the served list holds only the newest copy of each resource")
    void onlyNewestCopyIsServed() {
        cached(MedicareRecordCache.COVERAGE,
                stored("part-a--1", coverage("part-a--1", "A-new"), NOW.minusHours(3)),
                stored("part-a--1", coverage("part-a--1", "A-old"), NOW.minusDays(40)));
        lastAnswered(MedicareRecordCache.COVERAGE, NOW.minusHours(3));

        final List<JsonNode> served = cache.coverage(crosswalk, ACTOR).resources();

        assertThat(served).hasSize(1);
        assertThat(served.get(0).path("class").path(0).path("value").asText()).isEqualTo("A-new");
    }
}
