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
import com.careconnect.testsupport.fixtures.AthenaPropertiesFixtures;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.FutureTask;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import java.util.stream.Collectors;

import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.JSON;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.ROMILDA_ID;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.condition;
import static com.careconnect.testsupport.fixtures.AthenaFhirFixtures.romilda;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link AthenaSyncService}: which types are requested, what is stored and how, what
 * is removed afterwards, and how failures surface. Repositories and the FHIR client are mocked; the
 * status gate and the JSON handling are real. The self-proxy returns the service itself, so records
 * are mirrored inline rather than in a transaction.
 */
class AthenaSyncServiceTest {

    private static final long USER_ID = 7L;
    private static final long PATIENT_ID = 5L;
    private static final long SOURCE_ID = 9L;
    private static final String SOURCE = AthenaProperties.SOURCE_ATHENA;
    private static final String PRACTICE = AthenaPropertiesFixtures.PRACTICE_ID;

    private AthenaFhirClient fhir;
    private AthenaTokenProvider tokens;
    private EhrResourceRepository resources;
    private EhrResourceQueryRepository resourceQueries;
    private EhrRawPayloadRepository rawPayloads;
    private PatientRepository patients;
    private EhrSourceResolver sources;
    private ObjectProvider<AthenaSyncService> self;
    private AthenaSyncService service;

    @BeforeEach
    @SuppressWarnings("unchecked")
    void setUp() {
        fhir = mock(AthenaFhirClient.class);
        tokens = mock(AthenaTokenProvider.class);
        resources = mock(EhrResourceRepository.class);
        resourceQueries = mock(EhrResourceQueryRepository.class);
        rawPayloads = mock(EhrRawPayloadRepository.class);
        patients = mock(PatientRepository.class);
        sources = mock(EhrSourceResolver.class);
        self = mock(ObjectProvider.class);
        service = serviceWith(new ObjectMapper());

        when(patients.findByUserId(USER_ID)).thenReturn(Optional.of(Patient.builder().id(PATIENT_ID).build()));
        when(sources.idForCode(SOURCE)).thenReturn(SOURCE_ID);
        when(fhir.linkedPatientId(USER_ID)).thenReturn(Optional.of(ROMILDA_ID));
        when(fhir.practiceFor(ROMILDA_ID)).thenReturn(Optional.of(PRACTICE));
        when(resources.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(any(), any(), any(), any()))
                .thenReturn(Optional.empty());
        when(resources.save(any())).thenAnswer(inv -> inv.getArgument(0));
        when(resourceQueries.findByUserIdAndSourceAndResourceType(any(), any(), any())).thenReturn(List.of());
    }

    /** The service under test, with the self-proxy returning it so records mirror inline. */
    private AthenaSyncService serviceWith(final ObjectMapper objectMapper) {
        final AthenaSyncService built = new AthenaSyncService(fhir, tokens, resources, resourceQueries, rawPayloads,
                new EhrStatusGate(), patients, sources, objectMapper, self);
        when(self.getObject()).thenReturn(built);
        return built;
    }

    private void granted(final String... types) {
        when(tokens.grantedScopes()).thenReturn(Set.of(types).stream()
                .map(type -> "system/" + type + ".read").collect(Collectors.toSet()));
    }

    private void athenaHas(final String type, final JsonNode... found) {
        when(fhir.search(eq(USER_ID), eq(PRACTICE), eq(type), anyMap()))
                .thenReturn(new AthenaFhirClient.SearchResult(List.of(found), true));
    }

    private static Map<String, AthenaSyncResult.TypeResult> byType(final AthenaSyncResult result) {
        return result.types().stream()
                .collect(Collectors.toMap(AthenaSyncResult.TypeResult::resourceType, Function.identity()));
    }

    private static EhrResource row(final String type, final String fhirId) {
        return EhrResource.builder().userId(USER_ID).source(SOURCE).resourceType(type).resourceFhirId(fhirId).build();
    }

    @Test
    @DisplayName("only types whose scope athena granted are requested; the rest report NOT_GRANTED")
    void onlyGrantedTypesAreRequested() {
        // Arrange: what the portal app grants today, plus Condition.
        granted("Patient", "Condition");
        when(fhir.read(USER_ID, PRACTICE, "Patient", ROMILDA_ID)).thenReturn(romilda());
        athenaHas("Condition", condition("c-1", "active", "Asthma", "2024-01-01"));

        // Act
        final AthenaSyncResult result = service.sync(USER_ID);

        // Assert
        assertEquals(AthenaSyncResult.Status.COMPLETED, result.status());
        final Map<String, AthenaSyncResult.TypeResult> types = byType(result);
        assertEquals(AthenaSyncResult.Outcome.STORED, types.get("Patient").outcome());
        assertEquals(AthenaSyncResult.Outcome.STORED, types.get("Condition").outcome());
        assertEquals(AthenaSyncResult.Outcome.NOT_GRANTED, types.get("Observation").outcome());
        verify(fhir, times(1)).search(any(), any(), any(), any());
    }

    @Test
    @DisplayName("DocumentReference is never requested, even when its scope is granted")
    void documentReferenceIsNeverRequested() {
        // Arrange
        granted("DocumentReference");

        // Act
        final AthenaSyncResult result = service.sync(USER_ID);

        // Assert
        assertFalse(AthenaSyncService.SYNC_TYPES.contains("DocumentReference"));
        assertFalse(byType(result).containsKey("DocumentReference"));
        verify(fhir, never()).search(any(), any(), eq("DocumentReference"), any());
    }

    @Test
    @DisplayName("MedicationRequest is searched with the intent athena requires alongside patient")
    @SuppressWarnings("unchecked")
    void medicationRequestCarriesIntent() {
        // Arrange
        granted("MedicationRequest");
        athenaHas("MedicationRequest");

        // Act
        service.sync(USER_ID);

        // Assert
        final ArgumentCaptor<Map<String, String>> params = ArgumentCaptor.forClass(Map.class);
        verify(fhir).search(eq(USER_ID), eq(PRACTICE), eq("MedicationRequest"), params.capture());
        assertEquals(Map.of("intent", "order", "patient", ROMILDA_ID), params.getValue());
    }

    @Test
    @DisplayName("entered-in-error records are not stored, and stored ones athena stopped returning are removed")
    void statusGatedAndVanishedRecordsArePruned() {
        // Arrange: c-2 was mirrored earlier and is now entered-in-error; c-3 is gone from athena.
        granted("Condition");
        athenaHas("Condition", condition("c-1", "active", "Asthma", "2024-01-01"),
                condition("c-2", "entered-in-error", "Asthma", "2024-01-01"));
        final EhrResource stale = row("Condition", "c-2");
        final EhrResource gone = row("Condition", "c-3");
        final EhrResource kept = row("Condition", "c-1");
        when(resourceQueries.findByUserIdAndSourceAndResourceType(USER_ID, SOURCE, "Condition"))
                .thenReturn(List.of(kept, stale, gone));

        // Act
        final AthenaSyncResult result = service.sync(USER_ID);

        // Assert
        assertEquals(1, byType(result).get("Condition").count());
        verify(resources).deleteAll(List.of(stale, gone));
        verify(resources, times(1)).save(argThat(saved -> "c-1".equals(saved.getResourceFhirId())));
    }

    @Test
    @DisplayName("an incomplete result never prunes, since an absent record may be on an unread page")
    void incompleteResultIsNotPruned() {
        // Arrange
        granted("Condition");
        when(fhir.search(eq(USER_ID), eq(PRACTICE), eq("Condition"), anyMap())).thenReturn(new AthenaFhirClient.SearchResult(
                List.of(condition("c-1", "active", "Asthma", null)), false));

        // Act
        service.sync(USER_ID);

        // Assert
        verify(resourceQueries, never()).findByUserIdAndSourceAndResourceType(any(), any(), any());
        verify(resources, never()).deleteAll(any());
    }

    @Test
    @DisplayName("a failing type reports its own outcome and the remaining types still sync")
    void typeFailuresBecomeOutcomes() {
        // Arrange
        granted("Condition", "Observation", "Procedure", "Immunization");
        when(fhir.search(eq(USER_ID), eq(PRACTICE), eq("Condition"), anyMap()))
                .thenThrow(new AthenaFhirException(AthenaFhirException.Kind.SCOPE_DENIED, "403"));
        when(fhir.search(eq(USER_ID), eq(PRACTICE), eq("Observation"), anyMap()))
                .thenThrow(new AthenaFhirException(AthenaFhirException.Kind.UNAVAILABLE, "503"));
        when(fhir.search(eq(USER_ID), eq(PRACTICE), eq("Procedure"), anyMap()))
                .thenThrow(new AthenaFhirException(AthenaFhirException.Kind.REJECTED, "400"));
        athenaHas("Immunization");

        // Act
        final Map<String, AthenaSyncResult.TypeResult> types = byType(service.sync(USER_ID));

        // Assert
        assertEquals(AthenaSyncResult.Outcome.SCOPE_DENIED, types.get("Condition").outcome());
        assertEquals(AthenaSyncResult.Outcome.UNAVAILABLE, types.get("Observation").outcome());
        assertEquals(AthenaSyncResult.Outcome.REJECTED, types.get("Procedure").outcome());
        assertEquals(AthenaSyncResult.Outcome.EMPTY, types.get("Immunization").outcome());
        verify(resources, never()).deleteAll(any());
    }

    @Test
    @DisplayName("no token means SOURCE_UNAVAILABLE and athena is never called")
    void noTokenIsSourceUnavailable() {
        // Arrange
        when(tokens.grantedScopes()).thenThrow(new IllegalStateException("quota exceeded"));

        // Act
        final AthenaSyncResult result = service.sync(USER_ID);

        // Assert
        assertEquals(AthenaSyncResult.Status.SOURCE_UNAVAILABLE, result.status());
        assertTrue(result.types().isEmpty());
        verify(fhir, never()).search(any(), any(), any(), any());
        verify(fhir, never()).read(any(), any(), any(), any());
    }

    @Test
    @DisplayName("one record that fails to save does not stop the rest; all failing reports FAILED")
    void failingRecordsAreIsolated() {
        // Arrange
        granted("Condition", "Observation");
        athenaHas("Condition", condition("c-1", "active", "Asthma", null), condition("c-2", "active", "Gout", null));
        final ObjectNode observation = JSON.createObjectNode().put("resourceType", "Observation").put("id", "o-1");
        athenaHas("Observation", observation);
        when(resources.save(argThat(saved -> saved != null
                && ("c-1".equals(saved.getResourceFhirId()) || "o-1".equals(saved.getResourceFhirId())))))
                .thenThrow(new IllegalStateException("constraint"));

        // Act
        final Map<String, AthenaSyncResult.TypeResult> types = byType(service.sync(USER_ID));

        // Assert
        assertEquals(AthenaSyncResult.Outcome.STORED, types.get("Condition").outcome());
        assertEquals(1, types.get("Condition").count());
        assertEquals(AthenaSyncResult.Outcome.FAILED, types.get("Observation").outcome());
    }

    @Test
    @DisplayName("a second sync for the same user is refused while the first is running, then allowed")
    void concurrentSyncForOneUserIsRefused() throws Exception {
        // Arrange: hold the first sync inside its token lookup until the second attempt has been made.
        final CountDownLatch firstStarted = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        when(tokens.grantedScopes()).thenAnswer(inv -> {
            firstStarted.countDown();
            assertTrue(release.await(5, TimeUnit.SECONDS), "test never released the first sync");
            return Set.of();
        });
        final FutureTask<AthenaSyncResult> first = new FutureTask<>(() -> service.sync(USER_ID));
        new Thread(first, "athena-sync-first").start();
        assertTrue(firstStarted.await(5, TimeUnit.SECONDS));

        // Act / Assert: refused while running.
        assertThrows(AthenaSyncInProgressException.class, () -> service.sync(USER_ID));

        // Act / Assert: the first finishes, and the guard is released for the next sync.
        release.countDown();
        assertEquals(AthenaSyncResult.Status.COMPLETED, first.get(5, TimeUnit.SECONDS).status());
        assertEquals(AthenaSyncResult.Status.COMPLETED, service.sync(USER_ID).status());
    }

    @Test
    @DisplayName("a sync that fails before starting still releases the per-user guard")
    void guardIsReleasedAfterAFailure() {
        // Arrange
        when(fhir.linkedPatientId(USER_ID)).thenReturn(Optional.empty());

        // Act / Assert: twice, so a leaked guard would surface as AthenaSyncInProgressException.
        assertThrows(IllegalStateException.class, () -> service.sync(USER_ID));
        assertThrows(IllegalStateException.class, () -> service.sync(USER_ID));
    }

    @Test
    @DisplayName("mirror derives title, status and date, and touches lastSyncedAt")
    void mirrorDerivesRowFields() {
        // Act
        service.mirror(USER_ID, PATIENT_ID, SOURCE_ID, "Condition", condition("c-1", "active", "Asthma", "2024-03-05"));

        // Assert
        final ArgumentCaptor<EhrResource> saved = ArgumentCaptor.forClass(EhrResource.class);
        verify(resources).save(saved.capture());
        assertEquals("Condition: Asthma", saved.getValue().getTitle());
        assertEquals("active", saved.getValue().getStatusValue());
        assertEquals("2024-03-05", saved.getValue().getOccurredAt());
        assertEquals(SOURCE, saved.getValue().getSource());
        assertNotNull(saved.getValue().getLastSyncedAt());
    }

    @Test
    @DisplayName("an unchanged record refreshes the mirror but adds no raw payload row")
    void unchangedContentWritesNoRawPayload() {
        // Arrange: the first pass stores the record; the second finds it with the same content hash.
        final ObjectNode resource = condition("c-1", "active", "Asthma", "2024-03-05");
        service.mirror(USER_ID, PATIENT_ID, SOURCE_ID, "Condition", resource);
        final ArgumentCaptor<EhrResource> first = ArgumentCaptor.forClass(EhrResource.class);
        verify(resources).save(first.capture());
        when(resources.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(USER_ID, SOURCE, "Condition", "c-1"))
                .thenReturn(Optional.of(first.getValue()));

        // Act
        service.mirror(USER_ID, PATIENT_ID, SOURCE_ID, "Condition", resource);

        // Assert
        verify(resources, times(2)).save(any());
        verify(rawPayloads, times(1)).save(any());
    }

    @Test
    @DisplayName("Patient.photo and inline attachment data are removed before anything is stored")
    void inlineBinaryIsStrippedBeforeStorage() {
        // Arrange
        final ObjectNode patient = romilda();
        patient.putArray("photo").addObject().put("contentType", "image/png").put("data", "iVBORw0KGgo=");
        final ObjectNode report = JSON.createObjectNode().put("resourceType", "DiagnosticReport").put("id", "dr-1");
        report.putArray("presentedForm").addObject().put("contentType", "application/pdf")
                .put("data", "JVBERi0xLjQ=").put("title", "Lab report");

        // Act
        service.mirror(USER_ID, PATIENT_ID, SOURCE_ID, "Patient", patient);
        service.mirror(USER_ID, PATIENT_ID, SOURCE_ID, "DiagnosticReport", report);

        // Assert
        final ArgumentCaptor<EhrRawPayload> payloads = ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloads, times(2)).save(payloads.capture());
        for (final EhrRawPayload stored : payloads.getAllValues()) {
            assertTrue(stored.getPhotoStripped());
            assertFalse(stored.getPayload().contains("iVBORw0KGgo="));
            assertFalse(stored.getPayload().contains("JVBERi0xLjQ="));
        }
        assertTrue(payloads.getAllValues().get(1).getPayload().contains("Lab report"));
        final ArgumentCaptor<EhrResource> rows = ArgumentCaptor.forClass(EhrResource.class);
        verify(resources, times(2)).save(rows.capture());
        rows.getAllValues().forEach(row -> assertFalse(row.getPayloadJson().contains("\"data\"")));
        // The caller's node is left untouched.
        assertTrue(patient.has("photo"));
    }

    @Test
    @DisplayName("a Patient read that athena refuses reports its outcome instead of failing the sync")
    void demographicsFailureIsAnOutcome() {
        // Arrange
        granted("Patient");
        when(fhir.read(USER_ID, PRACTICE, "Patient", ROMILDA_ID))
                .thenThrow(new AthenaFhirException(AthenaFhirException.Kind.SCOPE_DENIED, "403"));

        // Act
        final Map<String, AthenaSyncResult.TypeResult> types = byType(service.sync(USER_ID));

        // Assert
        assertEquals(AthenaSyncResult.Outcome.SCOPE_DENIED, types.get("Patient").outcome());
        verify(resources, never()).save(any());
    }

    @Test
    @DisplayName("records with no id are skipped rather than stored under a blank key")
    void recordsWithoutAnIdAreSkipped() {
        // Arrange
        granted("Condition");
        final ObjectNode noId = condition("ignored", "active", "Asthma", null);
        noId.remove("id");
        athenaHas("Condition", noId);

        // Act
        final Map<String, AthenaSyncResult.TypeResult> types = byType(service.sync(USER_ID));

        // Assert
        assertEquals(AthenaSyncResult.Outcome.EMPTY, types.get("Condition").outcome());
        verify(resources, never()).save(any());
        verify(rawPayloads, never()).save(any());
    }

    @Test
    @DisplayName("a linked chart outside the configured practices is SOURCE_UNAVAILABLE and athena is not called")
    void chartOutsideConfiguredPracticesIsNotSynced() {
        // Arrange: the practice list changed after the patient was linked.
        granted("Patient", "Condition");
        when(fhir.practiceFor(ROMILDA_ID)).thenReturn(Optional.empty());

        // Act
        final AthenaSyncResult result = service.sync(USER_ID);

        // Assert
        assertEquals(AthenaSyncResult.Status.SOURCE_UNAVAILABLE, result.status());
        verify(fhir, never()).search(any(), any(), any(), any());
        verify(fhir, never()).read(any(), any(), any(), any());
        verify(tokens, never()).grantedScopes();
    }

    @Test
    @DisplayName("a record that cannot be serialized is skipped, and the type reports FAILED")
    void serializationFailureIsFailed() throws Exception {
        // Arrange: no real JsonNode fails to serialize, so the mapper is made to.
        final ObjectMapper failing = mock(ObjectMapper.class);
        when(failing.writeValueAsString(any())).thenThrow(new JsonProcessingException("cannot serialize") { });
        service = serviceWith(failing);
        granted("Condition");
        athenaHas("Condition", condition("c-1", "active", "Asthma", null));

        // Act
        final Map<String, AthenaSyncResult.TypeResult> types = byType(service.sync(USER_ID));

        // Assert
        assertEquals(AthenaSyncResult.Outcome.FAILED, types.get("Condition").outcome());
        verify(resources, never()).save(any());
    }
}
