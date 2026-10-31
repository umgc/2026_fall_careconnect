package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerAllergyService.UnknownPatientException;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrAppointmentRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.model.ehr.EhrSourceIdentity;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrAppointmentRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerOAuthService.CernerReauthorizationRequiredException;
import com.careconnect.service.ehr.EhrAppointmentMapper;
import com.careconnect.service.ehr.EhrPatientIdentityMapper;
import com.fasterxml.jackson.databind.JsonNode;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Live Patient and provisional Appointment retrieval using the shared canonical EHR stores. */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class DefaultCernerPatientAppointmentService
        implements CernerPatientAppointmentService {

    private final PatientRepository patients;
    private final EhrSourceRepository sources;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrRawPayloadRepository rawPayloads;
    private final EhrSourceIdentityRepository identities;
    private final EhrAppointmentRecordRepository appointments;
    private final CernerOAuthService oauth;
    private final CernerFhirBundleHttpClient client;
    private final Clock clock;

    @Override
    @Transactional
    public EhrSourceIdentity synchronizePatient(final long patientId) {
        return synchronizePatientWithSourceRecord(patientId).identity();
    }

    @Override
    @Transactional
    public PatientSynchronization synchronizePatientWithSourceRecord(final long patientId) {
        final Context context = context(patientId);
        final JsonNode resource = fetchPatientWithRefresh(context);
        final EhrSourceIdentity incoming;
        try {
            incoming = EhrPatientIdentityMapper.map(
                    resource, patientId, context.source().getId());
        } catch (IllegalArgumentException error) {
            throw new CernerSourceException("CERNER_INVALID_RESPONSE", false);
        }
        final var existing = identities.findByPatientIdAndSourceId(
                patientId, context.source().getId());
        if (existing.isPresent()
                && !incoming.getSourceUpdatedAt().isAfter(existing.get().getSourceUpdatedAt())) {
            return new PatientSynchronization(context.externalPatientId(), existing.get());
        }
        storeRaw(patientId, context.source().getId(), "Patient", resource);
        existing.ifPresent(identity -> incoming.setId(identity.getId()));
        // Patient identity rows do not directly reference raw payloads; provenance remains in
        // ehr_raw_payload under the same patient/source/external-resource tuple.
        return new PatientSynchronization(
                context.externalPatientId(), identities.save(incoming));
    }

    @Override
    @Transactional
    public List<EhrAppointmentRecord> synchronizeAppointments(
            final long patientId,
            final Instant startInclusive,
            final Instant endExclusive) {

        final Context context = context(patientId);
        final List<JsonNode> resources = fetchAppointmentsWithRefresh(
                context, startInclusive, endExclusive);
        final List<EhrAppointmentRecord> result = new ArrayList<>();
        for (final JsonNode resource : resources) {
            final EhrAppointmentRecord incoming;
            try {
                incoming = EhrAppointmentMapper.map(
                        resource, context.patient(), context.source(), null);
            } catch (IllegalArgumentException error) {
                throw new CernerSourceException("CERNER_INVALID_RESPONSE", false);
            }
            final var existing = appointments
                    .findByPatientIdAndSourceIdAndExternalAppointmentId(
                            patientId,
                            context.source().getId(),
                            incoming.getExternalAppointmentId());
            if (existing.isPresent() && isOlderOrUnversioned(
                    existing.get().getSourceUpdatedAt(), incoming.getSourceUpdatedAt())) {
                result.add(existing.get());
                continue;
            }
            incoming.setRawPayload(storeRaw(
                    patientId, context.source().getId(), "Appointment", resource));
            existing.ifPresent(record -> incoming.setId(record.getId()));
            result.add(appointments.save(incoming));
        }
        return List.copyOf(result);
    }

    @Override
    public List<EhrAppointmentRecord> synchronizeAppointmentsWithTokenRefresh(long patientId, Instant startInclusive, Instant endExclusive) {
        return List.of();
    }

    @Override
    public List<EhrAppointmentRecord> synchronizeAppointmentsAllowingEmptyResults(long patientId, Instant startInclusive, Instant endExclusive) {
        return List.of();
    }

    @Override
    public List<EhrAppointmentRecord> synchronizeAppointmentsWithPaginationAndRateLimiting(long patientId, Instant startInclusive, Instant endExclusive) {
        return List.of();
    }

    @Override
    public List<EhrAppointmentRecord> synchronizeAppointmentsWithReferenceMismatchHandling(long patientId, Instant startInclusive, Instant endExclusive) {
        return List.of();
    }

    @Override
    public boolean validatePatientAndAppointmentExpectedOutputFixtures(long patientId, Instant startInclusive, Instant endExclusive) {
        return false;
    }

    private JsonNode fetchPatientWithRefresh(final Context context) {
        try {
            return client.getPatient(context.externalPatientId(), context.accessToken());
        } catch (CernerSourceException error) {
            if (!"CERNER_AUTH_EXPIRED".equals(error.code())) {
                throw error;
            }
            return client.getPatient(
                    context.externalPatientId(), refreshedToken(context.userId()));
        }
    }

    private List<JsonNode> fetchAppointmentsWithRefresh(
            final Context context,
            final Instant startInclusive,
            final Instant endExclusive) {
        try {
            return client.getAppointments(
                    context.externalPatientId(),
                    context.accessToken(),
                    startInclusive,
                    endExclusive).resources();
        } catch (CernerSourceException error) {
            if (!"CERNER_AUTH_EXPIRED".equals(error.code())) {
                throw error;
            }
            return client.getAppointments(
                    context.externalPatientId(),
                    refreshedToken(context.userId()),
                    startInclusive,
                    endExclusive).resources();
        }
    }

    private String refreshedToken(final Long userId) {
        try {
            return oauth.refreshAccessToken(userId);
        } catch (CernerReauthorizationRequiredException error) {
            throw new CernerSourceException("CERNER_AUTH_EXPIRED", false);
        }
    }

    private Context context(final long patientId) {
        final Patient patient = patients.findById(patientId)
                .orElseThrow(UnknownPatientException::new);
        if (patient.getUser() == null || patient.getUser().getId() == null) {
            throw new CernerSourceException("CERNER_NOT_CONNECTED", false);
        }
        final EhrSource source = sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)
                .orElseThrow(() -> new CernerSourceException("CERNER_NOT_CONFIGURED", false));
        final EhrPatientCrosswalk crosswalk = crosswalks
                .findByPatientIdAndSourceId(patientId, source.getId())
                .orElseThrow(() -> new CernerSourceException("CERNER_NOT_CONNECTED", false));
        final String externalPatientId = normalizedPatientId(crosswalk.getExternalPatientId());
        if (externalPatientId == null) {
            throw new CernerSourceException("CERNER_NOT_CONNECTED", false);
        }
        try {
            final Long userId = patient.getUser().getId();
            final String launchPatientId = normalizedPatientId(oauth.patientFhirId(userId));
            if (!externalPatientId.equals(launchPatientId)) {
                throw new CernerSourceException("CERNER_PATIENT_CONTEXT_MISMATCH", false);
            }
            return new Context(
                    userId, patient, source, externalPatientId, oauth.validAccessToken(userId));
        } catch (CernerReauthorizationRequiredException error) {
            throw new CernerSourceException("CERNER_AUTH_EXPIRED", false);
        }
    }

    private EhrRawPayload storeRaw(
            final Long patientId,
            final Long sourceId,
            final String resourceType,
            final JsonNode resource) {
        final String externalId = resource.path("id").asText();
        final String payload = resource.toString();
        final EhrRawPayload raw = rawPayloads
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        patientId, sourceId, resourceType, externalId)
                .orElseGet(EhrRawPayload::new);
        raw.setPatientId(patientId);
        raw.setSourceId(sourceId);
        raw.setResourceType(resourceType);
        raw.setExternalResourceId(externalId);
        raw.setPayload(payload);
        raw.setPayloadSizeBytes(payload.getBytes(StandardCharsets.UTF_8).length);
        raw.setPhotoStripped(false);
        raw.setRetrievedAt(OffsetDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
        return rawPayloads.save(raw);
    }

    private static boolean isOlderOrUnversioned(
            final LocalDateTime previous, final LocalDateTime incoming) {
        return previous != null && (incoming == null || incoming.isBefore(previous));
    }

    private static String normalizedPatientId(final String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.startsWith("Patient/") ? value.substring("Patient/".length()) : value;
    }

    private record Context(
            Long userId,
            Patient patient,
            EhrSource source,
            String externalPatientId,
            String accessToken) { }
}
