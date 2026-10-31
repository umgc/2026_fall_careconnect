package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrResource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.ai.indexing.chunker.EpicResourceChunker;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Orchestration tests for {@link EpicSyncService}: that it wires the canonical projector and the
 * identity-sync into the per-resource mirror path, isolates a reconcile failure, and cleans the
 * canonical layer on disconnect. The projector and identity-sync are kept as mocks here — their own
 * mapping logic is covered by {@link EpicCanonicalProjectorTest} and {@link EpicIdentitySyncTest}.
 * Canonical-write (raw payload / crosswalk) and DELTA behaviour live in their existing suites.
 */
class EpicSyncServiceTest {

    private final EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
    private final EhrStatusGate statusGate = mock(EhrStatusGate.class);
    private final IndexingEventEmitter eventEmitter = mock(IndexingEventEmitter.class);
    private final RetrievalIndexService retrievalIndexService = mock(RetrievalIndexService.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final EhrSourceResolver sourceResolver = mock(EhrSourceResolver.class);
    private final EhrPatientCrosswalkRepository crosswalkRepo = mock(EhrPatientCrosswalkRepository.class);
    private final EhrRawPayloadRepository rawPayloadRepo = mock(EhrRawPayloadRepository.class);
    private final EhrAuditService audit = mock(EhrAuditService.class);
    private final EpicFhirClient fhirClient = mock(EpicFhirClient.class);
    private final EpicOAuthService oauth = mock(EpicOAuthService.class);
    private final EpicCanonicalProjector projector = mock(EpicCanonicalProjector.class);
    private final EpicIdentitySync identitySync = mock(EpicIdentitySync.class);
    @SuppressWarnings("unchecked")
    private final ObjectProvider<EpicSyncService> selfProvider = mock(ObjectProvider.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    private EpicSyncService service() {
        when(resourceRepo.save(any(EhrResource.class))).thenAnswer(inv -> inv.getArgument(0));
        final EpicSyncService service = new EpicSyncService(
                fhirClient,
                resourceRepo,
                statusGate,
                mock(EpicResourceChunker.class),
                eventEmitter,
                retrievalIndexService,
                audit,
                objectMapper,
                selfProvider,
                oauth,
                mock(EpicProperties.class),
                patientRepository,
                sourceResolver,
                crosswalkRepo,
                rawPayloadRepo,
                projector,
                identitySync);
        // mirror() re-enters the proxy for its own-transaction upsert; route it back to this instance.
        when(selfProvider.getObject()).thenReturn(service);
        return service;
    }

    private static Patient patientWithId(final long id) {
        final Patient p = new Patient();
        p.setId(id);
        return p;
    }

    private JsonNode json(final String raw) {
        try {
            return objectMapper.readTree(raw);
        } catch (final Exception e) {
            throw new RuntimeException(e);
        }
    }

    // --- projector wiring in upsertAndEmit -------------------------------

    @Test
    void upsertAndEmit_invokesProjector_whenCanonicalIdsResolved() {
        final JsonNode obs = json("{\"resourceType\":\"Observation\",\"id\":\"obs-1\"}");

        service().upsertAndEmit(1L, 7L, 3L, "Observation", obs);

        verify(projector).project(eq(7L), eq(3L), eq("Observation"), any(JsonNode.class));
    }

    @Test
    void upsertAndEmit_skipsProjector_whenCanonicalIdsUnresolved() {
        final JsonNode obs = json("{\"resourceType\":\"Observation\",\"id\":\"obs-1\"}");

        service().upsertAndEmit(1L, null, null, "Observation", obs);

        verify(projector, never()).project(any(), any(), any(), any());
        verify(resourceRepo).save(any(EhrResource.class)); // interim mirror still written
    }

    // --- identity-sync wiring in the mirror path -------------------------

    @Test
    void syncNow_feedsPatientDemographicsIntoIdentitySync() {
        when(patientRepository.findByUserId(1L)).thenReturn(Optional.of(patientWithId(7L)));
        when(sourceResolver.idForCode(EpicProperties.SOURCE_EPIC)).thenReturn(3L);
        when(oauth.findCredential(1L)).thenReturn(Optional.empty());
        when(statusGate.isAllowed(any())).thenReturn(true);
        when(fhirClient.everything(1L)).thenReturn(List.of(
                json("{\"resourceType\":\"Patient\",\"id\":\"pat-1\","
                        + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"}}")));
        when(fhirClient.fetch(anyLong(), anyString(), anyMap())).thenReturn(List.<JsonNode>of());

        service().syncNow(1L, EpicSyncService.SyncMode.FULL);

        verify(identitySync).syncFromPatient(eq(7L), eq(3L), any(JsonNode.class));
    }

    @Test
    void syncNow_swallowsIdentityReconcileFailure() {
        when(patientRepository.findByUserId(1L)).thenReturn(Optional.of(patientWithId(7L)));
        when(sourceResolver.idForCode(EpicProperties.SOURCE_EPIC)).thenReturn(3L);
        when(oauth.findCredential(1L)).thenReturn(Optional.empty());
        when(statusGate.isAllowed(any())).thenReturn(true);
        when(fhirClient.everything(1L)).thenReturn(List.of(
                json("{\"resourceType\":\"Patient\",\"id\":\"pat-1\","
                        + "\"meta\":{\"lastUpdated\":\"2026-09-01T10:00:00Z\"}}")));
        when(fhirClient.fetch(anyLong(), anyString(), anyMap())).thenReturn(List.<JsonNode>of());
        doThrow(new RuntimeException("reconcile boom"))
                .when(identitySync).syncFromPatient(anyLong(), anyLong(), any());

        assertThatCode(() -> service().syncNow(1L, EpicSyncService.SyncMode.FULL))
                .doesNotThrowAnyException();
    }

    // --- disconnect cleanup ---------------------------------------------

    @Test
    void removeEpicData_cleansCanonicalLayer() {
        final EhrResource row = new EhrResource();
        row.setResourceType("Observation");
        row.setResourceFhirId("obs-1");
        when(resourceRepo.findByUserIdAndSource(1L, EpicProperties.SOURCE_EPIC))
                .thenReturn(List.of(row));
        when(patientRepository.findByUserId(1L)).thenReturn(Optional.of(patientWithId(7L)));
        when(sourceResolver.idForCode(EpicProperties.SOURCE_EPIC)).thenReturn(3L);

        service().removeEpicData(1L);

        verify(resourceRepo).deleteByUserIdAndSource(1L, EpicProperties.SOURCE_EPIC);
        verify(rawPayloadRepo).deleteByPatientIdAndSourceId(7L, 3L);
        verify(crosswalkRepo).deleteByPatientIdAndSourceId(7L, 3L);
        verify(projector).deleteAllForPatientAndSource(7L, 3L);
    }
}
