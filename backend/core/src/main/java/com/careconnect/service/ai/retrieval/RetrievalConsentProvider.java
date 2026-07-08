package com.careconnect.service.ai.retrieval;

/** Supplies caregiver consent for on_consent visibility content (REQ-SC-8). */
public interface RetrievalConsentProvider {

    boolean isCaregiverConsentGranted(Long caregiverUserId, Long patientUserId);
}
