package com.careconnect.controller;

import com.careconnect.dto.FileUploadResponse;
import com.careconnect.exception.GlobalExceptionHandler;
import com.careconnect.model.Message;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverPatientLinkRepository;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.FamilyMemberLinkRepository;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.MessagingPolicy;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.multipart.MultipartFile;

import java.nio.charset.StandardCharsets;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PR #386's sender check on {@code POST /v1/api/messages/send-attachment} over HTTP: Test Plan IDs
 * TC-MSG-SEC-003…008 (DEF-MSG-01).
 * <p>
 * The controller runs with the application's real {@link AuthorizationService} (its
 * {@code requireSelfOrAdmin} reads no repository) and the real {@link GlobalExceptionHandler}, so these show the
 * status and body a caller receives, which the unit tests in {@link MessageControllerTest} cannot. The signed-in
 * user comes from a mocked {@link SecurityUtil}; the {@code @RequirePermission(SEND_MESSAGES)} aspect is not active
 * in a standalone MockMvc, so the permission itself is not tested here.
 */
@ExtendWith(MockitoExtension.class)
class MessageControllerAttachmentHttpTest {

    /** The signed-in user. */
    private static final long ALICE = 1L;
    /** Another user, who may message {@link #PEER}. */
    private static final long BOB = 2L;
    /** The receiver. */
    private static final long PEER = 3L;
    private static final long ADMIN = 99L;
    private static final String NOT_OWN_DATA = "You can only access your own data unless you are an administrator";
    private static final String MESSAGING_OFF = MessageController.NOT_ALLOWED;

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

    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        mvc = MockMvcBuilders.standaloneSetup(controller)
                .setControllerAdvice(new GlobalExceptionHandler())
                .build();
    }

    private static User user(final long id, final Role role) {
        return User.builder().id(id).email("user" + id + "@test.invalid")
                .role(role).password("p").status("ACTIVE").build();
    }

    private ResultActions sendAttachment(final long senderId, final long receiverId) throws Exception {
        final MockMultipartFile file = new MockMultipartFile(
                "file", "note.txt", "text/plain", "synthetic test file".getBytes(StandardCharsets.UTF_8));
        return mvc.perform(multipart("/v1/api/messages/send-attachment")
                .file(file)
                .param("senderId", Long.toString(senderId))
                .param("receiverId", Long.toString(receiverId)));
    }

    @Test
    @DisplayName("TC-MSG-SEC-003 another user's senderId gets 403 with the self-or-admin message, even when that user's "
            + "link allows messaging, and nothing is looked up, uploaded or saved")
    void otherUsersSenderId_returns403AndSendsNothing() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(ALICE, Role.PATIENT));
        // Bob may message the peer, so before the fix a request naming Bob passed the messaging check.
        lenient().when(messagingPolicy.canMessage(BOB, PEER)).thenReturn(true);

        sendAttachment(BOB, PEER)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value(NOT_OWN_DATA));

        verifyNoInteractions(messagingPolicy, userRepo, fileManagementService, messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-SEC-004 a request with no signed-in user gets 403 'User is not authenticated' and sends nothing")
    void signedOut_returns403AndSendsNothing() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        sendAttachment(ALICE, PEER)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("User is not authenticated"));

        verifyNoInteractions(messagingPolicy, userRepo, fileManagementService, messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-SEC-005 the signed-in user's own senderId with messaging on gets 200; the file is uploaded and "
            + "the message saved as theirs")
    void ownSenderId_messagingOn_returns200AndSavesAsSignedInUser() throws Exception {
        final User alice = user(ALICE, Role.PATIENT);
        when(securityUtil.resolveCurrentUser()).thenReturn(alice);
        when(messagingPolicy.canMessage(ALICE, PEER)).thenReturn(true);
        when(userRepo.findById(ALICE)).thenReturn(Optional.of(alice));
        when(fileManagementService.uploadFile(any(MultipartFile.class), eq(ALICE), eq("PATIENT"),
                eq("CHAT_ATTACHMENT"), eq("Chat attachment"), isNull()))
                .thenReturn(FileUploadResponse.builder().fileId(70L)
                        .originalFilename("note.txt").contentType("text/plain").build());
        when(messageRepo.save(any(Message.class))).thenAnswer(inv -> inv.getArgument(0));

        sendAttachment(ALICE, PEER)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.downloadUrl").value("/v1/api/files/70/download"))
                .andExpect(jsonPath("$.message.senderId").value(ALICE))
                .andExpect(jsonPath("$.message.receiverId").value(PEER))
                .andExpect(jsonPath("$.message.attachmentId").value(70));

        verify(authorizationService).requireSelfOrAdmin(alice, ALICE);
    }

    @Test
    @DisplayName("TC-MSG-SEC-006 the signed-in user's own senderId, to someone they may not message, still gets the "
            + "messaging refusal (403) and nothing is uploaded")
    void ownSenderId_messagingOff_returnsLinkRefusal() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(ALICE, Role.PATIENT));
        when(messagingPolicy.canMessage(ALICE, PEER)).thenReturn(false);

        sendAttachment(ALICE, PEER)
                .andExpect(status().isForbidden())
                .andExpect(content().string(MESSAGING_OFF));

        verifyNoInteractions(fileManagementService, messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-SEC-007 an administrator naming another user as sender passes the sender check (as on /send); "
            + "the messaging check still applies")
    void admin_otherUsersSenderId_passesSenderCheck_linkCheckStillApplies() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(ADMIN, Role.ADMIN));
        when(messagingPolicy.canMessage(BOB, PEER)).thenReturn(false);

        sendAttachment(BOB, PEER)
                .andExpect(status().isForbidden())
                .andExpect(content().string(MESSAGING_OFF));

        verify(messagingPolicy).canMessage(BOB, PEER);
        verifyNoInteractions(fileManagementService, messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-SEC-008 /send and /send-attachment refuse another user's senderId with the same 403 and body")
    void sendAndSendAttachment_refuseOtherUsersSenderIdAlike() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(ALICE, Role.PATIENT));

        final String sendBody = mvc.perform(post("/v1/api/messages/send")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"senderId\":" + BOB + ",\"receiverId\":" + PEER + ",\"content\":\"hi\"}"))
                .andExpect(status().isForbidden())
                .andReturn().getResponse().getContentAsString();
        final String attachmentBody = sendAttachment(BOB, PEER)
                .andExpect(status().isForbidden())
                .andReturn().getResponse().getContentAsString();

        assertThat(attachmentBody).isEqualTo(sendBody).contains(NOT_OWN_DATA);
        verifyNoInteractions(messageRepo, fileManagementService);
    }
}
