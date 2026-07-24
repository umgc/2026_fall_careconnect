package com.careconnect.service.ai.retrieval;

import com.careconnect.model.ConsentGrant;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ConsentService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Consent gate for {@code on_consent} visibility content (Task 2.4).
 *
 * <p>Prefers an explicit {@link ConsentGrant}. Care-circle link is used only as a migration
 * grandfather path when <em>no</em> grant history exists for the pair. Once any grant row
 * exists (including {@code REVOKED}), link fallback must not re-open access after revoke.
 */
@Component
@RequiredArgsConstructor
public class DefaultRetrievalConsentProvider implements RetrievalConsentProvider {

    private final ConsentService consentService;

    private final CaregiverPatientLinkService caregiverPatientLinkService;

    @Override
    public boolean isCaregiverConsentGranted(
            final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        if (consentService.isAiRetrievalConsentGranted(caregiverUserId, patientUserId)) {
            return true;
        }
        if (consentService.hasAnyAiRetrievalGrantHistory(caregiverUserId, patientUserId)) {
            return false;
        }
        return caregiverPatientLinkService.hasAccessToPatient(
                caregiverUserId, patientUserId);
    }
}
