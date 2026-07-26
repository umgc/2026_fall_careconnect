package com.careconnect.service.consent;

import com.careconnect.model.Patient;
import com.careconnect.repository.PatientRepository;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ConsentService;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Service;

/**
 * ConsentGrant-backed {@link CaregiverVisibilityService} for summary {@code on_consent}
 * gates (TC-E-SUM-009). Aligns call-summary visibility with Ask AI effective retrieval
 * consent (explicit grant or care-circle grandfather until grant history exists).
 *
 * <p>Replaces the permissive {@link NoOpCaregiverVisibilityService} so demos no longer
 * treat all caregivers as consented for {@code on_consent} summaries.
 */
@Service
@Primary
@RequiredArgsConstructor
public class ConsentBackedCaregiverVisibilityService implements CaregiverVisibilityService {

    private final ConsentService consentService;
    private final CaregiverPatientLinkService caregiverPatientLinkService;
    private final PatientRepository patientRepository;

    @Override
    public boolean canViewSummaries(final Long caregiverUserId, final Long patientEntityId) {
        return getStatus(caregiverUserId, patientEntityId).canViewSummaries();
    }

    @Override
    public CaregiverVisibilityCheck getStatus(
            final Long caregiverUserId, final Long patientEntityId) {
        if (caregiverUserId == null || patientEntityId == null) {
            return CaregiverVisibilityCheck.none();
        }
        final Long patientUserId = resolvePatientUserId(patientEntityId);
        if (patientUserId == null) {
            return CaregiverVisibilityCheck.none();
        }
        if (!caregiverPatientLinkService.hasAccessToPatient(caregiverUserId, patientUserId)) {
            // No care-circle relationship — surrounding durable access checks apply alone.
            return CaregiverVisibilityCheck.none();
        }
        if (consentService.isEffectiveAiRetrievalConsent(caregiverUserId, patientUserId)) {
            return new CaregiverVisibilityCheck(CaregiverVisibilityStatus.GRANTED, true);
        }
        if (consentService.hasAnyAiRetrievalGrantHistory(caregiverUserId, patientUserId)) {
            return new CaregiverVisibilityCheck(CaregiverVisibilityStatus.REVOKED, false);
        }
        return new CaregiverVisibilityCheck(CaregiverVisibilityStatus.PENDING_REVIEW, false);
    }

    private Long resolvePatientUserId(final Long patientEntityId) {
        return patientRepository.findById(patientEntityId)
                .map(Patient::getUser)
                .map(user -> user == null ? null : user.getId())
                .orElse(null);
    }
}
