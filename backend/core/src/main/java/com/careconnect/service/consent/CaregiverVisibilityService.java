package com.careconnect.service.consent;

/**
 * Contract for querying whether a caregiver is currently authorized to
 * view a specific patient's summary content. Backs the consent-based
 * access gate in {@code CallSummaryController} for summaries whose
 * {@code caregiverVisibility == 'on_consent'} (TC-E-SUM-009).
 *
 * <p>Two entry points:
 * <ul>
 *   <li>{@link #canViewSummaries(Long, Long)} — boolean-only check for
 *       callers that only need a yes/no decision.</li>
 *   <li>{@link #getStatus(Long, Long)} — richer variant returning both
 *       the current relationship {@link CaregiverVisibilityStatus} and
 *       the boolean decision, so callers can distinguish "not a
 *       caregiver at all" from "pending" or "revoked" for 403
 *       response bodies.</li>
 * </ul>
 *
 * <p>Real implementation ships in David's WBS 3.15.5 PR; until then a
 * permissive {@link NoOpCaregiverVisibilityService} default bean
 * allows access. When David's PR lands, his implementation replaces
 * the no-op via {@code @ConditionalOnMissingBean}.
 *
 * <p>Lookup key across both methods is the {@code (caregiverUserId,
 * patientUserId)} pair.
 */
public interface CaregiverVisibilityService {

    /**
     * Returns {@code true} when the given caregiver is currently
     * authorized to view summaries for the given patient. Equivalent
     * to {@code getStatus(caregiverUserId, patientUserId).canViewSummaries()}
     * for callers that don't need the status detail.
     *
     * @param caregiverUserId user identifier of the caregiver
     * @param patientUserId   user identifier of the patient
     * @return whether the caregiver may currently read summaries
     */
    boolean canViewSummaries(Long caregiverUserId, Long patientUserId);

    /**
     * Returns the full visibility check result for the given
     * (caregiver, patient) pair. Callers should prefer this method
     * when they need to distinguish an unregistered relationship
     * ({@code status == NONE}) from a registered-but-blocked one
     * ({@code PENDING_REVIEW} or {@code REVOKED}) — for example,
     * to decide whether the consent gate applies at all.
     *
     * @param caregiverUserId user identifier of the caregiver
     * @param patientUserId   user identifier of the patient
     * @return combined status + boolean decision
     */
    CaregiverVisibilityCheck getStatus(Long caregiverUserId, Long patientUserId);
}
