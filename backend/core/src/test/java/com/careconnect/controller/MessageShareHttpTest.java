package com.careconnect.controller;

import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.Message;
import com.careconnect.model.Message.ShareKind;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ehr.MedicareProperties;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.MedicareAccessPolicy;
import com.careconnect.security.Role;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.MessageShareService;
import com.careconnect.service.MessagingPolicy;
import com.careconnect.service.ehr.MedicareConnectionService;
import com.careconnect.service.ehr.MedicareConnectionService.ConnectionStatus;
import com.careconnect.util.SecurityUtil;
import com.careconnect.websocket.ChatMessageWebSocketHandler;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;
import org.springframework.http.MediaType;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PR #420's share card over HTTP: Test Plan IDs TC-MSG-SHR-025…031, Software Test Plan §3.35.
 * <p>
 * {@link MessageControllerTest} calls {@code share} directly with a mocked {@link MessageShareService}, so it shows
 * neither the request body Spring binds nor the status and body a caller gets. Here the controller runs with the real
 * {@link MessageShareService} behind it, the real JSON converter and {@link GlobalExceptionHandler}, as in
 * {@link MessageControllerSendHttpTest}. What the service consults (the link, the messaging rule, Medicare consent and
 * connection) is mocked: its rules are MessageShareIntegrationTest's. The {@code SEND_MESSAGES} aspect is not active in
 * a standalone MockMvc.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
class MessageShareHttpTest {

    /** User ids, which links and messages are keyed by. */
    private static final long PATIENT_USER = 100L;
    private static final long CAREGIVER_USER = 300L;
    /** The signed-in patient's record id, deliberately different from the user id. */
    private static final long PATIENT_RECORD = 10L;
    /** Another patient's record id, which a client might try to name. */
    private static final long OTHER_RECORD = 77L;

    @Mock
    private MessageRepository messageRepo;
    @Mock
    private UserRepository userRepo;
    @Mock
    private PatientRepository patientRepo;
    @Mock
    private CaregiverRepository caregiverRepo;
    @Mock
    private MessagingPolicy messagingPolicy;
    @Mock
    private FileManagementService fileManagementService;
    @Mock
    private SecurityUtil securityUtil;
    @Spy
    private AuthorizationService authorizationService = new AuthorizationService(
            mock(CaregiverPatientLinkRepository.class), mock(FamilyMemberLinkRepository.class),
            mock(PatientRepository.class));
    @InjectMocks
    private MessageController controller;

    @Mock
    private CaregiverPatientLinkService linkService;
    @Mock
    private MedicareAccessPolicy medicareAccess;
    @Mock
    private ChatMessageWebSocketHandler chatSocket;
    @Mock
    private MedicareConnectionService medicareConnectionService;
    @Mock
    private MedicareProperties medicareProperties;

    private MockMvc mvc;
    private User patient;
    private User caregiver;

    @BeforeEach
    void setUp() {
        final MessageShareService shareService = new MessageShareService(messageRepo, patientRepo, userRepo,
                linkService, messagingPolicy, medicareAccess, chatSocket, medicareConnectionService, medicareProperties);
        ReflectionTestUtils.setField(controller, "messageShareService", shareService);
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();

        patient = user(PATIENT_USER, Role.PATIENT);
        caregiver = user(CAREGIVER_USER, Role.CAREGIVER);
        final Patient record = new Patient();
        record.setId(PATIENT_RECORD);
        record.setUser(patient);
        when(patientRepo.findByUserId(PATIENT_USER)).thenReturn(Optional.of(record));
        when(userRepo.findById(CAREGIVER_USER)).thenReturn(Optional.of(caregiver));
        when(messageRepo.save(any(Message.class))).thenAnswer(inv -> {
            final Message m = inv.getArgument(0);
            ReflectionTestUtils.setField(m, "id", 5L);
            return m;
        });
        // A linked caregiver with messaging on, and Medicare connected, unless a test says otherwise
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(true);
        when(messagingPolicy.canMessage(PATIENT_USER, CAREGIVER_USER)).thenReturn(true);
        when(medicareConnectionService.status(anyLong()))
                .thenReturn(new ConnectionStatus(true, "LINKED", LocalDateTime.now()));
    }

    private static User user(final long id, final Role role) {
        return User.builder().id(id).email("user" + id + "@test.invalid")
                .role(role).password("p").status("ACTIVE").build();
    }

    private ResultActions share(final String json) throws Exception {
        return mvc.perform(post("/v1/api/messages/share")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private void assertNothingSentOrSaved() {
        verify(messageRepo, never()).save(any(Message.class));
        verifyNoInteractions(chatSocket);
    }

    @Test
    @DisplayName("TC-MSG-SHR-025 a patient posting {receiverId, kind:\"medicare\"} gets 200 with the saved card "
            + "(shareKind, sharePatientId, fallback text) and receiverCanView")
    void share_lowerCaseKind_returnsCardAndReceiverCanView() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(medicareAccess.canAccess(caregiver, PATIENT_RECORD)).thenReturn(false);

        share("{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"medicare\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.receiverCanView").value(false))
                .andExpect(jsonPath("$.message.id").value(5))
                .andExpect(jsonPath("$.message.senderId").value(PATIENT_USER))
                .andExpect(jsonPath("$.message.receiverId").value(CAREGIVER_USER))
                .andExpect(jsonPath("$.message.shareKind").value("MEDICARE"))
                .andExpect(jsonPath("$.message.sharePatientId").value(PATIENT_RECORD))
                .andExpect(jsonPath("$.message.content").value("Shared my Medicare records"));

        verify(chatSocket).deliver(any(Message.class));
    }

    @Test
    @DisplayName("TC-MSG-SHR-026 a body that also names a sender, a patient and a sharePatientId of someone else "
            + "still saves a card from the signed-in patient about their own record")
    void share_clientNamedPatient_isIgnored() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);

        share("{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"HEALTH\",\"senderId\":999,\"patientId\":"
                + OTHER_RECORD + ",\"sharePatientId\":" + OTHER_RECORD + ",\"shareKind\":\"MEDICARE\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message.senderId").value(PATIENT_USER))
                .andExpect(jsonPath("$.message.shareKind").value("HEALTH"))
                .andExpect(jsonPath("$.message.sharePatientId").value(PATIENT_RECORD))
                .andExpect(jsonPath("$.receiverCanView").value(true));

        final ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageRepo).save(saved.capture());
        assertThat(saved.getValue().getSharePatientId()).isEqualTo(PATIENT_RECORD);
        assertThat(saved.getValue().getSenderId()).isEqualTo(PATIENT_USER);
    }

    @Test
    @DisplayName("TC-MSG-SHR-027 a caregiver sharing, or no signed-in user, gets 403 {\"error\":\"Only a patient can "
            + "share their records.\"}; a patient sharing with an unlinked user gets 403 {\"error\":\"You can't send "
            + "messages to this user.\"}; nothing is saved or pushed")
    void share_refusals_return403WithError() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        share("{\"receiverId\":" + PATIENT_USER + ",\"kind\":\"MEDICARE\"}")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("Only a patient can share their records."));

        when(securityUtil.resolveCurrentUser()).thenReturn(null);
        share("{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"MEDICARE\"}")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("Only a patient can share their records."));

        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(linkService.hasAccessToPatient(CAREGIVER_USER, PATIENT_USER)).thenReturn(false);
        share("{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"HEALTH\"}")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value(MessagingPolicy.NOT_ALLOWED));

        assertNothingSentOrSaved();
    }

    @Test
    @DisplayName("TC-MSG-SHR-028 an unknown, empty or missing kind, or a missing receiverId, gets 400 with its error "
            + "message; nothing is saved or pushed")
    void share_badBodies_return400() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);

        for (final String body : new String[]{
                "{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"LAB_RESULTS\"}",
                "{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"\"}",
                "{\"receiverId\":" + CAREGIVER_USER + "}"}) {
            share(body)
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error").value("Unknown share kind."));
        }
        share("{\"kind\":\"MEDICARE\"}")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("receiverId is required."));

        assertNothingSentOrSaved();
    }

    @Test
    @DisplayName("TC-MSG-SHR-029 a MEDICARE card from a patient without Medicare connected gets 409 {\"error\":"
            + "\"Connect Medicare before sharing it.\"}; in mock mode the same request gets 200 (DEF-MSG-05)")
    void share_medicareNotConnected_409_butNotInMockMode() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        when(medicareConnectionService.status(anyLong())).thenReturn(new ConnectionStatus(false, "UNLINKED", null));

        share("{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"MEDICARE\"}")
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error").value("Connect Medicare before sharing it."));
        assertNothingSentOrSaved();

        when(medicareProperties.isMock()).thenReturn(true);
        share("{\"receiverId\":" + CAREGIVER_USER + ",\"kind\":\"MEDICARE\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.message.shareKind").value("MEDICARE"));
    }

    @Test
    @DisplayName("TC-MSG-SHR-030 /send cannot forge a share card: shareKind and sharePatientId in its body are not "
            + "saved")
    void send_cannotForgeShareCard() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(CAREGIVER_USER, Role.CAREGIVER));
        when(messagingPolicy.canMessage(CAREGIVER_USER, PATIENT_USER)).thenReturn(true);

        mvc.perform(post("/v1/api/messages/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"senderId\":" + CAREGIVER_USER + ",\"receiverId\":" + PATIENT_USER
                                + ",\"content\":\"Shared my Medicare records\",\"shareKind\":\"MEDICARE\","
                                + "\"sharePatientId\":" + OTHER_RECORD + "}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.shareKind").doesNotExist())
                .andExpect(jsonPath("$.sharePatientId").doesNotExist());

        final ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageRepo).save(saved.capture());
        assertThat(saved.getValue().getShareKind()).isNull();
        assertThat(saved.getValue().getSharePatientId()).isNull();
        verifyNoInteractions(chatSocket);
    }

    @Test
    @DisplayName("TC-MSG-SHR-031 GET /conversation returns a share card with shareKind and sharePatientId, which "
            + "the app needs to draw it after a reload; a plain message has neither")
    void conversation_carriesShareFields() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(caregiver);
        final Message card = new Message(PATIENT_USER, CAREGIVER_USER, "Shared my health information");
        ReflectionTestUtils.setField(card, "id", 5L);
        card.setShareKind(ShareKind.HEALTH);
        card.setSharePatientId(PATIENT_RECORD);
        final Message plain = new Message(PATIENT_USER, CAREGIVER_USER, "hi");
        ReflectionTestUtils.setField(plain, "id", 6L);
        when(messageRepo.findConversation(CAREGIVER_USER, PATIENT_USER)).thenReturn(List.of(card, plain));

        mvc.perform(get("/v1/api/messages/conversation")
                        .param("user1", String.valueOf(CAREGIVER_USER))
                        .param("user2", String.valueOf(PATIENT_USER)))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(jsonPath("$[0].shareKind").value("HEALTH"))
                .andExpect(jsonPath("$[0].sharePatientId").value(PATIENT_RECORD))
                .andExpect(jsonPath("$[1].shareKind").doesNotExist())
                .andExpect(jsonPath("$[1].sharePatientId").doesNotExist());
    }
}
