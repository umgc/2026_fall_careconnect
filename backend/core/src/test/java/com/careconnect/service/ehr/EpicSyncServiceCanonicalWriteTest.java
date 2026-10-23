package com.careconnect.service.ehr;

import com.careconnect.config.EpicProperties;
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
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.ObjectProvider;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Verifies the canonical dual-write added for Phase-1 (Team E brief S2/S3): the crosswalk link on
 * connect and the {@code ehr_raw_payload} append per resource, including {@code Patient.photo}
 * stripping and the no-op when the canonical ids cannot be resolved.
 */
class EpicSyncServiceCanonicalWriteTest {

    private final EhrResourceRepository resourceRepo = mock(EhrResourceRepository.class);
    private final EhrStatusGate statusGate = mock(EhrStatusGate.class);
    private final PatientRepository patientRepository = mock(PatientRepository.class);
    private final EhrSourceResolver sourceResolver = mock(EhrSourceResolver.class);
    private final EhrPatientCrosswalkRepository crosswalkRepo = mock(EhrPatientCrosswalkRepository.class);
    private final EhrRawPayloadRepository rawPayloadRepo = mock(EhrRawPayloadRepository.class);
    private final ObjectMapper objectMapper = new ObjectMapper();

    @SuppressWarnings("unchecked")
    private EpicSyncService service() {
        when(resourceRepo.save(any(EhrResource.class))).thenAnswer(inv -> inv.getArgument(0));
        return new EpicSyncService(
                mock(EpicFhirClient.class),
                resourceRepo,
                statusGate,
                mock(EpicResourceChunker.class),
                mock(IndexingEventEmitter.class),
                mock(RetrievalIndexService.class),
                mock(EhrAuditService.class),
                objectMapper,
                mock(ObjectProvider.class),
                mock(EpicOAuthService.class),
                mock(EpicProperties.class),
                patientRepository,
                sourceResolver,
                crosswalkRepo,
                rawPayloadRepo);
    }

    private static Patient patientWithId(final long id) {
        final Patient p = new Patient();
        p.setId(id);
        return p;
    }

    @Test
    void linkPatientCrosswalk_insertsNewRowWithResolvedIds() {
        when(patientRepository.findByUserId(1L)).thenReturn(Optional.of(patientWithId(7L)));
        when(sourceResolver.idForCode(EpicProperties.SOURCE_EPIC)).thenReturn(3L);
        when(crosswalkRepo.findByPatientIdAndSourceId(7L, 3L)).thenReturn(Optional.empty());

        service().linkPatientCrosswalk(1L, "epic-patient-abc");

        final ArgumentCaptor<EhrPatientCrosswalk> saved = ArgumentCaptor.forClass(EhrPatientCrosswalk.class);
        verify(crosswalkRepo).save(saved.capture());
        assertThat(saved.getValue().getPatientId()).isEqualTo(7L);
        assertThat(saved.getValue().getSourceId()).isEqualTo(3L);
        assertThat(saved.getValue().getExternalPatientId()).isEqualTo("epic-patient-abc");
    }

    @Test
    void linkPatientCrosswalk_skipsWhenNoPatientRow() {
        when(patientRepository.findByUserId(1L)).thenReturn(Optional.empty());
        when(sourceResolver.idForCode(EpicProperties.SOURCE_EPIC)).thenReturn(3L);

        service().linkPatientCrosswalk(1L, "epic-patient-abc");

        verify(crosswalkRepo, never()).save(any());
    }

    @Test
    void upsertAndEmit_writesRawPayloadAndStripsPatientPhoto() throws Exception {
        when(resourceRepo.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                1L, EpicProperties.SOURCE_EPIC, "Patient", "pat-1"))
                .thenReturn(Optional.empty());
        final JsonNode patient = objectMapper.readTree(
                "{\"resourceType\":\"Patient\",\"id\":\"pat-1\","
                        + "\"photo\":[{\"data\":\"QUJD\"}],"
                        + "\"name\":[{\"family\":\"Doe\"}]}");

        service().upsertAndEmit(1L, 7L, 3L, "Patient", patient);

        final ArgumentCaptor<EhrRawPayload> saved = ArgumentCaptor.forClass(EhrRawPayload.class);
        verify(rawPayloadRepo).save(saved.capture());
        final EhrRawPayload row = saved.getValue();
        assertThat(row.getPatientId()).isEqualTo(7L);
        assertThat(row.getSourceId()).isEqualTo(3L);
        assertThat(row.getResourceType()).isEqualTo("Patient");
        assertThat(row.getExternalResourceId()).isEqualTo("pat-1");
        assertThat(row.getPhotoStripped()).isTrue();
        assertThat(row.getPayload()).doesNotContain("photo").contains("Doe");
    }

    @Test
    void upsertAndEmit_skipsRawPayloadWhenCanonicalIdsUnresolved() throws Exception {
        when(resourceRepo.findByUserIdAndSourceAndResourceTypeAndResourceFhirId(
                1L, EpicProperties.SOURCE_EPIC, "Observation", "obs-1"))
                .thenReturn(Optional.empty());
        final JsonNode obs = objectMapper.readTree(
                "{\"resourceType\":\"Observation\",\"id\":\"obs-1\"}");

        service().upsertAndEmit(1L, null, null, "Observation", obs);

        verify(rawPayloadRepo, never()).save(any());
        verify(resourceRepo).save(any(EhrResource.class)); // interim mirror still written
    }
}
