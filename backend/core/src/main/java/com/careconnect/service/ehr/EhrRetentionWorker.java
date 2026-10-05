package com.careconnect.service.ehr;

import com.careconnect.ehr.StoredDateOfBirth;
import com.careconnect.repository.ehr.EhrAuditEventRepository;
import com.careconnect.repository.ehr.EhrIdentityConflictRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrResourceRepository;
import com.careconnect.repository.ehr.EhrSourceIdentityRepository;
import com.careconnect.repository.ehr.PatientDateOfBirth;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.function.BiFunction;
import java.util.function.Function;

/**
 * Deletes rows from the PHI-bearing {@code ehr_*} tables once the retention period for them has
 * passed (PR #209 and PR #216 reviews, issue #214).
 *
 * <h2>The rule, and where it comes from</h2>
 * Decided 2026-10-02 (issue #214): follow Maryland's medical-record statute, Health-General
 * § 4-403, as the retention floor, and purge once it is met.
 * <ul>
 *   <li>§ 4-403(b): a record may not be destroyed for <b>7 years</b> after it is made.</li>
 *   <li>§ 4-403(c): a record about a minor may not be destroyed until the patient attains the
 *       age of majority plus 7 years, which is <b>age 25</b>.</li>
 * </ul>
 * So a row is purged only when <em>both</em> hold: it is more than {@code years} old, and the
 * patient has reached {@code retain-until-age}. For a record about an adult the second condition
 * is already true by the time the first is; for a record about a minor it is what keeps a
 * newborn's data for 25 years. One rule covers both.
 * <p>
 * HIPAA sets no period for medical records (its six years, 45 CFR 164.316(b)(2)(i), is for
 * compliance documentation, and seven covers it), and the ten years of 42 CFR 422.504(d) is a
 * Medicare Advantage contract term; neither was adopted. Whether § 4-403 binds this application
 * at all, given that the record of care lives in the source EHR, is a legal question this class
 * does not answer. It implements the policy that was chosen.
 *
 * <h2>Which tables, and which date each is measured from</h2>
 * <ul>
 *   <li>{@code ehr_raw_payload}: {@code retrieved_at}, when the source answered.</li>
 *   <li>{@code ehr_resource}: {@code last_synced_at}, when this application last stored the
 *       current-state mirror. A mirror for a patient who is still syncing is simply written again
 *       by the next sync; rows with no {@code patient_id} yet (nullable, additive column) are
 *       skipped, as the age rule needs a patient.</li>
 *   <li>{@code ehr_identity_conflict}: {@code resolved_at}. Only resolved rows; a {@code PENDING}
 *       row is a question still waiting for the patient and is never purged. The whole row goes,
 *       values and decision together: the trail has by then been kept for the full period.</li>
 *   <li>{@code ehr_source_identity}: {@code updated_at}, when this application last stored the
 *       snapshot. A snapshot purged for a patient who is still syncing is simply written again by
 *       the next sync.</li>
 *   <li>{@code ehr_audit_event}: {@code event_time}.</li>
 * </ul>
 * Each of those dates is at or after the moment the record was made, so nothing is purged early.
 * <p>
 * Two tables are deliberately not here. {@code ehr_patient_crosswalk} is the live link between a
 * patient and a source: deleting it on a timer would unlink a patient who is still in care, and it
 * already goes when the {@code patient} row does, by foreign key. {@code
 * ehr_identity_field_provenance} holds a source id and a timestamp, no patient values, and the
 * reconciler depends on it to decide who wins.
 *
 * <h2>Unknown is kept</h2>
 * A patient whose date of birth is missing or unreadable is <em>unknown</em>, and their rows are
 * kept: unknown must not be read as "adult". {@code patient.dob} is free text, so this is a real
 * case, and those rows will not purge until the date of birth is corrected. Each run reports how
 * many patients that is, per table.
 *
 * <h2>Operational</h2>
 * Three things done deliberately, each a defect already filed against the telemetry purge: the
 * periods are constructor-injected and validated, so an unbound property cannot purge a table
 * (#102); the schedule is a cron expression rather than a delay from startup, so it does not fire
 * on every restart or drift with uptime (#104); and each delete is a bulk statement, not a derived
 * delete that loads the backlog first (#106). Two instances running it at the same moment is
 * harmless: the statements are idempotent. {@code years=0} turns the purge off.
 */
@Slf4j
@Component
public class EhrRetentionWorker {

    /** Patients per delete statement, to keep the IN list bounded. */
    static final int DELETE_BATCH_SIZE = 500;

    /** One table: how to find who has rows past the cutoff, and how to delete them. */
    private record Target(
            String table,
            Function<OffsetDateTime, List<PatientDateOfBirth>> candidates,
            BiFunction<OffsetDateTime, List<Long>, Integer> delete) {
    }

    private final List<Target> targets;
    private final int retentionYears;
    private final int retainUntilAge;

    public EhrRetentionWorker(
            final EhrRawPayloadRepository rawPayloads,
            final EhrIdentityConflictRepository conflicts,
            final EhrSourceIdentityRepository sourceIdentities,
            final EhrAuditEventRepository auditEvents,
            final EhrResourceRepository resources,
            @Value("${careconnect.ehr.retention.years:7}") final int retentionYears,
            @Value("${careconnect.ehr.retention.retain-until-age:25}") final int retainUntilAge) {
        if (retainUntilAge < 0) {
            throw new IllegalArgumentException(
                    "careconnect.ehr.retention.retain-until-age must not be negative: " + retainUntilAge);
        }
        this.retentionYears = retentionYears;
        this.retainUntilAge = retainUntilAge;
        this.targets = List.of(
                new Target("ehr_raw_payload",
                        rawPayloads::findPatientsWithPayloadRetrievedBefore,
                        rawPayloads::deleteRetrievedBeforeForPatients),
                new Target("ehr_resource",
                        cutoff -> resources.findPatientsWithResourceSyncedBefore(cutoff.toInstant()),
                        (cutoff, ids) -> resources.deleteSyncedBeforeForPatients(cutoff.toInstant(), ids)),
                new Target("ehr_identity_conflict",
                        cutoff -> conflicts.findPatientsWithConflictResolvedBefore(cutoff.toInstant()),
                        (cutoff, ids) -> conflicts.deleteResolvedBeforeForPatients(cutoff.toInstant(), ids)),
                new Target("ehr_source_identity",
                        cutoff -> sourceIdentities.findPatientsWithSnapshotUpdatedBefore(auditableTime(cutoff)),
                        (cutoff, ids) -> sourceIdentities.deleteUpdatedBeforeForPatients(auditableTime(cutoff), ids)),
                new Target("ehr_audit_event",
                        auditEvents::findPatientsWithEventBefore,
                        auditEvents::deleteEventsBeforeForPatients));
        if (retentionYears <= 0) {
            log.warn("EHR retention purge is OFF (careconnect.ehr.retention.years={}); the ehr_* tables "
                    + "hold PHI and nothing will be purged (issue #214)", retentionYears);
        }
    }

    /**
     * {@code Auditable} stamps {@code updated_at} with {@code LocalDateTime.now()} in the JVM's
     * zone, so the cutoff is expressed the same way before it is compared.
     */
    private static LocalDateTime auditableTime(final OffsetDateTime cutoff) {
        return LocalDateTime.ofInstant(cutoff.toInstant(), ZoneId.systemDefault());
    }

    @Scheduled(cron = "${careconnect.ehr.retention.purge-cron:0 30 3 * * *}")
    public void purgeExpired() {
        purgeExpired(OffsetDateTime.now());
    }

    /**
     * @param now the moment to measure from; a parameter so a test can fix it.
     * @return rows deleted across all tables, or 0 when the purge is off.
     */
    int purgeExpired(final OffsetDateTime now) {
        if (retentionYears <= 0) {
            return 0;
        }
        final OffsetDateTime cutoff = now.minusYears(retentionYears);
        // The patient has attained the age on their birthday, so "born on or before" is inclusive.
        final LocalDate bornOnOrBefore = now.toLocalDate().minusYears(retainUntilAge);

        int deleted = 0;
        for (final Target target : targets) {
            deleted += purge(target, cutoff, bornOnOrBefore);
        }
        return deleted;
    }

    private int purge(final Target target, final OffsetDateTime cutoff, final LocalDate bornOnOrBefore) {
        final List<Long> pastRetainUntilAge = new ArrayList<>();
        int stillTooYoung = 0;
        int unknownDateOfBirth = 0;
        for (final PatientDateOfBirth patient : target.candidates().apply(cutoff)) {
            final Optional<LocalDate> dateOfBirth = StoredDateOfBirth.parse(patient.getDob());
            if (dateOfBirth.isEmpty()) {
                unknownDateOfBirth++;
            } else if (dateOfBirth.get().isAfter(bornOnOrBefore)) {
                stillTooYoung++;
            } else {
                pastRetainUntilAge.add(patient.getPatientId());
            }
        }

        int deleted = 0;
        for (int from = 0; from < pastRetainUntilAge.size(); from += DELETE_BATCH_SIZE) {
            final List<Long> batch = pastRetainUntilAge.subList(
                    from, Math.min(from + DELETE_BATCH_SIZE, pastRetainUntilAge.size()));
            deleted += target.delete().apply(cutoff, batch);
        }

        // Counts and the cutoff only. Never log patient ids or anything from a row.
        if (deleted > 0 || stillTooYoung > 0) {
            log.info("EHR retention: {} purged {} row(s) older than {} for {} patient(s); "
                            + "kept {} patient(s) who have not reached age {}",
                    target.table(), deleted, cutoff, pastRetainUntilAge.size(), stillTooYoung, retainUntilAge);
        }
        if (unknownDateOfBirth > 0) {
            log.warn("EHR retention: {} has rows past the {}-year period for {} patient(s) with no readable "
                            + "date of birth; they were kept and will not purge until it is corrected",
                    target.table(), retentionYears, unknownDateOfBirth);
        }
        return deleted;
    }
}
