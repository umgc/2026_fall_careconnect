package com.careconnect.service.consent;

import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.stereotype.Service;

/**
 * Permissive default {@link CaregiverVisibilityService} that allows all
 * summary access. Wired only when no other {@code CaregiverVisibilityService}
 * bean is available — David's real implementation from WBS 3.15.5
 * automatically wins via {@code @ConditionalOnMissingBean} when his PR
 * lands.
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
 */
@Service
@ConditionalOnMissingBean(CaregiverVisibilityService.class)
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
