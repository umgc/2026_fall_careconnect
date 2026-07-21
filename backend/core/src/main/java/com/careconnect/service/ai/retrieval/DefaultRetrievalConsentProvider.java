package com.careconnect.service.ai.retrieval;

import com.careconnect.service.CaregiverPatientLinkService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Temporary consent gate until ConsentGrant persistence ships (Task 6.x).
 * Treats an active care-circle link as consent for {@code on_consent} visibility
 * so caregivers with valid patient access can retrieve summary/USPS chunks.
 */
@Component
@RequiredArgsConstructor
public class DefaultRetrievalConsentProvider implements RetrievalConsentProvider {

    private final CaregiverPatientLinkService caregiverPatientLinkService;

    @Override
    public boolean isCaregiverConsentGranted(
            final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        return caregiverPatientLinkService.hasAccessToPatient(
                caregiverUserId, patientUserId);
    }
}
