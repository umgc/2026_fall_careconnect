package com.careconnect.repository;

import static org.assertj.core.api.Assertions.assertThat;

import com.careconnect.model.ConsentGrant;
import com.careconnect.model.User;
import com.careconnect.security.Role;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;
import org.springframework.test.context.ActiveProfiles;

/**
 * {@link ConsentGrantRepository#findActiveGrantsForPatient} against real {@code consent_grants}
 * rows (CR-2, #305). {@code MedicareShareServiceTest} mocks the repository, so it can't show that
 * the JPQL leaves out revoked, expired, other-scope and other-patient rows, or that it orders
 * newest first; this test can. Runs on the test profile's H2 database, like
 * {@code MedicareAccessPolicyJpaTest}.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
class ConsentGrantRepositoryShareJpaTest {

    private static final AtomicInteger SEQ = new AtomicInteger();

    @Autowired
    private TestEntityManager em;

    @Autowired
    private ConsentGrantRepository repository;

    private User user(final Role role) {
        return em.persistAndFlush(User.builder()
                .email("share-" + SEQ.incrementAndGet() + "@example.test")
                .password("not-a-real-password")
                .role(role)
                .build());
    }

    private ConsentGrant grant(final User patient, final User grantee, final String scope,
                               final String status, final Instant grantedAt, final Instant expiresAt) {
        return em.persistAndFlush(ConsentGrant.builder()
                .patientUserId(patient.getId())
                .granteeUserId(grantee.getId())
                .granteeRole(ConsentGrant.GRANTEE_ROLE_SHARE_RECIPIENT)
                .scope(scope)
                .status(status)
                .grantedAt(grantedAt)
                .expiresAt(expiresAt)
                .revokedAt(ConsentGrant.STATUS_REVOKED.equals(status) ? grantedAt : null)
                .build());
    }

    @Test
    @DisplayName("TC-CONSENT-074 CR-2: only the patient's active, unexpired grants in the scope are listed, newest first")
    void findActiveGrantsForPatient_filtersAndOrders() {
        final Instant now = Instant.now();
        final User patient = user(Role.PATIENT);
        final User otherPatient = user(Role.PATIENT);
        final User older = user(Role.FAMILY_MEMBER);
        final User newer = user(Role.FAMILY_MEMBER);
        final User revoked = user(Role.FAMILY_MEMBER);
        final User expired = user(Role.FAMILY_MEMBER);
        final User otherScope = user(Role.FAMILY_MEMBER);

        final ConsentGrant olderShare = grant(patient, older, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(2, ChronoUnit.DAYS), now.plus(88, ChronoUnit.DAYS));
        final ConsentGrant newerShare = grant(patient, newer, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(1, ChronoUnit.DAYS), now.plus(89, ChronoUnit.DAYS));
        grant(patient, revoked, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_REVOKED, now.minus(3, ChronoUnit.DAYS), now.plus(87, ChronoUnit.DAYS));
        grant(patient, expired, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(91, ChronoUnit.DAYS), now.minus(1, ChronoUnit.DAYS));
        grant(patient, otherScope, ConsentGrant.SCOPE_AI_RETRIEVAL,
                ConsentGrant.STATUS_ACTIVE, now.minus(1, ChronoUnit.DAYS), null);
        grant(otherPatient, older, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(1, ChronoUnit.DAYS), now.plus(89, ChronoUnit.DAYS));

        final List<ConsentGrant> found = repository.findActiveGrantsForPatient(
                patient.getId(), ConsentGrant.SCOPE_MEDICARE_VIEW, now);

        assertThat(found).extracting(ConsentGrant::getId)
                .containsExactly(newerShare.getId(), olderShare.getId());
    }

    @Test
    @DisplayName("TC-CONSENT-082 CR-2: a recipient sees only active, unexpired grants made to them, newest first")
    void findActiveGrantsForGrantee_filtersAndOrders() {
        final Instant now = Instant.now();
        final User recipient = user(Role.FAMILY_MEMBER);
        final User someoneElse = user(Role.FAMILY_MEMBER);
        final User first = user(Role.PATIENT);
        final User second = user(Role.PATIENT);
        final User revokedBy = user(Role.PATIENT);
        final User expiredBy = user(Role.PATIENT);

        final ConsentGrant older = grant(first, recipient, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(2, ChronoUnit.DAYS), now.plus(88, ChronoUnit.DAYS));
        final ConsentGrant newer = grant(second, recipient, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(1, ChronoUnit.DAYS), now.plus(89, ChronoUnit.DAYS));
        grant(revokedBy, recipient, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_REVOKED, now.minus(3, ChronoUnit.DAYS), now.plus(87, ChronoUnit.DAYS));
        grant(expiredBy, recipient, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(91, ChronoUnit.DAYS), now.minus(1, ChronoUnit.DAYS));
        grant(first, recipient, ConsentGrant.SCOPE_AI_RETRIEVAL,
                ConsentGrant.STATUS_ACTIVE, now.minus(1, ChronoUnit.DAYS), null);
        grant(first, someoneElse, ConsentGrant.SCOPE_MEDICARE_VIEW,
                ConsentGrant.STATUS_ACTIVE, now.minus(1, ChronoUnit.DAYS), now.plus(89, ChronoUnit.DAYS));

        final List<ConsentGrant> found = repository.findActiveGrantsForGrantee(
                recipient.getId(), ConsentGrant.SCOPE_MEDICARE_VIEW, now);

        assertThat(found).extracting(ConsentGrant::getId)
                .containsExactly(newer.getId(), older.getId());
    }

    @Test
    @DisplayName("TC-CONSENT-075 CR-2: a patient with no grants gets an empty list")
    void findActiveGrantsForPatient_emptyForNoGrants() {
        final User patient = user(Role.PATIENT);

        assertThat(repository.findActiveGrantsForPatient(
                patient.getId(), ConsentGrant.SCOPE_MEDICARE_VIEW, Instant.now())).isEmpty();
    }
}
