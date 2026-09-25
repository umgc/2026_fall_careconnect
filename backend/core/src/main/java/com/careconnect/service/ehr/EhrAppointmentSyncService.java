package com.careconnect.service.ehr;

import com.careconnect.client.ehr.EhrApiClient;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Fetches appointments through an {@link EhrApiClient} adapter and upserts them into
 * {@link EhrAppointmentRecord}, storing the raw FHIR resource behind each one first.
 *
 * <p>Requires an {@link EhrPatientCrosswalk} row for {@code (patient, source)} to already exist —
 * establishing that mapping (for example during account linking) happens elsewhere and is out of
 * scope here.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class EhrAppointmentSyncService {

    private static final String RESOURCE_TYPE_APPOINTMENT = "Appointment";

    private final EhrSourceRepository sourceRepository;
    private final EhrPatientCrosswalkRepository crosswalkRepository;
    private final EhrRawPayloadRepository rawPayloadRepository;
    private final EhrAppointmentRecordRepository appointmentRepository;
    private final ObjectMapper objectMapper;

    /** Fetches and upserts every appointment {@code apiClient} returns for {@code patient}. */
    @Transactional
    public List<EhrAppointmentRecord> sync(final Patient patient, final EhrApiClient apiClient) {
        final EhrSource source = sourceRepository.findByCode(apiClient.sourceCode())
                .orElseThrow(() -> new IllegalStateException(
                        "Unknown EHR source code: " + apiClient.sourceCode()));

        final EhrPatientCrosswalk crosswalk = crosswalkRepository
                .findByPatientIdAndSourceId(patient.getId(), source.getId())
                .orElseThrow(() -> new IllegalStateException(
                        "No crosswalk entry for patient " + patient.getId()
                                + " at source " + source.getCode()
                                + " — link the account before syncing"));

        final List<JsonNode> appointments = apiClient.fetchResources(
                RESOURCE_TYPE_APPOINTMENT, crosswalk.getExternalPatientId());
        log.info("[EHR sync] {} appointment(s) fetched for patient {} from {}",
                appointments.size(), patient.getId(), source.getCode());

        final LocalDateTime fetchedAt = LocalDateTime.now();
        final List<EhrAppointmentRecord> saved = new ArrayList<>();
        for (final JsonNode resource : appointments) {
            final EhrRawPayload rawPayload = storeRawPayload(patient, source, resource, fetchedAt);
            saved.add(upsertAppointment(patient, source, resource, rawPayload));
        }
        return saved;
    }

    private EhrAppointmentRecord upsertAppointment(
            final Patient patient,
            final EhrSource source,
            final JsonNode resource,
            final EhrRawPayload rawPayload) {
        final EhrAppointmentRecord mapped =
                EhrAppointmentMapper.map(resource, patient, source, rawPayload);

        appointmentRepository
                .findByPatientIdAndSourceIdAndExternalAppointmentId(
                        patient.getId(), source.getId(), mapped.getExternalAppointmentId())
                .ifPresent(existing -> mapped.setId(existing.getId()));

        return appointmentRepository.save(mapped);
    }

    private EhrRawPayload storeRawPayload(
            final Patient patient,
            final EhrSource source,
            final JsonNode resource,
            final LocalDateTime fetchedAt) {
        final String externalResourceId = resource.path("id").asText();
        final byte[] serialized = resource.toString().getBytes(StandardCharsets.UTF_8);

        final EhrRawPayload rawPayload = rawPayloadRepository
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        patient.getId(), source.getId(),
                        RESOURCE_TYPE_APPOINTMENT, externalResourceId)
                .orElseGet(EhrRawPayload::new);

        rawPayload.setPatient(patient);
        rawPayload.setSource(source);
        rawPayload.setResourceType(RESOURCE_TYPE_APPOINTMENT);
        rawPayload.setExternalResourceId(externalResourceId);
        rawPayload.setPayload(
                objectMapper.convertValue(resource, new TypeReference<Map<String, Object>>() { }));
        rawPayload.setPayloadSizeBytes(serialized.length);
        rawPayload.setFetchedAt(fetchedAt);

        return rawPayloadRepository.save(rawPayload);
    }
}
