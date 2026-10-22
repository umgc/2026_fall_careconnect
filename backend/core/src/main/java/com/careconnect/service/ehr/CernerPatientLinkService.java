package com.careconnect.service.ehr;

import com.careconnect.config.CernerProperties;
import com.careconnect.model.Patient;
import com.careconnect.model.ehr.EhrPatientCrosswalk;
import com.careconnect.model.ehr.EhrSource;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ehr.EhrPatientCrosswalkRepository;
import com.careconnect.repository.ehr.EhrSourceRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Persists the authenticated SMART patient context in the canonical patient crosswalk. */
@Service
@RequiredArgsConstructor
@ConditionalOnProperty(name = "careconnect.cerner.enabled", havingValue = "true")
public class CernerPatientLinkService {

    private final PatientRepository patients;
    private final EhrSourceRepository sources;
    private final EhrPatientCrosswalkRepository crosswalks;

    @Transactional
    public EhrPatientCrosswalk link(final Long userId, final String smartPatientId) {
        String externalPatientId = normalize(smartPatientId);
        if (externalPatientId == null || !externalPatientId.matches("[A-Za-z0-9.-]{1,255}")) {
            throw new IllegalArgumentException("Invalid Oracle Health patient context");
        }
        Patient patient = patients.findByUserId(userId)
                .orElseThrow(() -> new IllegalStateException("No patient belongs to the connecting user"));
        EhrSource source = sources.findByCode(CernerProperties.SOURCE_ORACLE_HEALTH)
                .orElseThrow(() -> new IllegalStateException("ORACLE_HEALTH source is not seeded"));

        crosswalks.findBySourceIdAndExternalPatientId(source.getId(), externalPatientId)
                .filter(existing -> !existing.getPatientId().equals(patient.getId()))
                .ifPresent(existing -> {
                    throw new IllegalStateException("Oracle Health patient is linked to another patient");
                });

        EhrPatientCrosswalk crosswalk = crosswalks
                .findByPatientIdAndSourceId(patient.getId(), source.getId())
                .orElseGet(EhrPatientCrosswalk::new);
        crosswalk.setPatientId(patient.getId());
        crosswalk.setSourceId(source.getId());
        crosswalk.setExternalPatientId(externalPatientId);
        return crosswalks.save(crosswalk);
    }

    private static String normalize(final String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.startsWith("Patient/") ? value.substring("Patient/".length()) : value;
    }
}
