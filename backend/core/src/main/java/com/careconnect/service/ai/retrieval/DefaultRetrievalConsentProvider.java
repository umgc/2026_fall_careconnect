package com.careconnect.service.ai.retrieval;

import com.careconnect.service.ConsentService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Consent gate for {@code on_consent} visibility content (Task 2.4).
 *
 * <p>Delegates to {@link ConsentService#isEffectiveAiRetrievalConsent}, which prefers an
 * explicit {@link com.careconnect.model.ConsentGrant} and uses care-circle link only as a
 * migration grandfather path when no grant history exists.
 */
@Component
@RequiredArgsConstructor
public class DefaultRetrievalConsentProvider implements RetrievalConsentProvider {

    private final ConsentService consentService;

    @Override
    public boolean isCaregiverConsentGranted(
            final Long caregiverUserId, final Long patientUserId) {
        return consentService.isEffectiveAiRetrievalConsent(caregiverUserId, patientUserId);
    }
}
