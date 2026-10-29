package com.careconnect.service.consent;

import com.careconnect.exception.AppException;
import com.careconnect.model.ConsentGrant;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.security.EpicAccessPolicy;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

import com.careconnect.service.CaregiverPatientLinkService;
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

    /** The only role that can hold a Medicare View grant: the grantee must be a linked caregiver. */
    static final String MEDICARE_VIEW_GRANTEE_ROLE = "CAREGIVER";

    private final ConsentGrantRepository consentGrantRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;

    /**
     * Returns whether the caregiver currently holds an active AI-retrieval consent grant
     * for the given patient.
     *
     * @param caregiverUserId user identifier of the prospective grantee
     * @param patientUserId   user identifier of the patient granting consent
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
     * @param patientUserId   patient user id
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
     * @param patientUserId   patient user id
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
     * @param granteeRole   role of the grantee (e.g. {@code CAREGIVER})
     * @param expiresAt     optional expiry instant; null means no expiry
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
        // Soft-expired ACTIVE rows still occupy the unique ACTIVE index — revoke them first.
        final List<ConsentGrant> statusActive = consentGrantRepository.findStatusActiveGrants(
                patientUserId, granteeUserId, ConsentGrant.SCOPE_AI_RETRIEVAL);
        if (!statusActive.isEmpty()) {
            final List<ConsentGrant> expired = new ArrayList<>();
            for (final ConsentGrant row : statusActive) {
                if (row.getExpiresAt() != null && !row.getExpiresAt().isAfter(now)) {
                    row.setStatus(ConsentGrant.STATUS_REVOKED);
                    row.setRevokedAt(now);
                    expired.add(row);
                }
            }
            if (!expired.isEmpty()) {
                consentGrantRepository.saveAll(expired);
            }
        }
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
     * Records a patient's self-consent to import their own external EHR records
     * ({@link ConsentGrant#SCOPE_EHR_IMPORT}, Epic Phase 0). Unlike
     * {@link #grantAiRetrievalConsent} this is a self-grant (patient == grantee) and does not
     * require a caregiver link. Idempotent: refreshes an existing ACTIVE row.
     *
     * @param patientUserId the connecting user (patient) id
     * @return the persisted grant
     */
    @Transactional
    public ConsentGrant recordEhrImportConsent(final Long patientUserId) {
        if (patientUserId == null) {
            throw new IllegalArgumentException("patientUserId is required");
        }
        final Instant now = Instant.now();
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, patientUserId, ConsentGrant.SCOPE_EHR_IMPORT, now);
        if (!active.isEmpty()) {
            final ConsentGrant primary = active.get(0);
            primary.setGrantedAt(now);
            primary.setRevokedAt(null);
            primary.setStatus(ConsentGrant.STATUS_ACTIVE);
            return consentGrantRepository.save(primary);
        }
        final ConsentGrant grant = ConsentGrant.builder()
                .patientUserId(patientUserId)
                .granteeUserId(patientUserId)
                .granteeRole("PATIENT")
                .scope(ConsentGrant.SCOPE_EHR_IMPORT)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now)
                .build();
        return consentGrantRepository.save(grant);
    }

    /**
     * Revokes a patient's EHR-import self-consent (Epic "Disconnect").
     *
     * @param patientUserId the connecting user (patient) id
     * @return number of grants revoked
     */
    @Transactional
    public int revokeEhrImportConsent(final Long patientUserId) {
        if (patientUserId == null) {
            return 0;
        }
        final Instant now = Instant.now();
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, patientUserId, ConsentGrant.SCOPE_EHR_IMPORT, now);
        for (final ConsentGrant grant : active) {
            grant.setStatus(ConsentGrant.STATUS_REVOKED);
            grant.setRevokedAt(now);
        }
        if (!active.isEmpty()) {
            consentGrantRepository.saveAll(active);
        }
        return active.size();
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

    // ---------------------------------------------------------------------------------------------
    // EHR_VIEW consent (Epic canonical read surface). Caregiver reads of a patient's EHR records
    // through /api/ehr are gated by EpicAccessPolicy, which checks for an active EHR_VIEW grant.
    // ---------------------------------------------------------------------------------------------

    /**
     * Returns whether the caregiver currently holds an active {@link EpicAccessPolicy#SCOPE_EHR_VIEW}
     * consent grant for the given patient (the check {@link EpicAccessPolicy} enforces on reads).
     *
     * @param caregiverUserId user identifier of the prospective grantee
     * @param patientUserId   user identifier of the patient granting consent
     * @return true when an active, non-expired EHR_VIEW grant exists
     */
    @Transactional(readOnly = true)
    public boolean isEhrViewConsentGranted(final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        return consentGrantRepository.existsActiveGrant(
                patientUserId, caregiverUserId, EpicAccessPolicy.SCOPE_EHR_VIEW, Instant.now());
    }

    /**
     * Grants a patient's {@link EpicAccessPolicy#SCOPE_EHR_VIEW} consent to a caregiver, letting
     * them read the patient's EHR records through the generic {@code /api/ehr} read surface. Mirrors
     * {@link #grantAiRetrievalConsent}: requires an active caregiver link to the patient, is
     * idempotent (refreshes an existing ACTIVE row rather than stacking rows), and never writes a
     * grant to a user outside the patient's care circle.
     *
     * @param patientUserId the patient granting consent
     * @param granteeUserId the caregiver being granted EHR_VIEW
     * @param granteeRole   the grantee's role label (defaults to CAREGIVER)
     * @param expiresAt     optional expiry; null for no expiry
     * @return the persisted grant
     */
    @Transactional
    public ConsentGrant grantEhrViewConsent(
            final Long patientUserId,
            final Long granteeUserId,
            final String granteeRole,
            final Instant expiresAt) {
        if (patientUserId == null || granteeUserId == null) {
            throw new IllegalArgumentException("patientUserId and granteeUserId are required");
        }
        if (!caregiverPatientLinkService.hasAccessToPatient(granteeUserId, patientUserId)) {
            throw new AppException(
                    HttpStatus.BAD_REQUEST,
                    "No active caregiver relationship with this patient");
        }
        final Instant now = Instant.now();
        // Soft-expired ACTIVE rows still occupy the unique ACTIVE index — revoke them first.
        final List<ConsentGrant> statusActive = consentGrantRepository.findStatusActiveGrants(
                patientUserId, granteeUserId, EpicAccessPolicy.SCOPE_EHR_VIEW);
        if (!statusActive.isEmpty()) {
            final List<ConsentGrant> expired = new ArrayList<>();
            for (final ConsentGrant row : statusActive) {
                if (row.getExpiresAt() != null && !row.getExpiresAt().isAfter(now)) {
                    row.setStatus(ConsentGrant.STATUS_REVOKED);
                    row.setRevokedAt(now);
                    expired.add(row);
                }
            }
            if (!expired.isEmpty()) {
                consentGrantRepository.saveAll(expired);
            }
        }
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, granteeUserId, EpicAccessPolicy.SCOPE_EHR_VIEW, now);
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
                        "Refreshed EHR view consent: patient={} grantee={} grantId={}",
                        patientUserId, granteeUserId, saved.getId());
            }
            return saved;
        }

        final ConsentGrant grant = ConsentGrant.builder()
                .patientUserId(patientUserId)
                .granteeUserId(granteeUserId)
                .granteeRole(granteeRole == null ? "CAREGIVER" : granteeRole)
                .scope(EpicAccessPolicy.SCOPE_EHR_VIEW)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now)
                .expiresAt(expiresAt)
                .build();
        final ConsentGrant saved = consentGrantRepository.save(grant);
        if (log.isInfoEnabled()) {
            log.info(
                    "Granted EHR view consent: patient={} grantee={} expiresAt={}",
                    patientUserId, granteeUserId, expiresAt);
        }
        return saved;
    }

    /**
     * Revokes any active {@link EpicAccessPolicy#SCOPE_EHR_VIEW} consent grants from a patient to a
     * grantee. Unlike {@link #revokeAiRetrievalConsent} there is no grandfather access to end, so
     * no REVOKED sentinel is written when nothing is active.
     *
     * @param patientUserId the patient
     * @param granteeUserId the grantee
     * @return number of grants revoked
     */
    @Transactional
    public int revokeEhrViewConsent(final Long patientUserId, final Long granteeUserId) {
        if (patientUserId == null || granteeUserId == null) {
            return 0;
        }
        final Instant now = Instant.now();
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, granteeUserId, EpicAccessPolicy.SCOPE_EHR_VIEW, now);
        if (active.isEmpty()) {
            return 0;
        }
        for (final ConsentGrant grant : active) {
            grant.setStatus(ConsentGrant.STATUS_REVOKED);
            grant.setRevokedAt(now);
        }
        consentGrantRepository.saveAll(active);
        if (log.isInfoEnabled()) {
            log.info(
                    "Revoked {} EHR view consent grant(s): patient={} grantee={}",
                    active.size(), patientUserId, granteeUserId);
        }
        return active.size();
    }

    // ---------------------------------------------------------------------------------------------
    // MEDICARE_VIEW consent. Caregiver reads of a patient's Medicare data are gated by
    // MedicareAccessPolicy, which requires an explicit, active MEDICARE_VIEW grant (no link fallback).
    // ---------------------------------------------------------------------------------------------

    /**
     * Returns whether the caregiver currently holds an active Medicare View
     * ({@link ConsentGrant#SCOPE_MEDICARE_VIEW}) consent grant from the given patient.
     *
     * @param caregiverUserId user identifier of the grantee
     * @param patientUserId   user identifier of the patient granting consent
     * @return true when an active, non-expired grant exists
     */
    @Transactional(readOnly = true)
    public boolean isMedicareViewConsentGranted(
            final Long caregiverUserId, final Long patientUserId) {
        if (caregiverUserId == null || patientUserId == null) {
            return false;
        }
        return consentGrantRepository.existsActiveGrant(
                patientUserId, caregiverUserId, ConsentGrant.SCOPE_MEDICARE_VIEW, Instant.now());
    }

    /**
     * Returns whether Medicare View consent is in effect for the pair. Unlike AI retrieval there
     * is no care-circle fallback: SRS BR-02 and FR-MCR-16 require an explicit, active
     * {@code MEDICARE_VIEW} grant, and that is exactly what
     * {@link com.careconnect.security.MedicareAccessPolicy} checks on every Medicare read. Reporting
     * a linked caregiver without a grant as consented would tell the patient their data is shared
     * when the caregiver is in fact refused.
     *
     * @param caregiverUserId grantee user id
     * @param patientUserId   patient user id
     * @return true only when an active, non-expired explicit grant exists
     */
    @Transactional(readOnly = true)
    public boolean isEffectiveMedicareViewConsent(
            final Long caregiverUserId, final Long patientUserId) {
        return isMedicareViewConsentGranted(caregiverUserId, patientUserId);
    }

    /**
     * Grants Medicare View ({@link ConsentGrant#SCOPE_MEDICARE_VIEW}) consent from a patient to a
     * caregiver linked to them.
     *
     * <p>If an ACTIVE grant already exists for the tuple, it is refreshed in place (and any
     * duplicate ACTIVE rows are revoked) so callers cannot accumulate multiple live grants.
     *
     * @param patientUserId user identifier of the patient granting consent
     * @param granteeUserId user identifier of the caregiver
     * @param granteeRole   optional; when present it must be {@code CAREGIVER}
     * @param expiresAt     optional expiry instant, which must be in the future; null means no expiry
     * @return the persisted grant
     * @throws AppException with status 400 when the role or expiry is invalid or the grantee has no
     *                      active caregiver link to the patient
     */
    @Transactional
    public ConsentGrant grantMedicareViewConsent(
            final Long patientUserId,
            final Long granteeUserId,
            final String granteeRole,
            final Instant expiresAt) {
        if (patientUserId == null || granteeUserId == null) {
            throw new IllegalArgumentException("patientUserId and granteeUserId are required");
        }
        if (granteeRole != null && !MEDICARE_VIEW_GRANTEE_ROLE.equals(granteeRole)) {
            throw new AppException(HttpStatus.BAD_REQUEST, "granteeRole must be CAREGIVER");
        }
        final Instant now = Instant.now();
        if (expiresAt != null && !expiresAt.isAfter(now)) {
            throw new AppException(HttpStatus.BAD_REQUEST, "expiresAt must be in the future");
        }
        // Only a linked caregiver can receive the grant. MedicareAccessPolicy checks the link
        // again on every read, so a grant alone never opens Medicare data.
        if (!caregiverPatientLinkService.hasAccessToPatient(granteeUserId, patientUserId)) {
            throw new AppException(
                    HttpStatus.BAD_REQUEST,
                    "No active caregiver relationship with this patient");
        }
        // Soft-expired ACTIVE rows still occupy the unique ACTIVE index — revoke them first.
        final List<ConsentGrant> statusActive = consentGrantRepository.findStatusActiveGrants(
                patientUserId, granteeUserId, ConsentGrant.SCOPE_MEDICARE_VIEW);
        if (!statusActive.isEmpty()) {
            final List<ConsentGrant> expired = new ArrayList<>();
            for (final ConsentGrant row : statusActive) {
                if (row.getExpiresAt() != null && !row.getExpiresAt().isAfter(now)) {
                    row.setStatus(ConsentGrant.STATUS_REVOKED);
                    row.setRevokedAt(now);
                    expired.add(row);
                }
            }
            if (!expired.isEmpty()) {
                consentGrantRepository.saveAll(expired);
            }
        }
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, granteeUserId, ConsentGrant.SCOPE_MEDICARE_VIEW, now);
        if (!active.isEmpty()) {
            final ConsentGrant primary = active.get(0);
            primary.setGranteeRole(MEDICARE_VIEW_GRANTEE_ROLE);
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
                        "Refreshed Medicare View consent: patient={} grantee={} grantId={}",
                        patientUserId, granteeUserId, saved.getId());
            }
            return saved;
        }

        final ConsentGrant grant = ConsentGrant.builder()
                .patientUserId(patientUserId)
                .granteeUserId(granteeUserId)
                .granteeRole(MEDICARE_VIEW_GRANTEE_ROLE)
                .scope(ConsentGrant.SCOPE_MEDICARE_VIEW)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now)
                .expiresAt(expiresAt)
                .build();
        final ConsentGrant saved = consentGrantRepository.save(grant);
        if (log.isInfoEnabled()) {
            log.info(
                    "Granted Medicare View consent: patient={} grantee={} expiresAt={}",
                    patientUserId, granteeUserId, expiresAt);
        }
        return saved;
    }

    /**
     * Revokes any active Medicare View consent grants from a patient to a grantee. The caregiver's
     * next Medicare read is refused, because {@link com.careconnect.security.MedicareAccessPolicy}
     * looks the grant up on every request.
     *
     * @param patientUserId user identifier of the patient
     * @param granteeUserId user identifier of the grantee
     * @return number of grants revoked; 0 when none was active
     */
    @Transactional
    public int revokeMedicareViewConsent(final Long patientUserId, final Long granteeUserId) {
        if (patientUserId == null || granteeUserId == null) {
            return 0;
        }
        final Instant now = Instant.now();
        final List<ConsentGrant> active = consentGrantRepository.findActiveGrants(
                patientUserId, granteeUserId, ConsentGrant.SCOPE_MEDICARE_VIEW, now);
        if (active.isEmpty()) {
            return 0;
        }
        for (final ConsentGrant grant : active) {
            grant.setStatus(ConsentGrant.STATUS_REVOKED);
            grant.setRevokedAt(now);
        }
        consentGrantRepository.saveAll(active);
        if (log.isInfoEnabled()) {
            log.info(
                    "Revoked {} Medicare View consent grant(s): patient={} grantee={}",
                    active.size(), patientUserId, granteeUserId);
        }
        return active.size();
    }
}
