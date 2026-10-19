package com.careconnect.service.ehr;

import jakarta.persistence.EntityManager;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Deletes what CareConnect holds from one EHR source about one patient when that source is
 * disconnected, applying the unlink rule agreed for SRS v1.4 Addendum A (A1-Q1): the crosswalk link,
 * the source's raw payloads, its identity snapshot, the identity conflicts it raised, and the
 * {@code ehr_resource} mirror.
 *
 * <p>Deliberately kept: the retrieval audit log ({@code ehr_audit_event}, under the 7-year / age-25
 * retention rule), demographic values reconciliation has already applied to the patient record, and
 * the field provenance rows the reconciler depends on, which hold no patient values.
 */
@Component
@RequiredArgsConstructor
public class EhrSourceDataPurger {

    private final EntityManager entityManager;

    /** Rows removed per table, so a caller can confirm a disconnect only after the deletes commit. */
    public record Purged(int mirroredResources, int rawPayloads, int sourceIdentities,
                         int identityConflicts, int crosswalkLinks) {
    }

    /**
     * @param userId     owner of the {@code ehr_resource} rows, which are keyed by user
     * @param patientId  canonical patient id; null skips the canonical tables
     * @param sourceId   {@code ehr_source.id}; null skips the canonical tables
     * @param sourceCode {@code ehr_source.code}, which is also the mirror's {@code source} value
     */
    @Transactional
    public Purged purge(final Long userId, final Long patientId, final Long sourceId, final String sourceCode) {
        final int mirrored = entityManager
                .createQuery("delete from EhrResource r where r.userId = :userId and r.source = :source")
                .setParameter("userId", userId)
                .setParameter("source", sourceCode)
                .executeUpdate();
        if (patientId == null || sourceId == null) {
            return new Purged(mirrored, 0, 0, 0, 0);
        }
        final int rawPayloads = entityManager
                .createQuery("delete from EhrRawPayload p where p.patientId = :patientId and p.sourceId = :sourceId")
                .setParameter("patientId", patientId)
                .setParameter("sourceId", sourceId)
                .executeUpdate();
        final int identities = entityManager
                .createQuery("delete from EhrSourceIdentity s where s.patientId = :patientId and s.sourceId = :sourceId")
                .setParameter("patientId", patientId)
                .setParameter("sourceId", sourceId)
                .executeUpdate();
        final int conflicts = entityManager
                .createQuery("delete from EhrIdentityConflict c where c.patientId = :patientId and c.sourceId = :sourceId")
                .setParameter("patientId", patientId)
                .setParameter("sourceId", sourceId)
                .executeUpdate();
        final int links = entityManager
                .createQuery("delete from EhrPatientCrosswalk x where x.patientId = :patientId and x.sourceId = :sourceId")
                .setParameter("patientId", patientId)
                .setParameter("sourceId", sourceId)
                .executeUpdate();
        return new Purged(mirrored, rawPayloads, identities, conflicts, links);
    }
}
