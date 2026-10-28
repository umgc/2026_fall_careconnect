package com.careconnect.controller;

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
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Spy;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * PR #419's checks on {@code POST /v1/api/messages/send} over HTTP: Test Plan IDs TC-MSG-SEC-016…018 (DEF-MSG-02,
 * and the client-set fields the PR stops saving).
 * <p>
 * As in {@link MessageControllerAttachmentHttpTest}, the controller runs with the real {@link AuthorizationService}
 * and {@link GlobalExceptionHandler}, so these show the status and body a caller receives. They also bind the request
 * body with Spring's real JSON converter, which the unit tests in {@link MessageControllerTest} skip: only here does a
 * client-sent {@code id} or {@code attachmentId} actually reach the controller. {@link MessagingPolicy} is mocked
 * (its rule is MessagingPolicyTest's and MessagingPolicyIntegrationTest's); the {@code SEND_MESSAGES} aspect is not
 * active in a standalone MockMvc.
 */
@ExtendWith(MockitoExtension.class)
class MessageControllerSendHttpTest {

    /** The signed-in user. */
    private static final long ALICE = 1L;
    /** The receiver. */
    private static final long PEER = 3L;

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
            mock(CaregiverPatientLinkRepository.class), mock(FamilyMemberLinkRepository.class));
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

    private ResultActions send(final String json) throws Exception {
        return mvc.perform(post("/v1/api/messages/send")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    @Test
    @DisplayName("TC-MSG-SEC-016 a pair that may not message each other gets 403 \"You can't send messages to this user.\" "
            + "and nothing is saved")
    void notAllowed_returns403WithMessageAndSavesNothing() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(ALICE, Role.PATIENT));
        when(messagingPolicy.canMessage(ALICE, PEER)).thenReturn(false);

        send("{\"senderId\":" + ALICE + ",\"receiverId\":" + PEER + ",\"content\":\"hi\"}")
                .andExpect(status().isForbidden())
                .andExpect(content().string(MessageController.NOT_ALLOWED));

        verify(messagingPolicy).canMessage(ALICE, PEER);
        verifyNoInteractions(messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-SEC-017 a body that also sends id, attachmentId, attachment fields, read and timestamp is saved "
            + "with only its sender, receiver and content")
    void clientSetFields_inJson_areNotSaved() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(user(ALICE, Role.PATIENT));
        when(messagingPolicy.canMessage(ALICE, PEER)).thenReturn(true);
        when(messageRepo.save(any(Message.class))).thenAnswer(inv -> inv.getArgument(0));
        final LocalDateTime before = LocalDateTime.now().minusSeconds(1);

        send("{\"id\":77,\"senderId\":" + ALICE + ",\"receiverId\":" + PEER + ",\"content\":\"hi\","
                + "\"attachmentId\":99,\"attachmentName\":\"someone-elses.pdf\","
                + "\"attachmentContentType\":\"application/pdf\",\"attachmentSize\":4096,"
                + "\"read\":true,\"isRead\":true,\"timestamp\":\"2020-01-01T00:00:00\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.senderId").value(ALICE))
                .andExpect(jsonPath("$.receiverId").value(PEER))
                .andExpect(jsonPath("$.content").value("hi"));

        final ArgumentCaptor<Message> saved = ArgumentCaptor.forClass(Message.class);
        verify(messageRepo).save(saved.capture());
        final Message m = saved.getValue();
        assertThat(m.getId()).isNull();
        assertThat(m.getAttachmentId()).isNull();
        assertThat(m.getAttachmentName()).isNull();
        assertThat(m.getAttachmentContentType()).isNull();
        assertThat(m.getAttachmentSize()).isNull();
        assertThat(m.isRead()).isFalse();
        assertThat(m.getTimestamp()).isAfter(before);
        assertThat(m.getSenderId()).isEqualTo(ALICE);
        assertThat(m.getReceiverId()).isEqualTo(PEER);
        assertThat(m.getContent()).isEqualTo("hi");
    }

    @Test
    @DisplayName("TC-MSG-SEC-018 a request with no signed-in user gets 403 'User is not authenticated'; the messaging "
            + "rule is not consulted and nothing is saved")
    void signedOut_returns403AndSavesNothing() throws Exception {
        when(securityUtil.resolveCurrentUser()).thenReturn(null);

        send("{\"senderId\":" + ALICE + ",\"receiverId\":" + PEER + ",\"content\":\"hi\"}")
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error").value("User is not authenticated"));

        verifyNoInteractions(messagingPolicy, messageRepo);
    }
}
