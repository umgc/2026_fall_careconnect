package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.exception.*;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.*;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.*;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.EhrAppointmentMapper;
import com.careconnect.service.ehr.EhrPatientIdentityMapper;
import com.fasterxml.jackson.databind.JsonNode;
//import lombok.RequiredArgsConstructor;
import org.springframework.beans.BeanWrapper;
import org.springframework.beans.BeanWrapperImpl;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

@Service
//@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerPatientAppointmentServiceImpl implements CernerPatientAppointmentService {

    private final PatientRepository patients;
    private final EhrSourceRepository sources;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrRawPayloadRepository rawPayloads;
    private final EhrSourceIdentityRepository identities;
    private final EhrAppointmentRecordRepository appointments;
    private final CernerOAuthService oauth;
    private final CernerFhirBundleHttpClient client;
    private final Clock clock;

    public CernerPatientAppointmentServiceImpl(PatientRepository patients, EhrSourceRepository sources, EhrPatientCrosswalkRepository crosswalks, EhrRawPayloadRepository rawPayloads, EhrSourceIdentityRepository identities, EhrAppointmentRecordRepository appointments, CernerOAuthService oauth, CernerFhirBundleHttpClient client, Clock clock) {
        this.patients = patients;
        this.sources = sources;
        this.crosswalks = crosswalks;
        this.rawPayloads = rawPayloads;
        this.identities = identities;
        this.appointments = appointments;
        this.oauth = oauth;
        this.client = client;
        this.clock = clock;
    }

    @Override
    @Transactional
    public EhrSourceIdentity synchronizePatient(long patientId) {
        return synchronizePatientWithSourceRecord(patientId).identity();
    }

    @Override
    @Transactional
    public PatientSynchronization synchronizePatientWithSourceRecord(long patientId) {
        final Context context = context(patientId);
        final JsonNode resource = fetchPatientWithRefresh(context);

        final EhrSourceIdentity incoming;
        try {
            incoming = EhrPatientIdentityMapper.map(resource, patientId, sourceId(context.source()));
        } catch (IllegalArgumentException error) {
            throw new CernerAllergyService.CernerSourceException("CERNER_INVALID_RESPONSE", false);
        }

        final var existing = identities.findByPatientIdAndSourceId(patientId, sourceId(context.source()));

        if (existing.isPresent()
                && (incoming.getSourceUpdatedAt() == null
                || existing.get().getSourceUpdatedAt() != null
                && !incoming.getSourceUpdatedAt().isAfter(existing.get().getSourceUpdatedAt()))) {
            return new PatientSynchronization(context.externalPatientId(), existing.get());
        }

        storeRaw(patientId, sourceId(context.source()), "Patient", resource);
        existing.ifPresent(identity -> writeLong(incoming, "id", readLong(identity, "id")));

        return new PatientSynchronization(context.externalPatientId(), identities.save(incoming));
    }

    @Override
    @Transactional
    public List<EhrAppointmentRecord> synchronizeAppointments(long patientId, Instant startInclusive, Instant endExclusive) {
        final Context context = context(patientId);
        final List<JsonNode> resources = fetchAppointmentsWithRefresh(context, startInclusive, endExclusive);
        if (resources == null || resources.isEmpty()) return List.of();

        final List<EhrAppointmentRecord> result = new ArrayList<>();
        for (final JsonNode resource : resources) {
            if (resource == null || resource.isMissingNode()) continue;

            final EhrAppointmentRecord incoming;
            try {
                incoming = EhrAppointmentMapper.map(resource, context.patient(), context.source(), null);
            } catch (IllegalArgumentException error) {
                throw new CernerAllergyService.CernerSourceException("CERNER_INVALID_RESPONSE", false);
            }

            final var existing = appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                    patientId, sourceId(context.source()), externalAppointmentId(incoming));

            if (existing.isPresent() && isOlderOrUnversioned(
                    sourceUpdatedAt(existing.get()), sourceUpdatedAt(incoming))) {
                result.add(existing.get());
                continue;
            }

            writeRawPayload(incoming, storeRaw(patientId, sourceId(context.source()), "Appointment", resource));
            existing.ifPresent(record -> writeLong(incoming, "id", readLong(record, "id")));
            result.add(appointments.save(incoming));
        }
        return List.copyOf(result);
    }


    @Override
    @Transactional
    public List<EhrAppointmentRecord> synchronizeAppointmentsWithTokenRefresh(
            long patientId,
            Instant startInclusive,
            Instant endExclusive
    ) {
        final Context context = context(patientId);
        List<JsonNode> resources;

        try {
            resources = client
                    .getAppointments(context.externalPatientId(), context.accessToken(), startInclusive, endExclusive)
                    .resources();
        } catch (CernerAllergyService.CernerSourceException error) {
            if (!"CERNER_AUTH_EXPIRED".equals(error.code())) {
                throw error;
            }
            final String refreshedAccessToken = refreshedToken(context.userId());
            resources = client
                    .getAppointments(context.externalPatientId(), refreshedAccessToken, startInclusive, endExclusive)
                    .resources();
        }

        if (resources == null || resources.isEmpty()) {
            return List.of();
        }

        final List<EhrAppointmentRecord> result = new ArrayList<>();
        for (final JsonNode resource : resources) {
            if (resource == null || resource.isMissingNode()) continue;

            final EhrAppointmentRecord incoming;
            try {
                incoming = EhrAppointmentMapper.map(resource, context.patient(), context.source(), null);
            } catch (IllegalArgumentException error) {
                throw new CernerAllergyService.CernerSourceException("CERNER_INVALID_RESPONSE", false);
            }

            final var existing = appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                    patientId, sourceId(context.source()), externalAppointmentId(incoming));

            if (existing.isPresent() && isOlderOrUnversioned(
                    sourceUpdatedAt(existing.get()), sourceUpdatedAt(incoming))) {
                result.add(existing.get());
                continue;
            }

            writeRawPayload(incoming, storeRaw(patientId, sourceId(context.source()), "Appointment", resource));
            existing.ifPresent(record -> writeLong(incoming, "id", readLong(record, "id")));
            result.add(appointments.save(incoming));
        }

        return List.copyOf(result);
    }

    @Override
    @Transactional
    public List<EhrAppointmentRecord> synchronizeAppointmentsAllowingEmptyResults(
            long patientId,
            Instant startInclusive,
            Instant endExclusive
    ) {
        final List<EhrAppointmentRecord> records = synchronizeAppointments(patientId, startInclusive, endExclusive);
        if (records == null || records.isEmpty()) {
            return List.of();
        }
        return List.copyOf(records);
    }


    @Override
    @Transactional
    public List<EhrAppointmentRecord> synchronizeAppointmentsWithPaginationAndRateLimiting(
            long patientId,
            Instant startInclusive,
            Instant endExclusive
    ) {
        final Context context = context(patientId);
        final List<EhrAppointmentRecord> result = new ArrayList<>();

        final int maxPages = 100;
        final int maxRetriesPerPage = 3;
        final long baseBackoffMillis = 500L;

        String accessToken = context.accessToken();
        int pageCount = 0;

        while (pageCount < maxPages) {
            List<JsonNode> resources;
            int attempt = 0;

            while (true) {
                try {
                    resources = client.getAppointments(
                            context.externalPatientId(),
                            accessToken,
                            startInclusive,
                            endExclusive
                    ).resources();
                    break;
                } catch (CernerAllergyService.CernerSourceException error) {
                    final String code = error.code();

                    if ("CERNER_AUTH_EXPIRED".equals(code)) {
                        accessToken = refreshedToken(context.userId());
                        attempt++;
                    } else if ("CERNER_RATE_LIMITED".equals(code) || "CERNER_TOO_MANY_REQUESTS".equals(code)) {
                        attempt++;
                        if (attempt > maxRetriesPerPage) {
                            throw error;
                        }
                        final long sleepMillis = baseBackoffMillis * (1L << Math.min(attempt - 1, 5));
                        try {
                            Thread.sleep(sleepMillis);
                        } catch (InterruptedException interrupted) {
                            Thread.currentThread().interrupt();
                            throw new CernerAllergyService.CernerSourceException("CERNER_INTERRUPTED", false);
                        }
                    } else {
                        throw error;
                    }

                    if (attempt > maxRetriesPerPage) {
                        throw error;
                    }
                }
            }

            if (resources != null && !resources.isEmpty()) {
                for (final JsonNode resource : resources) {
                    if (resource == null || resource.isMissingNode()) continue;

                    final EhrAppointmentRecord incoming;
                    try {
                        incoming = EhrAppointmentMapper.map(resource, context.patient(), context.source(), null);
                    } catch (IllegalArgumentException error) {
                        throw new CernerAllergyService.CernerSourceException("CERNER_INVALID_RESPONSE", false);
                    }

                    final var existing = appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                            patientId, sourceId(context.source()), externalAppointmentId(incoming));

                    if (existing.isPresent() && isOlderOrUnversioned(
                            sourceUpdatedAt(existing.get()), sourceUpdatedAt(incoming))) {
                        result.add(existing.get());
                        continue;
                    }

                    writeRawPayload(incoming, storeRaw(patientId, sourceId(context.source()), "Appointment", resource));
                    existing.ifPresent(record -> writeLong(incoming, "id", readLong(record, "id")));
                    result.add(appointments.save(incoming));
                }
            }

            pageCount++;
            break;
        }

        return List.copyOf(result);
    }


    @Override
    @Transactional
    public List<EhrAppointmentRecord> synchronizeAppointmentsWithReferenceMismatchHandling(
            long patientId,
            Instant startInclusive,
            Instant endExclusive
    ) {
        final Context context = context(patientId);
        final List<JsonNode> resources = fetchAppointmentsWithRefresh(context, startInclusive, endExclusive);
        if (resources == null || resources.isEmpty()) return List.of();

        final List<EhrAppointmentRecord> result = new ArrayList<>();
        final String expectedPatientId = context.externalPatientId();
        final String expectedPatientRef = "Patient/" + expectedPatientId;

        for (final JsonNode resource : resources) {
            if (resource == null || resource.isMissingNode()) continue;

            final JsonNode participants = resource.path("participant");
            if (participants.isArray() && participants.size() > 0) {
                boolean hasMatchingReference = false;

                for (final JsonNode participant : participants) {
                    final String actorRef = participant.path("actor").path("reference").asText(null);
                    if (actorRef == null || actorRef.isBlank()) continue;

                    final String normalizedActorRef = normalizedPatientId(actorRef);
                    if (expectedPatientId.equals(normalizedActorRef) || expectedPatientRef.equals(actorRef)) {
                        hasMatchingReference = true;
                        break;
                    }
                }

                if (!hasMatchingReference) {
                    continue;
                }
            }

            final EhrAppointmentRecord incoming;
            try {
                incoming = EhrAppointmentMapper.map(resource, context.patient(), context.source(), null);
            } catch (IllegalArgumentException error) {
                throw new CernerAllergyService.CernerSourceException("CERNER_INVALID_RESPONSE", false);
            }

            final var existing = appointments.findByPatientIdAndSourceIdAndExternalAppointmentId(
                    patientId, sourceId(context.source()), externalAppointmentId(incoming));

            if (existing.isPresent() && isOlderOrUnversioned(
                    sourceUpdatedAt(existing.get()), sourceUpdatedAt(incoming))) {
                result.add(existing.get());
                continue;
            }

            writeRawPayload(incoming, storeRaw(patientId, sourceId(context.source()), "Appointment", resource));
            existing.ifPresent(record -> writeLong(incoming, "id", readLong(record, "id")));
            result.add(appointments.save(incoming));
        }

        return List.copyOf(result);
    }

    @Override
    public boolean validatePatientAndAppointmentExpectedOutputFixtures(long patientId, Instant startInclusive, Instant endExclusive) {
        try {
            final Context context = context(patientId);

            final JsonNode patientResource = fetchPatientWithRefresh(context);
            if (patientResource == null || patientResource.isMissingNode()) {
                return false;
            }

            final EhrSourceIdentity mappedIdentity = EhrPatientIdentityMapper.map(
                    patientResource,
                    patientId,
                    sourceId(context.source())
            );
            if (mappedIdentity == null) {
                return false;
            }

            final String mappedExternalPatientId = normalizedPatientId(readString(mappedIdentity, "externalPatientId"));
            if (mappedExternalPatientId == null || !mappedExternalPatientId.equals(context.externalPatientId())) {
                return false;
            }

            final List<JsonNode> appointmentResources = fetchAppointmentsWithRefresh(context, startInclusive, endExclusive);
            if (appointmentResources == null) {
                return false;
            }

            for (final JsonNode resource : appointmentResources) {
                if (resource == null || resource.isMissingNode()) {
                    return false;
                }

                final EhrAppointmentRecord mappedAppointment = EhrAppointmentMapper.map(
                        resource,
                        context.patient(),
                        context.source(),
                        null
                );

                if (mappedAppointment == null) {
                    return false;
                }

                final String externalAppointmentId = externalAppointmentId(mappedAppointment);
                if (externalAppointmentId == null || externalAppointmentId.isBlank()) {
                    return false;
                }
            }

            return true;
        } catch (IllegalArgumentException | CernerAllergyService.CernerSourceException error) {
            return false;
        }
    }


    private JsonNode fetchPatientWithRefresh(final Context context) {
        try {
            return client.getPatient(context.externalPatientId(), context.accessToken());
        } catch (CernerAllergyService.CernerSourceException error) {
            if (!"CERNER_AUTH_EXPIRED".equals(error.code())) throw error;
            return client.getPatient(context.externalPatientId(), refreshedToken(context.userId()));
        }
    }

    private List<JsonNode> fetchAppointmentsWithRefresh(final Context context, final Instant startInclusive, final Instant endExclusive) {
        try {
            return client.getAppointments(context.externalPatientId(), context.accessToken(), startInclusive, endExclusive).resources();
        } catch (CernerAllergyService.CernerSourceException error) {
            if (!"CERNER_AUTH_EXPIRED".equals(error.code())) throw error;
            return client.getAppointments(context.externalPatientId(), refreshedToken(context.userId()), startInclusive, endExclusive).resources();
        }
    }

    private String refreshedToken(final Long userId) {
        try {
            return oauth.refreshAccessToken(userId);
        } catch (CernerOAuthService.CernerReauthorizationRequiredException error) {
            throw new CernerAllergyService.CernerSourceException("CERNER_AUTH_EXPIRED", false);
        }
    }

    private Context context(final long patientId) {
        final Patient patient = patients.findById(patientId).orElseThrow(UnknownPatientException::new);
        if (patient.getUser() == null || patient.getUser().getId() == null) {
            throw new CernerAllergyService.CernerSourceException("CERNER_NOT_CONNECTED", false);
        }

        final EhrSource source = sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)
                .orElseThrow(() -> new CernerAllergyService.CernerSourceException("CERNER_NOT_CONFIGURED", false));

        final EhrPatientCrosswalk crosswalk = crosswalks
                .findByPatientIdAndSourceId(patientId, sourceId(source))
                .orElseThrow(() -> new CernerAllergyService.CernerSourceException("CERNER_NOT_CONNECTED", false));

        final String externalPatientId = normalizedPatientId(crosswalk.getExternalPatientId());
        if (externalPatientId == null) {
            throw new CernerAllergyService.CernerSourceException("CERNER_NOT_CONNECTED", false);
        }

        try {
            final Long userId = patient.getUser().getId();
            final String launchPatientId = normalizedPatientId(oauth.patientFhirId(userId));
            if (!externalPatientId.equals(launchPatientId)) {
                throw new CernerAllergyService.CernerSourceException("CERNER_PATIENT_CONTEXT_MISMATCH", false);
            }
            return new Context(userId, patient, source, externalPatientId, oauth.validAccessToken(userId));
        } catch (CernerOAuthService.CernerReauthorizationRequiredException error) {
            throw new CernerAllergyService.CernerSourceException("CERNER_AUTH_EXPIRED", false);
        }
    }

    private EhrRawPayload storeRaw(Long patientId, Long sourceId, String resourceType, JsonNode resource) {
        final String externalId = resource.path("id").asText();
        final String payload = resource.toString();

        final EhrRawPayload raw = rawPayloads
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(patientId, sourceId, resourceType, externalId)
                .orElseGet(EhrRawPayload::new);

//        raw.setPatientId(patientId);
//        raw.setSourceId(sourceId);
//        raw.setResourceType(resourceType);
//        raw.setExternalResourceId(externalId);
//        raw.setPayload(payload);
//        raw.setPayloadSizeBytes(payload.getBytes(StandardCharsets.UTF_8).length);
//        raw.setPhotoStripped(false);
//        raw.setRetrievedAt(OffsetDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
        set(raw, "patientId", patientId);
        set(raw, "sourceId", sourceId);
        set(raw, "resourceType", resourceType);
        set(raw, "externalResourceId", externalId);
        set(raw, "payload", payload);
        set(raw, "payloadSizeBytes", payload.getBytes(StandardCharsets.UTF_8).length);
        set(raw, "photoStripped", false);
        set(raw, "retrievedAt", OffsetDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
        return rawPayloads.save(raw);
    }

    private static boolean isOlderOrUnversioned(LocalDateTime previous, LocalDateTime incoming) {
        return previous != null && (incoming == null || incoming.isBefore(previous));
    }

    private static boolean isAfter(LocalDateTime left, LocalDateTime right) {
        return left != null && (right == null || left.isAfter(right));
    }

    private static String normalizedPatientId(final String value) {
        if (value == null || value.isBlank()) return null;
        return value.startsWith("Patient/") ? value.substring("Patient/".length()) : value;
    }

    private static Long sourceId(EhrSource source) {
        return readLong(source, "id");
    }

    private static LocalDateTime sourceUpdatedAt(Object bean) {
        return readLocalDateTime(bean, "sourceUpdatedAt");
    }

    private static String externalAppointmentId(EhrAppointmentRecord record) {
        return readString(record, "externalAppointmentId");
    }

    private static void writeRawPayload(EhrAppointmentRecord record, EhrRawPayload payload) {
        set(record, "rawPayload", payload);
    }

    private static Long readLong(Object bean, String field) {
        Object v = get(bean, field);
        return v instanceof Number n ? n.longValue() : (Long) v;
    }

    private static String readString(Object bean, String field) {
        Object v = get(bean, field);
        return v == null ? null : v.toString();
    }

    private static LocalDateTime readLocalDateTime(Object bean, String field) {
        Object v = get(bean, field);
        return (v instanceof LocalDateTime ldt) ? ldt : null;
    }

    private static Object get(Object bean, String field) {
        BeanWrapper w = new BeanWrapperImpl(bean);
        return w.isReadableProperty(field) ? w.getPropertyValue(field) : null;
    }

    private static void writeLong(Object bean, String field, Long value) {
        set(bean, field, value);
    }

    private static void set(Object bean, String field, Object value) {
        BeanWrapper w = new BeanWrapperImpl(bean);
        if (w.isWritableProperty(field)) {
            w.setPropertyValue(field, value);
        }
    }

    private record Context(Long userId, Patient patient, EhrSource source, String externalPatientId, String accessToken) {}
}
