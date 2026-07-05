package com.careconnect.service.ai.retrieval;

import org.springframework.stereotype.Component;

/** Fail-closed consent provider until ConsentGrant persistence is implemented. */
@Component
public class DefaultRetrievalConsentProvider implements RetrievalConsentProvider {

    @Override
    public boolean isCaregiverConsentGranted(Long caregiverUserId, Long patientUserId) {
        return false;
    }
}
