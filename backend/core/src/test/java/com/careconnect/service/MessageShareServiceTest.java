package com.careconnect.service;

import com.careconnect.exception.AppException;
import com.careconnect.model.Message;
import com.careconnect.model.Message.ShareKind;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
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

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

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
    @InjectMocks
    private MessageShareService service;

    private User patientUser;
    private User caregiverUser;

    @BeforeEach
    void setUp() {
        patientUser = User.builder().id(PATIENT_USER).role(Role.PATIENT).email("p@test").password("x").status("ACTIVE").build();
        caregiverUser = User.builder().id(CAREGIVER_USER).role(Role.CAREGIVER).email("c@test").password("x").status("ACTIVE").build();

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
    @DisplayName("saves a card holding only the kind and the patient record id, with fallback text, and pushes it")
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
    @DisplayName("says the caregiver cannot open it yet when the patient has not given consent, and still sends it")
    void share_withoutConsent_receiverCannotView() {
        when(medicareAccess.canAccess(caregiverUser, PATIENT_RECORD)).thenReturn(false);

        final MessageShareService.ShareResult result = service.share(patientUser, CAREGIVER_USER, "MEDICARE");

        assertThat(result.receiverCanView()).isFalse();
        verify(messages).save(any(Message.class));
        verify(chatSocket).deliver(result.message());
    }

    @Test
    @DisplayName("a HEALTH card opens the Health tab, which the link alone admits, so the caregiver can always view it")
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
    @DisplayName("a HEALTH card is refused like any other for a caregiver who is not linked (403)")
    void share_health_notLinkedCaregiver_forbidden() {
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "HEALTH"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }

    @Test
    @DisplayName("accepts the kind in any case")
    void share_kindIsCaseInsensitive() {
        assertThat(service.share(patientUser, CAREGIVER_USER, " medicare ").message().getShareKind())
                .isEqualTo(ShareKind.MEDICARE);
    }

    @Test
    @DisplayName("refuses a sender who is not a patient (403)")
    void share_nonPatient_forbidden() {
        assertRefused(() -> service.share(caregiverUser, PATIENT_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }

    @Test
    @DisplayName("refuses when there is no signed-in user (403)")
    void share_noSender_forbidden() {
        assertRefused(() -> service.share(null, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }

    @Test
    @DisplayName("refuses a patient account with no patient record (403)")
    void share_noPatientRecord_forbidden() {
        when(patients.findByUserId(PATIENT_USER)).thenReturn(Optional.empty());

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessageShareService.ONLY_PATIENT);
    }

    @Test
    @DisplayName("refuses an unknown or missing kind (400)")
    void share_unknownKind_badRequest() {
        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "LAB_RESULTS"),
                HttpStatus.BAD_REQUEST, MessageShareService.UNKNOWN_KIND);
        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, null),
                HttpStatus.BAD_REQUEST, MessageShareService.UNKNOWN_KIND);
    }

    @Test
    @DisplayName("refuses a missing receiver (400)")
    void share_noReceiver_badRequest() {
        assertRefused(() -> service.share(patientUser, null, "MEDICARE"),
                HttpStatus.BAD_REQUEST, MessageShareService.NO_RECEIVER);
    }

    @Test
    @DisplayName("refuses a receiver who is not this patient's linked caregiver, such as a friend (403)")
    void share_notLinkedCaregiver_forbidden() {
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }

    @Test
    @DisplayName("refuses a linked caregiver whose link has messaging off (403)")
    void share_messagingOff_forbidden() {
        when(messagingPolicy.canMessage(PATIENT_USER, CAREGIVER_USER)).thenReturn(false);

        assertRefused(() -> service.share(patientUser, CAREGIVER_USER, "MEDICARE"),
                HttpStatus.FORBIDDEN, MessagingPolicy.NOT_ALLOWED);
    }
}
