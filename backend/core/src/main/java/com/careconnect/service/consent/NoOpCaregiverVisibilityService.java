package com.careconnect.service.consent;

import org.springframework.stereotype.Service;

/**
 * Permissive default {@link CaregiverVisibilityService} that allows all
 * summary access until David's real WBS 3.15.5 implementation lands.
 * Remove or replace this class when the real service ships to avoid a
 * duplicate-bean conflict.
 *
 * <p>Behavior:
 * <ul>
 *   <li>{@link #canViewSummaries(Long, Long)} always returns {@code true}.</li>
 *   <li>{@link #getStatus(Long, Long)} always returns
 *       {@link CaregiverVisibilityCheck#none()} (status={@code NONE},
 *       canViewSummaries={@code true}).</li>
 * </ul>
 *
 * <p>The permissive default is deliberate: it prevents the on_consent
 * gate from blocking any user until real consent data is available.
 * The gate itself in {@code CallSummaryController} short-circuits when
 * {@code status == NONE}, so returning {@code NONE} here means the
 * no-op does not accidentally block otherwise-legitimate callers.
 *
 * <p>NOTE: {@code @ConditionalOnMissingBean} on a component-scanned
 * {@code @Service} is unreliable (Spring Boot evaluates it too early
 * during scan), so it is intentionally omitted here. Prefer a
 * {@code @Configuration @Bean} default if a conditional wire-up is
 * needed later.
 */
@Service
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
