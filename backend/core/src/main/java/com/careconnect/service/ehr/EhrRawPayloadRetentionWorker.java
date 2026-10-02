package com.careconnect.service.ehr;

import com.careconnect.ehr.StoredDateOfBirth;
import com.careconnect.repository.ehr.EhrRawPayloadRepository;
import com.careconnect.repository.ehr.EhrRawPayloadRepository.PatientDateOfBirth;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * Deletes {@code ehr_raw_payload} rows once the retention period for them has passed.
 * <p>
 * {@code ehr_raw_payload} holds retrieved clinical content verbatim, so it is PHI and must not
 * accumulate without limit (PR #209 and PR #216 reviews, issue #214).
 *
 * <h2>The rule, and where it comes from</h2>
 * Decided 2026-10-02 (issue #214): follow Maryland's medical-record statute, Health-General
 * § 4-403, as the retention floor, and purge once it is met.
 * <ul>
 *   <li>§ 4-403(b): a record may not be destroyed for <b>7 years</b> after it is made.</li>
 *   <li>§ 4-403(c): a record about a minor may not be destroyed until the patient attains the
 *       age of majority plus 7 years, which is <b>age 25</b>.</li>
 * </ul>
 * So a payload is purged only when <em>both</em> hold: it was retrieved more than
 * {@code retention-years} ago, and the patient has reached {@code retain-until-age}. For a record
 * about an adult the second condition is already true by the time the first is; for a record
 * about a minor it is what keeps a newborn's payload for 25 years. One rule covers both.
 * <p>
 * HIPAA sets no period for medical records (its six years, 45 CFR 164.316(b)(2)(i), is for
 * compliance documentation), and the ten years of 42 CFR 422.504(d) is a Medicare Advantage
 * contract term; neither was adopted. Whether § 4-403 binds this application at all, given that
 * the record of care lives in the source EHR, is a legal question this class does not answer. It
 * implements the policy that was chosen.
 *
 * <h2>Two choices that err toward keeping</h2>
 * Age is measured from {@code retrieved_at}, when the source answered. That is later than when
 * the record was made, so a payload is never purged early.
 * <p>
 * A patient whose date of birth is missing or unreadable is treated as <em>unknown</em>, and
 * their payloads are kept: unknown must not be read as "adult". {@code patient.dob} is free text,
 * so this is a real case, and those rows will not purge until the date of birth is corrected.
 * Each run reports how many patients that is.
 *
 * <h2>Operational</h2>
 * Three things done deliberately, each a defect already filed against the telemetry purge: the
 * periods are constructor-injected and validated, so an unbound property cannot purge the table
 * (#102); the schedule is a cron expression rather than a delay from startup, so it does not fire
 * on every restart or drift with uptime (#104); and the delete is a bulk statement, not a derived
 * delete that loads the backlog first (#106). Two instances running it at the same moment is
 * harmless: the statements are idempotent. {@code retention-years=0} turns the purge off.
 */
@Slf4j
@Component
public class EhrRawPayloadRetentionWorker {

    /** Patients per delete statement, to keep the IN list bounded. */
    static final int DELETE_BATCH_SIZE = 500;

    private final EhrRawPayloadRepository repository;
    private final int retentionYears;
    private final int retainUntilAge;

    public EhrRawPayloadRetentionWorker(
            final EhrRawPayloadRepository repository,
            @Value("${careconnect.ehr.raw-payload.retention-years:7}") final int retentionYears,
            @Value("${careconnect.ehr.raw-payload.retain-until-age:25}") final int retainUntilAge) {
        if (retainUntilAge < 0) {
            throw new IllegalArgumentException(
                    "careconnect.ehr.raw-payload.retain-until-age must not be negative: " + retainUntilAge);
        }
        this.repository = repository;
        this.retentionYears = retentionYears;
        this.retainUntilAge = retainUntilAge;
        if (retentionYears <= 0) {
            log.warn("EHR raw payload retention purge is OFF "
                    + "(careconnect.ehr.raw-payload.retention-years={}); ehr_raw_payload is PHI and "
                    + "nothing will be purged (issue #214)", retentionYears);
        }
    }

    @Scheduled(cron = "${careconnect.ehr.raw-payload.purge-cron:0 30 3 * * *}")
    public void purgeExpired() {
        purgeExpired(OffsetDateTime.now());
    }

    /**
     * @param now the moment to measure from; a parameter so a test can fix it.
     * @return rows deleted, or 0 when the purge is off.
     */
    int purgeExpired(final OffsetDateTime now) {
        if (retentionYears <= 0) {
            return 0;
        }
        final OffsetDateTime cutoff = now.minusYears(retentionYears);
        // The patient has attained the age on their birthday, so "born on or before" is inclusive.
        final LocalDate bornOnOrBefore = now.toLocalDate().minusYears(retainUntilAge);

        final List<Long> pastRetainUntilAge = new ArrayList<>();
        int stillTooYoung = 0;
        int unknownDateOfBirth = 0;
        for (final PatientDateOfBirth patient : repository.findPatientsWithPayloadRetrievedBefore(cutoff)) {
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
            deleted += repository.deleteRetrievedBeforeForPatients(cutoff, batch);
        }

        // Counts and the cutoff only. Never log patient ids or anything from the payload.
        if (deleted > 0 || stillTooYoung > 0) {
            log.info("EHR raw payload retention: purged {} row(s) retrieved before {} for {} patient(s); "
                            + "kept {} patient(s) who have not reached age {}",
                    deleted, cutoff, pastRetainUntilAge.size(), stillTooYoung, retainUntilAge);
        }
        if (unknownDateOfBirth > 0) {
            log.warn("EHR raw payload retention: {} patient(s) have payloads past the {}-year period "
                            + "but no readable date of birth, so their payloads were kept and will not "
                            + "purge until it is corrected",
                    unknownDateOfBirth, retentionYears);
        }
        return deleted;
    }
}
