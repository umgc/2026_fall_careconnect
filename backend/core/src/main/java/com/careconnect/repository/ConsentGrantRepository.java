package com.careconnect.repository;

import com.careconnect.model.ConsentGrant;

import java.time.Instant;
import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * Repository for scoped patient consent grants (Task 2.4).
 */
public interface ConsentGrantRepository extends JpaRepository<ConsentGrant, Long> {

    /**
     * Returns whether an active, non-expired, non-revoked grant exists for the given
     * patient/grantee/scope tuple.
     *
     * @param patientUserId patient granting consent
     * @param granteeUserId user consent was granted to (e.g. caregiver)
     * @param scope         consent scope (e.g. {@code AI_RETRIEVAL})
     * @param now           current instant used to evaluate expiry
     * @return true when an active grant covers the tuple
     */
    @Query(
            "SELECT CASE WHEN COUNT(cg) > 0 THEN true ELSE false END FROM ConsentGrant cg "
                    + "WHERE cg.patientUserId = :patientUserId "
                    + "AND cg.granteeUserId = :granteeUserId "
                    + "AND cg.scope = :scope "
                    + "AND cg.status = 'ACTIVE' "
                    + "AND cg.revokedAt IS NULL "
                    + "AND (cg.expiresAt IS NULL OR cg.expiresAt > :now)")
    boolean existsActiveGrant(
            @Param("patientUserId") Long patientUserId,
            @Param("granteeUserId") Long granteeUserId,
            @Param("scope") String scope,
            @Param("now") Instant now);

    /**
     * Returns active, non-expired, non-revoked grants for the given patient/grantee/scope
     * tuple, so a revoke operation can locate every matching row.
     */
    @Query(
            "SELECT cg FROM ConsentGrant cg "
                    + "WHERE cg.patientUserId = :patientUserId "
                    + "AND cg.granteeUserId = :granteeUserId "
                    + "AND cg.scope = :scope "
                    + "AND cg.status = 'ACTIVE' "
                    + "AND cg.revokedAt IS NULL "
                    + "AND (cg.expiresAt IS NULL OR cg.expiresAt > :now)")
    List<ConsentGrant> findActiveGrants(
            @Param("patientUserId") Long patientUserId,
            @Param("granteeUserId") Long granteeUserId,
            @Param("scope") String scope,
            @Param("now") Instant now);

    /**
     * ACTIVE rows for the tuple regardless of expiry — used to revoke soft-expired
     * grants before inserting a new ACTIVE row (unique index is status-only).
     */
    @Query(
            "SELECT cg FROM ConsentGrant cg "
                    + "WHERE cg.patientUserId = :patientUserId "
                    + "AND cg.granteeUserId = :granteeUserId "
                    + "AND cg.scope = :scope "
                    + "AND cg.status = 'ACTIVE' "
                    + "AND cg.revokedAt IS NULL")
    List<ConsentGrant> findStatusActiveGrants(
            @Param("patientUserId") Long patientUserId,
            @Param("granteeUserId") Long granteeUserId,
            @Param("scope") String scope);

    /**
     * True when any grant row exists for the tuple (ACTIVE, REVOKED, or expired). Used to
     * stop falling back to care-circle link once explicit consent has been recorded.
     */
    boolean existsByPatientUserIdAndGranteeUserIdAndScope(
            Long patientUserId, Long granteeUserId, String scope);
}
