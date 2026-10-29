package com.careconnect.service;

import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.CaregiverPatientLink.LinkStatus;
import com.careconnect.model.FriendRequest;
import com.careconnect.model.User;
import com.careconnect.security.Role;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;

import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link MessagingPolicy} against real {@code users}, {@code caregiver_patient_link} and {@code friend_requests}
 * rows, with the real {@link CaregiverPatientLinkService}.
 * <p>
 * {@link MessagingPolicyTest} mocks the link service and the friend-request repository, so it proves how the policy
 * combines the two relationships but not what counts as an active link: the link's status and expiry, and the
 * messaging switch as {@link CaregiverPatientLinkService#setPatientMessagingEnabled} stores it. Those depend on the
 * link service's queries, which only run here.
 * <p>
 * Test IDs: TC-MSG-POL-011…017, Software Test Plan §3.34. Runs on the test profile's H2 database, not PostgreSQL.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import({MessagingPolicy.class, CaregiverPatientLinkService.class})
class MessagingPolicyIntegrationTest {

    private static final AtomicInteger SEQ = new AtomicInteger();

    @Autowired
    private TestEntityManager em;
    @Autowired
    private MessagingPolicy policy;
    @Autowired
    private CaregiverPatientLinkService linkService;

    private User user(final Role role) {
        return em.persistAndFlush(User.builder()
                .email("msg-" + SEQ.incrementAndGet() + "@example.test")
                .password("not-a-real-password")
                .role(role)
                .build());
    }

    private CaregiverPatientLink link(final User caregiver, final User patient, final LinkStatus status,
                                      final LocalDateTime expiresAt) {
        final CaregiverPatientLink l = new CaregiverPatientLink();
        l.setCaregiverUser(caregiver);
        l.setPatientUser(patient);
        l.setCreatedBy(patient);
        l.setStatus(status);
        l.setExpiresAt(expiresAt);
        return em.persistAndFlush(l);
    }

    private void friendRequest(final User from, final User to, final String status) {
        final FriendRequest r = new FriendRequest();
        r.setFromUserId(from.getId());
        r.setToUserId(to.getId());
        r.setStatus(status);
        em.persistAndFlush(r);
    }

    private boolean bothWays(final User a, final User b) {
        final boolean ab = policy.canMessage(a.getId(), b.getId());
        final boolean ba = policy.canMessage(b.getId(), a.getId());
        assertThat(ab).as("the rule is the same in both directions").isEqualTo(ba);
        return ab;
    }

    @Test
    @DisplayName("TC-MSG-POL-011 an active permanent link with messaging on lets the caregiver and the patient message "
            + "each other")
    void activeLink_messagingOn_allowedBothWays() {
        final User caregiver = user(Role.CAREGIVER);
        final User patient = user(Role.PATIENT);
        link(caregiver, patient, LinkStatus.ACTIVE, null);

        assertThat(bothWays(caregiver, patient)).isTrue();
    }

    @Test
    @DisplayName("TC-MSG-POL-012 messaging turned off through the link service blocks both directions, even when the "
            + "two are also friends")
    void messagingTurnedOff_blocksBothWays_evenForFriends() {
        final User caregiver = user(Role.CAREGIVER);
        final User patient = user(Role.PATIENT);
        final CaregiverPatientLink l = link(caregiver, patient, LinkStatus.ACTIVE, null);
        friendRequest(patient, caregiver, "accepted");
        linkService.setPatientMessagingEnabled(l.getId(), false, caregiver.getId(), Role.CAREGIVER);
        em.flush();
        em.clear();

        assertThat(bothWays(caregiver, patient)).isFalse();

        linkService.setPatientMessagingEnabled(l.getId(), true, caregiver.getId(), Role.CAREGIVER);
        em.flush();
        em.clear();
        assertThat(bothWays(caregiver, patient)).as("turned back on").isTrue();
    }

    @Test
    @DisplayName("TC-MSG-POL-013 a pending, suspended, revoked, expired or rejected link, with no friend request, does "
            + "not allow messaging")
    void inactiveLink_noFriendship_refused() {
        for (final LinkStatus status : new LinkStatus[]{LinkStatus.PENDING, LinkStatus.SUSPENDED, LinkStatus.REVOKED,
                LinkStatus.EXPIRED, LinkStatus.REJECTED}) {
            final User caregiver = user(Role.CAREGIVER);
            final User patient = user(Role.PATIENT);
            link(caregiver, patient, status, null);

            assertThat(bothWays(caregiver, patient)).as(status.name()).isFalse();
        }
    }

    @Test
    @DisplayName("TC-MSG-POL-014 an ACTIVE link past its expiry is not a link: refused on its own, allowed only through "
            + "an accepted friend request")
    void expiredActiveLink_fallsBackToFriendship() {
        final User caregiver = user(Role.CAREGIVER);
        final User patient = user(Role.PATIENT);
        link(caregiver, patient, LinkStatus.ACTIVE, LocalDateTime.now().minusDays(1));

        assertThat(bothWays(caregiver, patient)).as("no friend request").isFalse();

        friendRequest(caregiver, patient, "accepted");
        assertThat(bothWays(caregiver, patient)).as("accepted friend request").isTrue();
    }

    @Test
    @DisplayName("TC-MSG-POL-015 with no link, an accepted friend request allows messaging both ways; a pending or "
            + "rejected one does not")
    void noLink_friendRequestStatusDecides() {
        final User a = user(Role.PATIENT);
        final User b = user(Role.PATIENT);
        friendRequest(a, b, "pending");
        assertThat(bothWays(a, b)).as("pending").isFalse();

        final User c = user(Role.CAREGIVER);
        final User d = user(Role.CAREGIVER);
        friendRequest(c, d, "rejected");
        assertThat(bothWays(c, d)).as("rejected").isFalse();

        final User e = user(Role.PATIENT);
        final User f = user(Role.CAREGIVER);
        friendRequest(f, e, "accepted");
        assertThat(bothWays(e, f)).as("accepted").isTrue();
    }

    @Test
    @DisplayName("TC-MSG-POL-016 an administrator with no link or friend request cannot message a user")
    void admin_noRelationship_refused() {
        final User admin = user(Role.ADMIN);
        final User patient = user(Role.PATIENT);

        assertThat(bothWays(admin, patient)).isFalse();
    }

    @Test
    @DisplayName("TC-MSG-POL-017 a caregiver's link to one patient does not let them message another patient")
    void linkToOnePatient_doesNotOpenAnother() {
        final User caregiver = user(Role.CAREGIVER);
        final User linked = user(Role.PATIENT);
        final User other = user(Role.PATIENT);
        link(caregiver, linked, LinkStatus.ACTIVE, null);

        assertThat(bothWays(caregiver, linked)).isTrue();
        assertThat(bothWays(caregiver, other)).isFalse();
        assertThat(bothWays(linked, other)).isFalse();
    }
}
