package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.CaregiverPatientLink;
import com.careconnect.model.CaregiverPatientLink.LinkStatus;
import com.careconnect.model.ConsentGrant;
import com.careconnect.model.FriendRequest;
import com.careconnect.model.Message;
import com.careconnect.model.Message.ShareKind;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.MessageRepository;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.ConnectionStatus;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.boot.test.autoconfigure.orm.jpa.TestEntityManager;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.context.transaction.TestTransaction;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * {@link MessageShareService} against real {@code users}, {@code patient}, {@code caregiver_patient_link},
 * {@code friend_requests}, {@code consent_grants} and {@code messages} rows, with the real
 * {@link CaregiverPatientLinkService}, {@link MessagingPolicy} and {@link MedicareAccessPolicy}.
 * <p>
 * MessageShareServiceTest mocks all three, so it proves how the service combines them but not what they mean: that an
 * expired or switched-off link, a friendship or another patient's link is refused, that consent decides
 * {@code receiverCanView}, and that the saved row carries the patient record id. Those depend on the queries, which
 * only run here. The chat socket and the Medicare connection are mocked (the connection's own rule is
 * MedicareConnectionServiceTest's).
 * <p>
 * Test IDs: TC-MSG-SHR-032…039, Software Test Plan §3.35. Runs on the test profile's H2 database, not PostgreSQL.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
@ActiveProfiles("test")
@Import({MessageShareService.class, MessagingPolicy.class, CaregiverPatientLinkService.class,
        MedicareAccessPolicy.class})
class MessageShareIntegrationTest {

    private static final AtomicInteger SEQ = new AtomicInteger();

    @Autowired
    private TestEntityManager em;
    @Autowired
    private MessageShareService service;
    @Autowired
    private CaregiverPatientLinkService linkService;
    @Autowired
    private MessageRepository messages;

    @MockitoBean
    private ChatMessageWebSocketHandler chatSocket;
    @MockitoBean
    private MedicareConnectionService medicareConnections;
    @MockitoBean
    private MedicareProperties medicareProperties;

    @BeforeEach
    void medicareConnected() {
        when(medicareConnections.status(anyLong())).thenReturn(new ConnectionStatus(true, "LINKED", null));
    }

    private User user(final Role role) {
        return em.persistAndFlush(User.builder()
                .email("share-" + SEQ.incrementAndGet() + "@example.test")
                .password("not-a-real-password")
                .role(role)
                .build());
    }

    /** A patient: their account and their {@code patient} row, which has an id of its own. */
    private record PatientAccount(User user, Patient record) {
    }

    private PatientAccount patient() {
        final User account = user(Role.PATIENT);
        final Patient record = new Patient();
        record.setUser(account);
        return new PatientAccount(account, em.persistAndFlush(record));
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

    private CaregiverPatientLink activeLink(final User caregiver, final User patient) {
        return link(caregiver, patient, LinkStatus.ACTIVE, null);
    }

    private ConsentGrant grant(final User patient, final User caregiver) {
        final Instant now = Instant.now();
        return em.persistAndFlush(ConsentGrant.builder()
                .patientUserId(patient.getId())
                .granteeUserId(caregiver.getId())
                .granteeRole(caregiver.getRole().name())
                .scope(MedicareAccessPolicy.SCOPE_MEDICARE_VIEW)
                .status(ConsentGrant.STATUS_ACTIVE)
                .grantedAt(now.minus(1, ChronoUnit.DAYS))
                .createdAt(now)
                .updatedAt(now)
                .build());
    }

    private void assertForbidden(final User sender, final User receiver, final String kind) {
        assertThatThrownBy(() -> service.share(sender, receiver.getId(), kind))
                .isInstanceOf(AppException.class)
                .hasMessage(MessagingPolicy.NOT_ALLOWED)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(messages.findConversation(sender.getId(), receiver.getId())).as("nothing saved").isEmpty();
    }

    @Test
    @DisplayName("TC-MSG-SHR-032 a patient shares a MEDICARE card with a linked, consented caregiver: the row reads "
            + "back from the conversation with share_kind and the patient record id, which is not the user id")
    void linkedConsentedCaregiver_cardSavedWithRecordId() {
        // The caregiver's account first, so the patient's user id runs ahead of their record id
        final User caregiver = user(Role.CAREGIVER);
        final PatientAccount patient = patient();
        assertThat(patient.record().getId()).isNotEqualTo(patient.user().getId());
        activeLink(caregiver, patient.user());
        grant(patient.user(), caregiver);

        final MessageShareService.ShareResult result = service.share(patient.user(), caregiver.getId(), "medicare");
        em.flush();
        em.clear();

        assertThat(result.receiverCanView()).isTrue();
        final List<Message> conversation = messages.findConversation(patient.user().getId(), caregiver.getId());
        assertThat(conversation).hasSize(1);
        final Message card = conversation.get(0);
        assertThat(card.getShareKind()).isEqualTo(ShareKind.MEDICARE);
        assertThat(card.getSharePatientId()).isEqualTo(patient.record().getId());
        assertThat(card.getSenderId()).isEqualTo(patient.user().getId());
        assertThat(card.getReceiverId()).isEqualTo(caregiver.getId());
        assertThat(card.getContent()).isEqualTo("Shared my Medicare records");
    }

    @Test
    @DisplayName("TC-MSG-SHR-033 receiverCanView follows the patient's MEDICARE_VIEW consent: false without it, true "
            + "with it, false again once it is revoked; the card is sent each time")
    void receiverCanView_followsConsent() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        assertThat(service.share(patient.user(), caregiver.getId(), "MEDICARE").receiverCanView())
                .as("no consent").isFalse();

        final ConsentGrant consent = grant(patient.user(), caregiver);
        assertThat(service.share(patient.user(), caregiver.getId(), "MEDICARE").receiverCanView())
                .as("consent given").isTrue();

        consent.setStatus(ConsentGrant.STATUS_REVOKED);
        consent.setRevokedAt(Instant.now());
        em.persistAndFlush(consent);
        assertThat(service.share(patient.user(), caregiver.getId(), "MEDICARE").receiverCanView())
                .as("consent revoked").isFalse();

        assertThat(messages.findConversation(patient.user().getId(), caregiver.getId())).hasSize(3);
    }

    @Test
    @DisplayName("TC-MSG-SHR-034 a caregiver whose ACTIVE link has expired, or whose link is pending or revoked, "
            + "cannot be sent a card (403)")
    void expiredOrInactiveLink_refused() {
        final PatientAccount patient = patient();
        final User expired = user(Role.CAREGIVER);
        link(expired, patient.user(), LinkStatus.ACTIVE, LocalDateTime.now().minusDays(1));
        assertForbidden(patient.user(), expired, "HEALTH");

        for (final LinkStatus status : new LinkStatus[]{LinkStatus.PENDING, LinkStatus.REVOKED}) {
            final User caregiver = user(Role.CAREGIVER);
            link(caregiver, patient.user(), status, null);
            assertForbidden(patient.user(), caregiver, "HEALTH");
        }
    }

    @Test
    @DisplayName("TC-MSG-SHR-035 a linked caregiver whose link has messaging switched off cannot be sent a card "
            + "(403); switched back on, they can")
    void messagingOff_refused() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        final CaregiverPatientLink l = activeLink(caregiver, patient.user());
        linkService.setPatientMessagingEnabled(l.getId(), false, caregiver.getId(), Role.CAREGIVER);
        em.flush();
        em.clear();

        assertForbidden(patient.user(), caregiver, "HEALTH");

        linkService.setPatientMessagingEnabled(l.getId(), true, caregiver.getId(), Role.CAREGIVER);
        em.flush();
        em.clear();
        assertThat(service.share(patient.user(), caregiver.getId(), "HEALTH").message().getShareKind())
                .isEqualTo(ShareKind.HEALTH);
    }

    @Test
    @DisplayName("TC-MSG-SHR-036 a friend the patient may message, but who is not their linked caregiver, cannot be "
            + "sent a card (403)")
    void friendOnly_refused() {
        final PatientAccount patient = patient();
        final User friend = user(Role.CAREGIVER);
        final FriendRequest r = new FriendRequest();
        r.setFromUserId(patient.user().getId());
        r.setToUserId(friend.getId());
        r.setStatus("accepted");
        em.persistAndFlush(r);

        assertForbidden(patient.user(), friend, "HEALTH");
    }

    @Test
    @DisplayName("TC-MSG-SHR-037 a caregiver linked to another patient, or the patient themselves, cannot be sent a "
            + "card (403)")
    void otherPatientsCaregiver_orSelf_refused() {
        final PatientAccount patient = patient();
        final PatientAccount other = patient();
        final User othersCaregiver = user(Role.CAREGIVER);
        activeLink(othersCaregiver, other.user());
        grant(other.user(), othersCaregiver);

        assertForbidden(patient.user(), othersCaregiver, "MEDICARE");
        assertForbidden(patient.user(), patient.user(), "MEDICARE");
    }

    @Test
    @DisplayName("TC-MSG-SHR-038 a HEALTH card to a linked caregiver without Medicare consent says they can view it, "
            + "as the Health tab needs only the link")
    void healthCard_linkEnough() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        final MessageShareService.ShareResult result = service.share(patient.user(), caregiver.getId(), "HEALTH");

        assertThat(result.receiverCanView()).isTrue();
        assertThat(result.message().getSharePatientId()).isEqualTo(patient.record().getId());
    }

    @Test
    @DisplayName("TC-MSG-SHR-039 the card reaches the caregiver's socket only when the transaction commits, and "
            + "never when it rolls back (DEF-MSG-04)")
    void deliveredOnlyAfterCommit() {
        final PatientAccount patient = patient();
        final User caregiver = user(Role.CAREGIVER);
        activeLink(caregiver, patient.user());

        // Rolled back: no push
        service.share(patient.user(), caregiver.getId(), "HEALTH");
        verify(chatSocket, never()).deliver(any(Message.class));
        TestTransaction.flagForRollback();
        TestTransaction.end();
        verify(chatSocket, never()).deliver(any(Message.class));

        // The rows above were rolled back with it; set the pair up again and commit
        TestTransaction.start();
        final PatientAccount p2 = patient();
        final User c2 = user(Role.CAREGIVER);
        activeLink(c2, p2.user());
        final Message saved = service.share(p2.user(), c2.getId(), "HEALTH").message();
        verify(chatSocket, never()).deliver(any(Message.class));
        TestTransaction.flagForCommit();
        TestTransaction.end();
        verify(chatSocket).deliver(saved);
    }
}
