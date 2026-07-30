package com.careconnect.service.consent;

/**
 * Legacy permissive stub kept for reference/tests that explicitly construct it.
 * Production wiring uses {@link ConsentBackedCaregiverVisibilityService} ({@code @Primary}).
 *
 * <p>Do not add {@code @Service} here — that would reintroduce always-allow summary access.
 */
public class NoOpCaregiverVisibilityService implements CaregiverVisibilityService {

    @Override
    public boolean canViewSummaries(final Long caregiverUserId, final Long patientUserId) {
        return true;
    }

    @Override
    public CaregiverVisibilityCheck getStatus(final Long caregiverUserId, final Long patientUserId) {
        return CaregiverVisibilityCheck.none();
    }
}
