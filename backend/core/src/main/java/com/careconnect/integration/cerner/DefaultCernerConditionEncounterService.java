package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.integration.cerner.CernerAllergyService.CernerSourceException;
import com.careconnect.integration.cerner.CernerAllergyService.UnknownPatientException;
import com.careconnect.integration.cerner.CernerFhirBundleHttpClient.ResourceType;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrConditionRecord;
import com.careconnect.model.ehr.EhrEncounterRecord;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrConditionRecordRepository;
import com.careconnect.repository.ehr.EhrEncounterRecordRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerOAuthService.CernerReauthorizationRequiredException;
import com.careconnect.service.ehr.EhrConditionMapper;
import com.careconnect.service.ehr.EhrEncounterMapper;
import com.fasterxml.jackson.databind.JsonNode;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Live Cerner Condition/Encounter retrieval, raw retention, mapping and idempotent upsert. */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class DefaultCernerConditionEncounterService implements CernerConditionEncounterService {

    private final PatientRepository patients;
    private final EhrSourceRepository sources;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrRawPayloadRepository rawPayloads;
    private final EhrConditionRecordRepository conditions;
    private final EhrEncounterRecordRepository encounters;
    private final CernerOAuthService oauth;
    private final CernerFhirBundleHttpClient client;
    private final Clock clock;

    @Override
    @Transactional
    public List<EhrConditionRecord> synchronizeConditions(final long patientId) {
        final Context context = context(patientId);
        final List<JsonNode> resources = fetchWithRefresh(ResourceType.CONDITION, context);
        final List<EhrConditionRecord> result = new ArrayList<>();
        for (final JsonNode resource : resources) {
            final EhrConditionRecord incoming = mapCondition(resource, patientId, context);
            final var existing = conditions.findByPatientIdAndSourceIdAndExternalConditionId(
                    patientId, context.sourceId(), incoming.getExternalConditionId());
            if (existing.isPresent() && isOlderOrUnversioned(
                    existing.get().getSourceUpdatedAt(), incoming.getSourceUpdatedAt())) {
                result.add(existing.get());
                continue;
            }
            final EhrRawPayload raw = storeRaw(patientId, context.sourceId(), "Condition", resource);
            incoming.setRawPayloadId(raw.getId());
            existing.ifPresent(record -> incoming.setId(record.getId()));
            result.add(conditions.save(incoming));
        }
        return List.copyOf(result);
    }

    @Override
    @Transactional
    public List<EhrEncounterRecord> synchronizeEncounters(final long patientId) {
        final Context context = context(patientId);
        final List<JsonNode> resources = fetchWithRefresh(ResourceType.ENCOUNTER, context);
        final List<EhrEncounterRecord> result = new ArrayList<>();
        for (final JsonNode resource : resources) {
            final EhrEncounterRecord incoming = mapEncounter(resource, patientId, context);
            final var existing = encounters.findByPatientIdAndSourceIdAndExternalEncounterId(
                    patientId, context.sourceId(), incoming.getExternalEncounterId());
            if (existing.isPresent() && isOlderOrUnversioned(
                    existing.get().getSourceUpdatedAt(), incoming.getSourceUpdatedAt())) {
                result.add(existing.get());
                continue;
            }
            final EhrRawPayload raw = storeRaw(patientId, context.sourceId(), "Encounter", resource);
            incoming.setRawPayloadId(raw.getId());
            existing.ifPresent(record -> incoming.setId(record.getId()));
            result.add(encounters.save(incoming));
        }
        return List.copyOf(result);
    }

    @SuppressWarnings("PMD.PreserveStackTrace")
    private static EhrConditionRecord mapCondition(
            final JsonNode resource, final long patientId, final Context context) {
        try {
            return EhrConditionMapper.map(
                    resource, patientId, context.sourceId(), null, context.externalPatientId());
        } catch (IllegalArgumentException error) {
            throw new CernerSourceException("CERNER_INVALID_RESPONSE", false);
        }
    }

    @SuppressWarnings("PMD.PreserveStackTrace")
    private static EhrEncounterRecord mapEncounter(
            final JsonNode resource, final long patientId, final Context context) {
        try {
            return EhrEncounterMapper.map(
                    resource, patientId, context.sourceId(), null, context.externalPatientId());
        } catch (IllegalArgumentException error) {
            throw new CernerSourceException("CERNER_INVALID_RESPONSE", false);
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
            return new Context(userId, source.getId(), externalPatientId,
                    oauth.validAccessToken(userId));
        } catch (CernerReauthorizationRequiredException error) {
            throw new CernerSourceException("CERNER_AUTH_EXPIRED", false);
        }
    }

    private List<JsonNode> fetchWithRefresh(final ResourceType type, final Context context) {
        try {
            return client.getResources(type, context.externalPatientId(), context.accessToken())
                    .resources();
        } catch (CernerSourceException error) {
            if (!"CERNER_AUTH_EXPIRED".equals(error.code())) {
                throw error;
            }
            try {
                final String refreshed = oauth.refreshAccessToken(context.userId());
                return client.getResources(type, context.externalPatientId(), refreshed).resources();
            } catch (CernerReauthorizationRequiredException refreshError) {
                throw new CernerSourceException("CERNER_AUTH_EXPIRED", false);
            }
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
            final java.time.Instant previous, final java.time.Instant incoming) {
        return previous != null && (incoming == null || incoming.isBefore(previous));
    }

    private static String normalizedPatientId(final String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.startsWith("Patient/") ? value.substring("Patient/".length()) : value;
    }

    private record Context(
            Long userId, Long sourceId, String externalPatientId, String accessToken) { }
}
