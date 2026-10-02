package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
import com.careconnect.indexing.IndexingEventEmitter;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.service.ai.indexing.RetrievalIndexService;
import com.careconnect.service.ai.indexing.chunker.EpicResourceChunker;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.ObjectProvider;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyMap;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Verifies the DELTA sync path: typed fetches carry {@code _lastUpdated}, {@code $everything} and the
 * demographics read are skipped, and a missing watermark degrades to a FULL import.
 */
class EpicSyncServiceDeltaTest {

    @SuppressWarnings("unchecked")
    private EpicSyncService newService(EpicFhirClient fhirClient,
                                       EhrResourceRepository resourceRepo,
                                       EpicOAuthService oauth,
                                       EpicProperties epicProperties) {
        return new EpicSyncService(
                fhirClient,
                resourceRepo,
                mock(EhrStatusGate.class),
                mock(EpicResourceChunker.class),
                mock(IndexingEventEmitter.class),
                mock(RetrievalIndexService.class),
                mock(EhrAuditService.class),
                new ObjectMapper(),
                mock(ObjectProvider.class),
                oauth,
                epicProperties,
                mock(PatientRepository.class),
                mock(EhrSourceResolver.class),
                mock(EhrPatientCrosswalkRepository.class),
                mock(EhrRawPayloadRepository.class));
    }

    @Test
    void delta_withWatermark_filtersByLastUpdatedAndSkipsEverything() {
        EpicFhirClient fhirClient = mock(EpicFhirClient.class);
        EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
        EpicOAuthService oauth = mock(EpicOAuthService.class);
        EpicProperties epicProperties = mock(EpicProperties.class);

        when(oauth.findCredential(1L)).thenReturn(Optional.empty()); // no scope filtering
        when(resourceRepo.findMaxLastSyncedAt(1L, EpicProperties.SOURCE_EPIC))
                .thenReturn(Instant.parse("2026-09-01T00:00:00Z"));
        when(epicProperties.getDeltaSafetyMargin()).thenReturn(Duration.ofHours(24));
        when(fhirClient.fetch(anyLong(), anyString(), anyMap())).thenReturn(List.<JsonNode>of());

        EpicSyncService service = newService(fhirClient, resourceRepo, oauth, epicProperties);

        service.syncNow(1L, EpicSyncService.SyncMode.DELTA);

        // $everything and the demographics read must be skipped in DELTA.
        verify(fhirClient, never()).everything(anyLong());
        verify(fhirClient, never()).read(anyLong(), anyString(), anyString());

        // Every typed fetch carries a _lastUpdated=gt<watermark - 24h> filter.
        ArgumentCaptor<Map<String, String>> params = ArgumentCaptor.forClass(Map.class);
        verify(fhirClient, atLeastOnce()).fetch(eq(1L), anyString(), params.capture());
        assertTrue(params.getAllValues().stream().allMatch(p -> p.containsKey("_lastUpdated")),
                "every DELTA fetch should carry _lastUpdated");
        assertTrue(params.getAllValues().stream()
                        .allMatch(p -> p.get("_lastUpdated").startsWith("gt2026-08-31T")),
                "cursor should be the watermark back-dated by the 24h safety margin");
    }

    @Test
    void delta_withoutWatermark_fallsBackToFullAndCallsEverything() {
        EpicFhirClient fhirClient = mock(EpicFhirClient.class);
        EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
        EpicOAuthService oauth = mock(EpicOAuthService.class);
        EpicProperties epicProperties = mock(EpicProperties.class);

        when(oauth.findCredential(1L)).thenReturn(Optional.empty());
        when(oauth.patientFhirId(1L)).thenReturn(null); // skip the demographics read loop
        when(resourceRepo.findMaxLastSyncedAt(1L, EpicProperties.SOURCE_EPIC)).thenReturn(null);
        when(fhirClient.everything(1L)).thenReturn(List.<JsonNode>of());
        when(fhirClient.fetch(anyLong(), anyString(), anyMap())).thenReturn(List.<JsonNode>of());

        EpicSyncService service = newService(fhirClient, resourceRepo, oauth, epicProperties);

        service.syncNow(1L, EpicSyncService.SyncMode.DELTA);

        // No watermark → FULL import: $everything runs and typed fetches carry no _lastUpdated.
        verify(fhirClient).everything(1L);
        ArgumentCaptor<Map<String, String>> params = ArgumentCaptor.forClass(Map.class);
        verify(fhirClient, atLeastOnce()).fetch(eq(1L), anyString(), params.capture());
        assertTrue(params.getAllValues().stream().noneMatch(p -> p.containsKey("_lastUpdated")),
                "FULL fetches should not carry _lastUpdated");
    }
}
