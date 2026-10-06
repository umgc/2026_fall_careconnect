package com.careconnect.security;

import com.careconnect.exception.AppException;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.CaregiverPatientLink.LinkStatus;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

/**
 * {@link MedicareAccessPolicy} against real {@code users}, {@code patient}, {@code caregiver_patient_link}
 * and {@code consent_grants} rows (WBS 6.2.37; SRS FR-MCR-16, FR-MCR-17, BR-02). The guard is called
 * with the {@code patient.id}, as Medicare endpoints will call it; the link and consent rows are keyed
 * by user id.
 * <p>
 * {@link MedicareAccessPolicyTest} mocks both repositories and the caregiver, so it proves how the
 * guard combines its three checks but not that the checks themselves hold: that a real caregiver
 * account carries {@code VIEW_ASSIGNED_PATIENTS}, that an expired, pending or revoked link or an
 * expired or revoked grant is refused, and that one patient's link or grant never opens another
 * patient's data. Those depend on the two JPQL queries, which only run here.
 * <p>
 * Test IDs: TC-MCR-AUTHZ-017 to 026 and 030, Software Test Plan §3.15. Runs on the test profile's H2
 * database (default mode, PostgreSQL shims), not PostgreSQL.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import(MedicareAccessPolicy.class)
class MedicareAccessPolicyJpaTest {

    private static final AtomicInteger SEQ = new AtomicInteger();

    @Autowired
    private TestEntityManager em;

    @Autowired
    private MedicareAccessPolicy policy;

    private User user(final Role role) {
        final User u = User.builder()
                .email("authz-" + SEQ.incrementAndGet() + "@example.test")
                .password("not-a-real-password")
                .role(role)
                .build();
        return em.persistAndFlush(u);
    }

    /** A patient: their account and their {@code patient} row, which has an id of its own. */
    private record PatientAccount(User user, Patient record) {
        Long recordId() {
            return record.getId();
        }
    }

    private PatientAccount patient() {
        final User account = user(Role.PATIENT);
        final Patient record = new Patient();
        record.setUser(account);
        return new PatientAccount(account, em.persistAndFlush(record));
    }

    private void link(final User caregiver, final User patient, final LinkStatus status,
                      final LocalDateTime expiresAt) {
        final CaregiverPatientLink l = new CaregiverPatientLink();
        l.setCaregiverUser(caregiver);
        l.setPatientUser(patient);
        l.setCreatedBy(patient);
        l.setStatus(status);
        l.setExpiresAt(expiresAt);
        em.persistAndFlush(l);
    }

    private void activeLink(final User caregiver, final User patient) {
        link(caregiver, patient, LinkStatus.ACTIVE, null);
    }

    private void grant(final User patient, final User grantee, final String status,
                       final Instant expiresAt, final Instant revokedAt) {
        final Instant now = Instant.now();
        em.persistAndFlush(ConsentGrant.builder()
                .patientUserId(patient.getId())
                .granteeUserId(grantee.getId())
                .granteeRole(grantee.getRole().name())
                .scope(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW)
                .status(status)
                .grantedAt(now.minus(1, ChronoUnit.DAYS))
                .expiresAt(expiresAt)
                .revokedAt(revokedAt)
                .createdAt(now)
                .updatedAt(now)
                .build());
    }

    private void activeGrant(final User patient, final User grantee) {
        grant(patient, grantee, ConsentGrant.STATUS_ACTIVE, null, null);
    }

    private void assertAllowed(final User caller, final PatientAccount patient) {
        assertThatCode(() -> policy.requireMedicareAccess(caller, patient.recordId()))
                .doesNotThrowAnyException();
    }

    private void assertRefused(final User caller, final Long patientId) {
        assertThatThrownBy(() -> policy.requireMedicareAccess(caller, patientId))
                .isInstanceOf(AppException.class)
                .hasMessage(MedicareAccessPolicy.NOT_FOUND_MESSAGE)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-017 a real caregiver account with an active permanent link and an active MEDICARE_VIEW grant is allowed")
    void realCaregiverWithLinkAndGrant() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());
        activeGrant(patient.user(), caregiver);

        assertAllowed(caregiver, patient);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-018 a caregiver whose MEDICARE_VIEW grant has expired is refused")
    void expiredGrant() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());
        grant(patient.user(), caregiver, ConsentGrant.STATUS_ACTIVE, Instant.now().minus(1, ChronoUnit.HOURS), null);

        assertRefused(caregiver, patient.recordId());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-019 a caregiver whose MEDICARE_VIEW grant the patient revoked is refused")
    void revokedGrant() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());
        grant(patient.user(), caregiver, ConsentGrant.STATUS_REVOKED, null, Instant.now().minus(1, ChronoUnit.HOURS));

        assertRefused(caregiver, patient.recordId());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-020 a caregiver whose link has expired, though still marked ACTIVE, is refused")
    void expiredLink() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        link(caregiver, patient.user(), LinkStatus.ACTIVE, LocalDateTime.now().minusHours(1));
        activeGrant(patient.user(), caregiver);

        assertRefused(caregiver, patient.recordId());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-021 a caregiver whose link is still PENDING is refused")
    void pendingLink() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        link(caregiver, patient.user(), LinkStatus.PENDING, null);
        activeGrant(patient.user(), caregiver);

        assertRefused(caregiver, patient.recordId());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-022 a caregiver whose link was REVOKED is refused")
    void revokedLink() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        link(caregiver, patient.user(), LinkStatus.REVOKED, null);
        activeGrant(patient.user(), caregiver);

        assertRefused(caregiver, patient.recordId());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-023 a caregiver linked to and consented by patient B is refused patient A's data, and still allowed B's")
    void linkAndGrantForAnotherPatient() {
        final PatientAccount patientA = patient();
        final PatientAccount patientB = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patientB.user());
        activeGrant(patientB.user(), caregiver);

        assertRefused(caregiver, patientA.recordId());
        assertAllowed(caregiver, patientB);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-024 a caregiver linked to patient A but holding a MEDICARE_VIEW grant only from patient B is refused A's data")
    void linkToOnePatientGrantFromAnother() {
        final PatientAccount patientA = patient();
        final PatientAccount patientB = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patientA.user());
        activeGrant(patientB.user(), caregiver);

        assertRefused(caregiver, patientA.recordId());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-025 a linked caregiver is refused when the patient's MEDICARE_VIEW grant went to a different caregiver")
    void grantToAnotherCaregiver() {
        final PatientAccount patient = patient();
        final User linkedOnly = user(Role.CAREGIVER);
        final User grantee = user(Role.CAREGIVER);
        activeLink(linkedOnly, patient.user());
        activeLink(grantee, patient.user());
        activeGrant(patient.user(), grantee);

        assertRefused(linkedOnly, patient.recordId());
        assertAllowed(grantee, patient);
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-026 a request for a patient id that does not exist is refused exactly as a request for an existing patient is")
    void patientThatDoesNotExist() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        final long noSuchPatient = patient.recordId() + 100_000L;
        assertThat(em.find(Patient.class, noSuchPatient)).isNull();

        final AppException missing = catchThrowableOfType(
                () -> policy.requireMedicareAccess(caregiver, noSuchPatient), AppException.class);
        final AppException existing = catchThrowableOfType(
                () -> policy.requireMedicareAccess(caregiver, patient.recordId()), AppException.class);

        assertThat(missing).isNotNull();
        assertThat(existing).isNotNull();
        assertThat(missing.getStatus()).isEqualTo(existing.getStatus()).isEqualTo(HttpStatus.NOT_FOUND);
        assertThat(missing.getMessage()).isEqualTo(existing.getMessage());
    }

    @Test
    @DisplayName("TC-MCR-AUTHZ-030 the guard takes the patient record id: a patient whose patient.id and users.id differ is allowed by the record id, refused by their user id")
    void patientRecordIdAndUserIdDiffer() {
        // Each patient() inserts one users row and one patient row, so the two id sequences move in
        // step. An account with no patient record (a caregiver, as in real data) pulls them apart.
        user(Role.CAREGIVER);
        PatientAccount patient = patient();
        for (int i = 0; i < 3 && patient.recordId().equals(patient.user().getId()); i++) {
            user(Role.CAREGIVER);
            patient = patient();
        }
        final PatientAccount self = patient;
        assertThat(self.recordId()).as("this case needs patient.id and users.id to differ")
                .isNotEqualTo(self.user().getId());

        assertAllowed(self.user(), self);
        assertRefused(self.user(), self.user().getId());
    }
}
