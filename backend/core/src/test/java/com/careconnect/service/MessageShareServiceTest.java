package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.Message;
import com.careconnect.model.Message.ShareKind;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import lombok.extern.slf4j.Slf4j;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

@Slf4j
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("MessageShareService: a patient shares data with a caregiver as a chat card")
class MessageShareServiceTest {

    /** User ids, which links and messages are keyed by. */
    private static final long PATIENT_USER = 100L;
    private static final long CAREGIVER_USER = 300L;
    /** The patient record id, deliberately different from the user id, as for most real accounts. */
    private static final long PATIENT_RECORD = 10L;

    @Mock
    private MessageRepository messages;
    @Mock
    private PatientRepository patients;
    @Mock
    private UserRepository users;
    @Mock
    private CaregiverPatientLinkService linkService;
    @Mock
    private MessagingPolicy messagingPolicy;
    @Mock
    private MedicareAccessPolicy medicareAccess;
    @Mock
    private ChatMessageWebSocketHandler chatSocket;
    @Mock
    private MedicareConnectionService medicareConnectionService;
    /** Live mode unless a test says otherwise: isMock() is false on a plain mock. */
    @Mock
    private MedicareProperties medicareProperties;

    @InjectMocks
    private MessageShareService service;

    private User patientUser;
    private User caregiverUser;
    private MedicareConnectionService.ConnectionStatus linked;
    private MedicareConnectionService.ConnectionStatus unlinked;

    @BeforeEach
    void setUp() {
        patientUser = User.builder().id(PATIENT_USER).role(Role.PATIENT).email("p@test").password("x").status("ACTIVE").build();
        caregiverUser = User.builder().id(CAREGIVER_USER).role(Role.CAREGIVER).email("c@test").password("x").status("ACTIVE").build();

        linked = new MedicareConnectionService.ConnectionStatus(true, "LINKED", LocalDateTime.now().plusDays(1));
        unlinked = MedicareConnectionService.ConnectionStatus.unlinked();
        when(medicareConnectionService.status(anyLong())).thenReturn(linked);


        final Patient patient = new Patient();
        patient.setId(PATIENT_RECORD);
        patient.setUser(patientUser);
        when(patients.findByUserId(PATIENT_USER)).thenReturn(Optional.of(patient));
        when(users.findById(CAREGIVER_USER)).thenReturn(Optional.of(caregiverUser));
        when(messages.save(any(Message.class))).thenAnswer(inv -> inv.getArgument(0));

        // A linked caregiver with messaging on, unless a test says otherwise
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(true);
        when(messagingPolicy.canMessage(PATIENT_USER, CAREGIVER_USER)).thenReturn(true);
    }

    private void assertRefused(final Runnable call, final HttpStatus status, final String message) {
        assertThatThrownBy(call::run)
                .isInstanceOf(AppException.class)
                .hasMessage(message)
                .extracting(e -> ((AppException) e).getStatus())
                .isEqualTo(status);
        verify(messages, never()).save(any(Message.class));
        verifyNoInteractions(chatSocket);
    }

    @Test
    @DisplayName("TC-MSG-SHR-001 saves a card holding only the kind and the patient record id, with fallback text, and pushes it")
    void share_savesCardAndDelivers() {
        when(medicareAccess.canAccess(caregiverUser, PATIENT_RECORD)).thenReturn(true);

        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "MEDICARE");

        final Message card = result.message();
        assertThat(card.getSenderId()).isEqualTo(PATIENT_USER);
        assertThat(card.getReceiverId()).isEqualTo(CAREGIVER_USER);
        assertThat(card.getShareKind()).isEqualTo(ShareKind.MEDICARE);
        assertThat(card.getSharePatientId()).isEqualTo(PATIENT_RECORD);
        assertThat(card.getContent()).isEqualTo("Shared my Medicare records");
        assertThat(card.getAttachmentId()).isNull();
        assertThat(card.isRead()).isFalse();
        assertThat(result.receiverCanView()).isTrue();
        verify(chatSocket).deliver(card);
    }

    @Test
    @DisplayName("TC-MSG-SHR-002 says the caregiver cannot open it yet when the patient has not given consent, and still sends it")
    void share_withoutConsent_receiverCannotView() {
        when(medicareAccess.canAccess(caregiverUser, PATIENT_RECORD)).thenReturn(false);

        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "MEDICARE");

        assertThat(result.receiverCanView()).isFalse();
        verify(messages).save(any(Message.class));
        verify(chatSocket).deliver(result.message());
    }

    @Test
    @DisplayName("TC-MSG-SHR-003 a HEALTH card opens the Health tab, which the link alone admits, so the caregiver can always view it")
    void share_health_receiverCanViewWithoutConsentCheck() {
        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "HEALTH");

        final Message card = result.message();
        assertThat(card.getShareKind()).isEqualTo(ShareKind.HEALTH);
        assertThat(card.getSharePatientId()).isEqualTo(PATIENT_RECORD);
        assertThat(card.getContent()).isEqualTo("Shared my health information");
        assertThat(result.receiverCanView()).isTrue();
        verifyNoInteractions(medicareAccess);
        verify(chatSocket).deliver(card);
    }

    @Test
    @DisplayName("TC-MSG-SHR-004 a HEALTH card is refused like any other for a caregiver who is not linked (403)")
    void share_health_notLinkedCaregiver_forbidden() {
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "HEALTH"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }

    @Test
    @DisplayName("TC-MSG-SHR-005 accepts the kind in any case")
    void share_kindIsCaseInsensitive() {
        assertThat(service.share(patientUser, CAREGIVER_USER, " medicare ").message().getShareKind())
                .isEqualTo(ShareKind.MEDICARE);
    }

    @Test
    @DisplayName("TC-MSG-SHR-006 refuses a sender who is not a patient (403)")
    void share_nonPatient_forbidden() {
        assertRefused(() -> service.share(caregiverUser, PATIENT_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }

    @Test
    @DisplayName("TC-MSG-SHR-007 refuses when there is no signed-in user (403)")
    void share_noSender_forbidden() {
        assertRefused(() -> service.share(null, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }

    @Test
    @DisplayName("TC-MSG-SHR-008 refuses a patient account with no patient record (403)")
    void share_noPatientRecord_forbidden() {
        when(patients.findByUserId(PATIENT_USER)).thenReturn(Optional.empty());

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }

    @Test
    @DisplayName("TC-MSG-SHR-009 refuses an unknown or missing kind (400)")
    void share_unknownKind_badRequest() {
        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "LAB_RESULTS"),
                HttpStatus.BAD_REQUEST, MessageShareService.UNKNOWN_KIND);
        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, null),
                HttpStatus.BAD_REQUEST, MessageShareService.UNKNOWN_KIND);
    }

    @Test
    @DisplayName("TC-MSG-SHR-010 refuses a missing receiver (400)")
    void share_noReceiver_badRequest() {
        assertRefused(() -> service.share(patientUser, null, "MEDICARE"),
                HttpStatus.BAD_REQUEST, MessageShareService.NO_RECEIVER);
    }

    @Test
    @DisplayName("TC-MSG-SHR-011 refuses a receiver who is not this patient's linked caregiver, such as a friend (403)")
    void share_notLinkedCaregiver_forbidden() {
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }

    @Test
    @DisplayName("TC-MSG-SHR-012 refuses a linked caregiver whose link has messaging off (403)")
    void share_messagingOff_forbidden() {
        when(messagingPolicy.canMessage(PATIENT_USER, CAREGIVER_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }

    @Test
    @DisplayName("TC-MSG-SHR-013 Refuses a patient who is trying to send medicare data without being connected to medicare (409)")
    void share_noMedicareData_conflict(){
        when(medicareConnectionService.status(anyLong())).thenReturn(unlinked);
        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.CONFLICT, MessageShareService.CONNECT_MEDICARE);
    }

    // ─── Testing Lead additions (PR #420 review): TC-MSG-SHR-015…024 ─────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-SHR-015 a patient with Medicare connected shares a MEDICARE card; the check asks about the "
            + "patient record id, not the user id")
    void share_medicareConnected_sent() {
        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "MEDICARE");

        assertThat(result.message().getShareKind()).isEqualTo(ShareKind.MEDICARE);
        verify(medicareConnectionService).status(PATIENT_RECORD);
        verify(medicareConnectionService, never()).status(PATIENT_USER);
        verify(chatSocket).deliver(result.message());
    }

    @Test
    @DisplayName("TC-MSG-SHR-016 in mock mode a MEDICARE card is sent though no Medicare connection is saved, as the "
            + "Medicare tile shows connected (DEF-MSG-05)")
    void share_mockMode_notConnected_sent() {
        when(medicareProperties.isMock()).thenReturn(true);
        when(medicareConnectionService.status(anyLong())).thenReturn(unlinked);

        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "MEDICARE");

        assertThat(result.message().getShareKind()).isEqualTo(ShareKind.MEDICARE);
        verify(messages).save(any(Message.class));
        verify(chatSocket).deliver(result.message());
    }

    @Test
    @DisplayName("TC-MSG-SHR-017 a HEALTH card is sent whether or not Medicare is connected: the 409 is for MEDICARE "
            + "cards only")
    void share_health_medicareNotConnected_sent() {
        when(medicareConnectionService.status(anyLong())).thenReturn(unlinked);

        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "HEALTH");

        assertThat(result.message().getShareKind()).isEqualTo(ShareKind.HEALTH);
        verifyNoInteractions(medicareConnectionService);
        verify(chatSocket).deliver(result.message());
    }

    @Test
    @DisplayName("TC-MSG-SHR-018 a receiver who is not this patient's linked caregiver gets the 403, not the 409, so "
            + "a refused share never tells them whether the patient has Medicare connected")
    void share_notLinked_medicareNotConnected_403Not409() {
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);
        when(medicareConnectionService.status(anyLong())).thenReturn(unlinked);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
        verifyNoInteractions(medicareConnectionService);
    }

    @Test
    @DisplayName("TC-MSG-SHR-019 the link is checked with the receiver as caregiver and the signed-in patient as "
            + "patient, never the other way round")
    void share_linkCheckedCaregiverThenPatient() {
        when(linkService.hasAccessToPatient(PATIENT_USER, CAREGIVER_USER)).thenReturn(true);
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "HEALTH"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }

    @Test
    @DisplayName("TC-MSG-SHR-020 a blank kind, or a sender account without an id, is refused before anything is "
            + "looked up")
    void share_blankKind_or_senderWithoutId_refused() {
        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "   "),
                HttpStatus.BAD_REQUEST, MessageShareService.UNKNOWN_KIND);

        final User noId = User.builder().role(Role.PATIENT).email("n@test").password("x").status("ACTIVE").build();
        assertRefused(() -> service.share(noId, CAREGIVER_USER, "HEALTH"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
        verifyNoInteractions(patients, linkService, messagingPolicy);
    }

    @Test
    @DisplayName("TC-MSG-SHR-021 a MEDICARE card to a receiver whose account cannot be found still saves, and says "
            + "they cannot view it")
    void share_receiverAccountMissing_cannotView() {
        when(users.findById(CAREGIVER_USER)).thenReturn(Optional.empty());

        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "MEDICARE");

        assertThat(result.receiverCanView()).isFalse();
        verify(medicareAccess).canAccess(null, PATIENT_RECORD);
    }

    @Test
    @DisplayName("TC-MSG-SHR-022 receiverCanView asks about the receiver and the patient record, never the sender "
            + "or the user id")
    void share_canViewAsksAboutReceiverAndRecord() {
        when(medicareAccess.canAccess(any(), anyLong())).thenReturn(false);
        when(medicareAccess.canAccess(eq(caregiverUser), eq(PATIENT_RECORD))).thenReturn(true);

        assertThat(service.share(patientUser, CAREGIVER_USER, "MEDICARE").receiverCanView()).isTrue();
        verify(medicareAccess).canAccess(caregiverUser, PATIENT_RECORD);
        verifyNoMoreInteractions(medicareAccess);
    }

    @Test
    @DisplayName("TC-MSG-SHR-023 inside a transaction the card is pushed only after commit, and not at all on "
            + "rollback (DEF-MSG-04)")
    void share_inTransaction_deliversOnlyAfterCommit() {
        TransactionSynchronizationManager.initSynchronization();
        try {
            final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "HEALTH");

            verify(messages).save(any(Message.class));
            verifyNoInteractions(chatSocket);
            for (final TransactionSynchronization sync : TransactionSynchronizationManager.getSynchronizations()) {
                sync.afterCompletion(TransactionSynchronization.STATUS_ROLLED_BACK);
            }
            verifyNoInteractions(chatSocket);
            for (final TransactionSynchronization sync : TransactionSynchronizationManager.getSynchronizations()) {
                sync.afterCommit();
            }
            verify(chatSocket).deliver(result.message());
        } finally {
            TransactionSynchronizationManager.clearSynchronization();
        }
    }

    @Test
    @DisplayName("TC-MSG-SHR-024 a failure while working out receiverCanView saves and pushes nothing (DEF-MSG-04)")
    void share_canViewThrows_nothingSavedOrPushed() {
        when(medicareAccess.canAccess(caregiverUser, PATIENT_RECORD)).thenThrow(new IllegalStateException("db down"));

        assertThatThrownBy(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"))
                .isInstanceOf(IllegalStateException.class);
        verify(messages, never()).save(any(Message.class));
        verifyNoInteractions(chatSocket);
    }

    @Test
    @DisplayName("TC-MSG-SHR-046 a caregiver account that also has a patient record is refused (403): only a patient "
            + "shares")
    void share_caregiverWithPatientRecord_forbidden() {
        final Patient record = new Patient();
        record.setId(99L);
        record.setUser(caregiverUser);
        when(patients.findByUserId(CAREGIVER_USER)).thenReturn(Optional.of(record));
        when(linkService.hasAccessToPatient(PATIENT_USER, CAREGIVER_USER)).thenReturn(true);
        when(messagingPolicy.canMessage(CAREGIVER_USER, PATIENT_USER)).thenReturn(true);

        assertRefused(() -> service.share(caregiverUser, PATIENT_USER, "HEALTH"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }
}
