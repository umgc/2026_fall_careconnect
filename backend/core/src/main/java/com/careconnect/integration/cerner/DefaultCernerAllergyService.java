package com.careconnect.integration.cerner;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrRawPayload;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import com.careconnect.service.ehr.CernerOAuthService;
import com.careconnect.service.ehr.CernerOAuthService.CernerReauthorizationRequiredException;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;

/** Live read-only allergy workflow joining patient, crosswalk, OAuth, HTTP, and mapping layers. */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class DefaultCernerAllergyService implements CernerAllergyService {

    private final PatientRepository patients;
    private final EhrSourceRepository sources;
    private final EhrPatientCrosswalkRepository crosswalks;
    private final EhrRawPayloadRepository rawPayloads;
    private final CernerOAuthService oauth;
    private final CernerAllergyHttpClient client;
    private final Clock clock;

    @Override
    @Transactional
    public List<CernerAllergyMapper.Allergy> getAllergies(final long patientId) {
        Patient patient = patients.findById(patientId).orElseThrow(UnknownPatientException::new);
        if (patient.getUser() == null || patient.getUser().getId() == null) {
            throw new CernerSourceException("CERNER_NOT_CONNECTED", false);
        }
        EhrSource source = sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)
                .orElseThrow(() -> new CernerSourceException("CERNER_NOT_CONFIGURED", false));
        EhrPatientCrosswalk crosswalk = crosswalks
                .findByPatientIdAndSourceId(patientId, source.getId())
                .orElseThrow(() -> new CernerSourceException("CERNER_NOT_CONNECTED", false));
        String externalPatientId = normalizedPatientId(crosswalk.getExternalPatientId());
        if (externalPatientId == null) {
            throw new CernerSourceException("CERNER_NOT_CONNECTED", false);
        }
        try {
            String launchPatientId = normalizedPatientId(oauth.patientFhirId(patient.getUser().getId()));
            if (!externalPatientId.equals(launchPatientId)) {
                throw new CernerSourceException("CERNER_PATIENT_CONTEXT_MISMATCH", false);
            }
            Long userId = patient.getUser().getId();
            CernerAllergyHttpClient.Result result = fetchWithRefresh(
                    externalPatientId, userId, oauth.validAccessToken(userId));
            result.rawResources().forEach(resource -> storeRaw(patientId, source.getId(), resource));
            return result.allergies();
        } catch (CernerReauthorizationRequiredException exception) {
            throw new CernerSourceException("CERNER_AUTH_EXPIRED", false);
        }
    }

    private CernerAllergyHttpClient.Result fetchWithRefresh(
            final String externalPatientId, final Long userId, final String accessToken) {
        try {
            return client.getAllergyResult(externalPatientId, accessToken);
        } catch (CernerSourceException exception) {
            if (!"CERNER_AUTH_EXPIRED".equals(exception.code())) {
                throw exception;
            }
            return client.getAllergyResult(externalPatientId, oauth.refreshAccessToken(userId));
        }
    }

    private void storeRaw(
            final Long patientId, final Long sourceId, final JsonNode resource) {
        String externalId = resource.path("id").asText();
        String payload = resource.toString();
        EhrRawPayload raw = rawPayloads
                .findByPatientIdAndSourceIdAndResourceTypeAndExternalResourceId(
                        patientId, sourceId, "AllergyIntolerance", externalId)
                .orElseGet(EhrRawPayload::new);
        raw.setPatientId(patientId);
        raw.setSourceId(sourceId);
        raw.setResourceType("AllergyIntolerance");
        raw.setExternalResourceId(externalId);
        raw.setPayload(payload);
        raw.setPayloadSizeBytes(payload.getBytes(StandardCharsets.UTF_8).length);
        raw.setPhotoStripped(false);
        raw.setRetrievedAt(OffsetDateTime.ofInstant(clock.instant(), ZoneOffset.UTC));
        rawPayloads.save(raw);
    }

    private static String normalizedPatientId(final String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.startsWith("Patient/") ? value.substring("Patient/".length()) : value;
    }
}
