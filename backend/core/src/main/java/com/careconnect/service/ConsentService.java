package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.ConsentGrant;
import com.careconnect.repository.ConsentGrantRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Manages scoped patient consent grants (Task 2.4), starting with
 * {@link ConsentGrant#SCOPE_AI_RETRIEVAL} for Ask AI on_consent content.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ConsentService {

    private final ConsentGrantRepository consentGrantRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;

    /**
     * Returns whether the caregiver currently holds an active AI-retrieval consent grant
     * for the given patient.
     *
     * @param caregiverUserId user identifier of the prospective grantee
     * @param patientUserId user identifier of the patient granting consent
     * @return true when an active, non-expired grant exists
     */
    @Transactional(readOnly = true)
    public boolean isAiRetrievalConsentGranted(
            final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        return consentGrantRepository.existsActiveGrant(
                patientUserId, caregiverUserId, ConsentGrant.SCOPE_AI_RETRIEVAL, Instant.now());
    }

    /**
     * Returns whether any AI-retrieval grant history exists for the patient/grantee pair
     * (including revoked or expired rows). Once history exists, care-circle link fallback
     * must not re-open {@code on_consent} retrieval after an explicit revoke.
     *
     * @param caregiverUserId grantee user id
     * @param patientUserId patient user id
     * @return true when at least one grant row exists for the AI_RETRIEVAL scope
     */
    @Transactional(readOnly = true)
    public boolean hasAnyAiRetrievalGrantHistory(
            final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        return consentGrantRepository.existsByPatientUserIdAndGranteeUserIdAndScope(
                patientUserId, caregiverUserId, ConsentGrant.SCOPE_AI_RETRIEVAL);
    }

    /**
     * Returns whether Ask AI retrieval consent is effectively granted for the pair —
     * an active explicit grant, or (when no grant history exists) an active care-circle
     * link. Matches {@link com.careconnect.service.ai.retrieval.DefaultRetrievalConsentProvider}.
     *
     * @param caregiverUserId grantee user id
     * @param patientUserId patient user id
     * @return true when Ask AI may treat {@code on_consent} content as consented
     */
    @Transactional(readOnly = true)
    public boolean isEffectiveAiRetrievalConsent(
            final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        if (isAiRetrievalConsentGranted(caregiverUserId, patientUserId)) {
            return true;
        }
        if (hasAnyAiRetrievalGrantHistory(caregiverUserId, patientUserId)) {
            return false;
        }
        return caregiverPatientLinkService.hasAccessToPatient(caregiverUserId, patientUserId);
    }

    /**
     * Grants AI-retrieval consent from a patient to a grantee (typically a caregiver).
     *
     * <p>If an ACTIVE grant already exists for the tuple, it is refreshed in place (and any
     * duplicate ACTIVE rows are revoked) so callers cannot accumulate multiple live grants.
     *
     * @param patientUserId user identifier of the patient granting consent
     * @param granteeUserId user identifier of the grantee
     * @param granteeRole role of the grantee (e.g. {@code CAREGIVER})
     * @param expiresAt optional expiry instant; null means no expiry
     * @return the persisted grant
     */
    @Transactional
    public ConsentGrant grantAiRetrievalConsent(
            final Long patientUserId,
            final Long granteeUserId,
            final String granteeRole,
            final Instant expiresAt) {
        if (patientUserId == null || granteeUserId == null) {
            throw new IllegalArgumentException("patientUserId and granteeUserId are required");
        }
        // Prevent orphan grants to users outside the patient's care circle. Ask still
        // enforces assertCanAsk, but grants should not accumulate without a live link.
        if (!caregiverPatientLinkService.hasAccessToPatient(granteeUserId, patientUserId)) {
            throw new AppException(
                    HttpStatus.BAD_REQUEST,
                    "No active caregiver relationship with this patient");
        }
        final Instant now = Instant.now();
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, granteeUserId, ConsentGrant.SCOPE_AI_RETRIEVAL, now);
        if (!active.isEmpty()) {
            final ConsentGrant primary = active.get(0);
            primary.setGranteeRole(granteeRole == null ? "CAREGIVER" : granteeRole);
            primary.setGrantedAt(now);
            primary.setExpiresAt(expiresAt);
            primary.setRevokedAt(null);
            primary.setStatus(ConsentGrant.STATUS_ACTIVE);
            if (active.size() > 1) {
                final List<ConsentGrant> extras = new ArrayList<>(active.subList(1, active.size()));
                for (final ConsentGrant extra : extras) {
                    extra.setStatus(ConsentGrant.STATUS_REVOKED);
                    extra.setRevokedAt(now);
                }
                consentGrantRepository.saveAll(extras);
            }
            final ConsentGrant saved = consentGrantRepository.save(primary);
            if (log.isInfoEnabled()) {
                log.info(
                        "Refreshed AI retrieval consent: patient={} grantee={} grantId={}",
                        patientUserId, granteeUserId, saved.getId());
            }
            return saved;
        }

        final ConsentGrant grant = ConsentGrant.builder()
                .patientUserId(patientUserId)
                .granteeUserId(granteeUserId)
                .granteeRole(granteeRole == null ? "CAREGIVER" : granteeRole)
                .scope(ConsentGrant.SCOPE_AI_RETRIEVAL)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now)
                .expiresAt(expiresAt)
                .build();
        final ConsentGrant saved = consentGrantRepository.save(grant);
        if (log.isInfoEnabled()) {
            log.info(
                    "Granted AI retrieval consent: patient={} grantee={} expiresAt={}",
                    patientUserId, granteeUserId, expiresAt);
        }
        return saved;
    }

    /**
     * Revokes any active AI-retrieval consent grants from a patient to a grantee.
     *
     * <p>When no ACTIVE grant exists and no grant history exists, inserts a {@code REVOKED}
     * sentinel so care-circle grandfather access ends (toggle OFF matches Ask AI).
     *
     * @param patientUserId user identifier of the patient
     * @param granteeUserId user identifier of the grantee
     * @return number of grants revoked or sentinel rows written
     */
    @Transactional
    public int revokeAiRetrievalConsent(final Long patientUserId, final Long granteeUserId) {
        if (patientUserId == null || granteeUserId == null) {
            return 0;
        }
        final Instant now = Instant.now();
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, granteeUserId, ConsentGrant.SCOPE_AI_RETRIEVAL, now);
        if (!active.isEmpty()) {
            for (final ConsentGrant grant : active) {
                grant.setStatus(ConsentGrant.STATUS_REVOKED);
                grant.setRevokedAt(now);
            }
            consentGrantRepository.saveAll(active);
            if (log.isInfoEnabled()) {
                log.info(
                        "Revoked {} AI retrieval consent grant(s): patient={} grantee={}",
                        active.size(), patientUserId, granteeUserId);
            }
            return active.size();
        }

        // End grandfather access when the patient toggles OFF without a prior grant row.
        if (!hasAnyAiRetrievalGrantHistory(granteeUserId, patientUserId)) {
            final ConsentGrant sentinel = ConsentGrant.builder()
                    .patientUserId(patientUserId)
                    .granteeUserId(granteeUserId)
                    .granteeRole("CAREGIVER")
                    .scope(ConsentGrant.SCOPE_AI_RETRIEVAL)
                    .status(ConsentGrant.STATUS_REVOKED)
                    .grantedAt(now)
                    .revokedAt(now)
                    .build();
            consentGrantRepository.save(sentinel);
            if (log.isInfoEnabled()) {
                log.info(
                        "Wrote AI retrieval revoke sentinel (end grandfather): patient={} grantee={}",
                        patientUserId, granteeUserId);
            }
            return 1;
        }
        return 0;
    }
}
