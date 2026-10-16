package com.careconnect.service.consent;

import com.careconnect.exception.AppException;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.CaregiverPatientLink.LinkStatus;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.ConsentGrantRepository;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
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
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * The Medicare View consent API's service ({@link ConsentService}, PR #325, WBS 6.2.56) against the
 * Medicare read guard ({@link MedicareAccessPolicy}, PR #238) on real {@code users}, {@code patient},
 * {@code caregiver_patient_link} and {@code consent_grants} rows. SRS BR-02 and FR-MCR-16: a linked
 * caregiver reads a patient's Medicare data only while the patient's MEDICARE_VIEW grant is active.
 * <p>
 * {@code ConsentServiceTest} mocks the repository, so it cannot show that a grant the service writes is
 * the grant the guard reads: same scope string, same patient and grantee columns, same expiry and
 * status rules. That only shows here.
 * <p>
 * Test IDs TC-MCR-CONSENT-040 to 047, Software Test Plan §3.20. Runs on the test profile's H2 database
 * (default mode, {@code ddl-auto=create-drop}), not PostgreSQL, so the partial unique index
 * {@code uq_consent_grants_active} is not present; it is checked live on PostgreSQL instead.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import({ConsentService.class, CaregiverPatientLinkService.class, MedicareAccessPolicy.class})
class MedicareViewConsentJpaTest {

    private static final AtomicInteger SEQ = new AtomicInteger();

    @Autowired
    private TestEntityManager em;

    @Autowired
    private ConsentService consentService;

    @Autowired
    private MedicareAccessPolicy policy;

    @Autowired
    private ConsentGrantRepository grants;

    private User user(final Role role) {
        return em.persistAndFlush(User.builder()
                .email("consent-" + SEQ.incrementAndGet() + "@example.test")
                .password("not-a-real-password")
                .role(role)
                .build());
    }

    /** A patient: their account and their {@code patient} row, which has an id of its own. */
    private record PatientAccount(User user, Patient record) {
        Long userId() {
            return user.getId();
        }

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

    private void activeLink(final User caregiver, final User patient) {
        final CaregiverPatientLink link = new CaregiverPatientLink();
        link.setCaregiverUser(caregiver);
        link.setPatientUser(patient);
        link.setCreatedBy(patient);
        link.setStatus(LinkStatus.ACTIVE);
        em.persistAndFlush(link);
    }

    private void assertAllowed(final User caller, final PatientAccount patient) {
        assertThatCode(() -> policy.requireMedicareAccess(caller, patient.recordId()))
                .doesNotThrowAnyException();
    }

    private void assertRefused(final User caller, final PatientAccount patient) {
        assertThatThrownBy(() -> policy.requireMedicareAccess(caller, patient.recordId()))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    private List<ConsentGrant> rows(final PatientAccount patient, final User grantee, final String status) {
        return grants.findAll().stream()
                .filter(g -> g.getPatientUserId().equals(patient.userId())
                        && g.getGranteeUserId().equals(grantee.getId())
                        && (status == null || status.equals(g.getStatus())))
                .toList();
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-040 a grant written by the consent service opens the linked caregiver's Medicare read; before it, the read is refused")
    void grantOpensMedicareRead() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());
        assertRefused(caregiver, patient);

        consentService.grantMedicareViewConsent(patient.userId(), caregiver.getId(), null, null);
        em.flush();

        assertAllowed(caregiver, patient);
        assertThat(consentService.isMedicareViewConsentGranted(caregiver.getId(), patient.userId())).isTrue();
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-041 after the patient revokes, the caregiver's next Medicare read is refused and the check reports no consent")
    void revokeClosesNextRead() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());
        consentService.grantMedicareViewConsent(patient.userId(), caregiver.getId(), null, null);
        em.flush();
        assertAllowed(caregiver, patient);

        assertThat(consentService.revokeMedicareViewConsent(patient.userId(), caregiver.getId())).isEqualTo(1);
        em.flush();

        assertRefused(caregiver, patient);
        assertThat(consentService.isEffectiveMedicareViewConsent(caregiver.getId(), patient.userId())).isFalse();
        assertThat(rows(patient, caregiver, ConsentGrant.STATUS_REVOKED)).hasSize(1);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-042 the two scopes never cross: an AI-retrieval grant opens no Medicare read, and a Medicare View grant is not AI-retrieval consent")
    void scopesDoNotCross() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        consentService.grantAiRetrievalConsent(patient.userId(), caregiver.getId(), "CAREGIVER", null);
        em.flush();
        assertRefused(caregiver, patient);

        consentService.revokeAiRetrievalConsent(patient.userId(), caregiver.getId());
        consentService.grantMedicareViewConsent(patient.userId(), caregiver.getId(), null, null);
        em.flush();
        assertAllowed(caregiver, patient);
        assertThat(consentService.isAiRetrievalConsentGranted(caregiver.getId(), patient.userId())).isFalse();
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-043 patient A's grant opens only A's Medicare data: the same caregiver, also linked to B, is refused B's")
    void grantIsPerPatient() {
        final PatientAccount patientA = patient();
        final PatientAccount patientB = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patientA.user());
        activeLink(caregiver, patientB.user());

        consentService.grantMedicareViewConsent(patientA.userId(), caregiver.getId(), null, null);
        em.flush();

        assertAllowed(caregiver, patientA);
        assertRefused(caregiver, patientB);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-044 granting twice leaves exactly one ACTIVE row and the read stays open")
    void regrantKeepsOneActiveRow() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        final ConsentGrant first = consentService.grantMedicareViewConsent(patient.userId(), caregiver.getId(), null, null);
        em.flush();
        final Instant later = Instant.now().plus(30, ChronoUnit.DAYS);
        final ConsentGrant second = consentService.grantMedicareViewConsent(patient.userId(), caregiver.getId(), "CAREGIVER", later);
        em.flush();

        assertThat(second.getId()).isEqualTo(first.getId());
        assertThat(rows(patient, caregiver, ConsentGrant.STATUS_ACTIVE)).hasSize(1);
        assertAllowed(caregiver, patient);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-045 a grant to a caregiver with no link, or to the patient's family member, is refused with 400 and writes no row")
    void grantNeedsCaregiverLink() {
        final PatientAccount patient = patient();
        final User unlinkedCaregiver = user(Role.CAREGIVER);
        final User familyMember = user(Role.FAMILY_MEMBER);

        for (final User grantee : List.of(unlinkedCaregiver, familyMember)) {
            assertThatThrownBy(() -> consentService.grantMedicareViewConsent(
                    patient.userId(), grantee.getId(), null, null))
                    .isInstanceOf(AppException.class)
                    .extracting(e -> ((AppException) e).getStatus())
                    .isEqualTo(HttpStatus.BAD_REQUEST);
            assertThat(rows(patient, grantee, null)).isEmpty();
        }
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-046 a past expiry or an over-long role is refused with 400 before any write, not a database error (DEF-MCR-30)")
    void invalidGrantInputIs400() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        assertThatThrownBy(() -> consentService.grantMedicareViewConsent(
                patient.userId(), caregiver.getId(), null, Instant.now().minus(1, ChronoUnit.HOURS)))
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);
        assertThatThrownBy(() -> {
            consentService.grantMedicareViewConsent(patient.userId(), caregiver.getId(), "C".repeat(40), null);
            em.flush();
        })
                .isInstanceOf(AppException.class)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.BAD_REQUEST);

        assertThat(rows(patient, caregiver, null)).isEmpty();
        assertRefused(caregiver, patient);
    }

    @Test
    @DisplayName("TC-MCR-CONSENT-047 the consent check and the Medicare guard agree for a linked caregiver with no grant: neither reports access (DEF-MCR-29)")
    void checkAgreesWithGuardWithoutGrant() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        assertThat(consentService.isEffectiveMedicareViewConsent(caregiver.getId(), patient.userId())).isFalse();
        assertRefused(caregiver, patient);
    }
}
