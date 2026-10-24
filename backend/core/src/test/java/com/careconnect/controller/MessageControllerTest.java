package com.careconnect.controller;

import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.InboxMessageDto;
import com.careconnect.model.Caregiver;
import com.careconnect.model.Message;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.MessageShareService;
import com.careconnect.service.MessagingPolicy;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.multipart.MultipartFile;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * Unit tests for {@link MessageController}. Test Plan IDs: TC-MSG-CTL-001…024 (inherited tests, labelled for
 * PR #386), TC-MSG-SEC-001, 002 (PR #386's sender check on sendAttachment) and TC-MSG-SEC-009…011 (PR #419: who may
 * message whom, and /send saving only sender, receiver and content). The sender check over HTTP, with the real
 * AuthorizationService and GlobalExceptionHandler, is TC-MSG-SEC-003…008 in {@link MessageControllerAttachmentHttpTest}.
 * Who may message whom is {@code MessagingPolicy}'s rule, tested in {@code MessagingPolicyTest}; here it is mocked.
 */
@ExtendWith(MockitoExtension.class)
class MessageControllerTest {

    private static final Long SENDER_ID = 1L;
    private static final Long RECEIVER_ID = 2L;
    @Mock
    private MessageRepository messageRepo;
    @Mock
    private UserRepository userRepo;
    @Mock
    private MessagingPolicy messagingPolicy;
    @Mock
    private MessageShareService messageShareService;
    @Mock
    private FileManagementService fileManagementService;
    @Mock
    private PatientRepository patientRepo;
    @Mock
    private CaregiverRepository caregiverRepo;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private MessageController controller;

    private Message makeMessage(Long id, Long senderId, Long receiverId, String content) {
        final Message m = new Message();
        m.setSenderId(senderId);
        m.setReceiverId(receiverId);
        m.setContent(content);
        m.setTimestamp(LocalDateTime.now());
        m.setRead(false);
        return m;
    }

    private User makeUser(Long id, String name, String email) {
        final User u = new User();
        u.setId(id);
        u.setName(name);
        u.setEmail(email);
        return u;
    }

    // ─── sendMessage ──────────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-CTL-001 sendMessage sets the timestamp and unread flag, then saves the message")
    void sendMessage_setsTimestampAndIsRead_thenSaves() throws Exception {
        final Message inbound = new Message();
        inbound.setSenderId(SENDER_ID);
        inbound.setReceiverId(RECEIVER_ID);
        inbound.setContent("Hello!");

        final User sender = makeUser(SENDER_ID, "Alice", "alice@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(sender);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(true);
        final Message saved = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hello!");
        when(messageRepo.save(any(Message.class))).thenReturn(saved);

        final ResponseEntity<?> response = controller.sendMessage(inbound);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isSameAs(saved);
        // verify timestamp and isRead were set before save
        verify(messageRepo).save(argThat(m -> m.getTimestamp() != null && !m.isRead()));
    }

    @Test
    @DisplayName("TC-MSG-SEC-009 sendMessage returns 403 and saves nothing when the users may not message each other")
    void sendMessage_notAllowed_returnsForbidden() throws Exception {
        final Message inbound = new Message(SENDER_ID, RECEIVER_ID, "Hello!");
        when(securityUtil.resolveCurrentUser()).thenReturn(makeUser(SENDER_ID, "Alice", "alice@test.com"));
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(false);

        final ResponseEntity<?> response = controller.sendMessage(inbound);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(response.getBody()).isEqualTo(MessageController.NOT_ALLOWED);
        verify(messageRepo, never()).save(any(Message.class));
    }

    @Test
    @DisplayName("TC-MSG-SEC-010 sendMessage saves only sender, receiver and content, never a client-supplied id or attachment")
    void sendMessage_ignoresClientIdAndAttachment() throws Exception {
        final Message inbound = new Message(SENDER_ID, RECEIVER_ID, "Hello!");
        final var idField = Message.class.getDeclaredField("id");
        idField.setAccessible(true);
        idField.set(inbound, 77L);
        inbound.setAttachmentId(99L);
        inbound.setAttachmentName("someone-elses.pdf");
        inbound.setRead(true);
        when(securityUtil.resolveCurrentUser()).thenReturn(makeUser(SENDER_ID, "Alice", "alice@test.com"));
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(true);
        when(messageRepo.save(any(Message.class))).thenAnswer(inv -> inv.getArgument(0));

        controller.sendMessage(inbound);

        verify(messageRepo).save(argThat(m -> m.getId() == null
                && m.getAttachmentId() == null
                && m.getAttachmentName() == null
                && !m.isRead()
                && SENDER_ID.equals(m.getSenderId())
                && RECEIVER_ID.equals(m.getReceiverId())
                && "Hello!".equals(m.getContent())));
    }

    @Test
    @DisplayName("TC-MSG-SEC-011 sendMessage refuses a sender other than the signed-in user")
    void sendMessage_otherSender_throwsUnauthorized() throws Exception {
        final Message inbound = new Message(SENDER_ID, RECEIVER_ID, "Hello!");
        final User other = makeUser(RECEIVER_ID, "Bob", "bob@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(other);
        doThrow(new UnauthorizedException("not you")).when(authorizationService).requireSelfOrAdmin(other, SENDER_ID);

        assertThatThrownBy(() -> controller.sendMessage(inbound)).isInstanceOf(UnauthorizedException.class);
        verify(messageRepo, never()).save(any(Message.class));
        verifyNoInteractions(messagingPolicy);
    }

    // ─── getConversation ──────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-CTL-002 getConversation returns the conversation to user1")
    void getConversation_returns200_withMessages() throws Exception {
        final User currentUser = User.builder().id(SENDER_ID).email("sender@test.com").role(Role.PATIENT).password("p").status("ACTIVE").build();
        when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hi");
        when(messageRepo.findConversation(SENDER_ID, RECEIVER_ID)).thenReturn(List.of(msg));

        final ResponseEntity<List<Message>> response = controller.getConversation(SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
    }

    @Test
    @DisplayName("TC-MSG-CTL-003 getConversation returns an empty conversation")
    void getConversation_returns200_emptyConversation() throws Exception {
        final User currentUser = User.builder().id(SENDER_ID).email("sender@test.com").role(Role.PATIENT).password("p").status("ACTIVE").build();
        when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
        when(messageRepo.findConversation(SENDER_ID, RECEIVER_ID)).thenReturn(List.of());

        final ResponseEntity<List<Message>> response = controller.getConversation(SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    // ─── getInbox ─────────────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-CTL-004 getInbox returns an empty list when the user has no messages")
    void getInbox_noMessages_returnsEmptyList() throws Exception {
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of());

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    @DisplayName("TC-MSG-CTL-005 getInbox shows the receiver as the peer of a message the user sent")
    void getInbox_userIsSender_peerIsReceiver() throws Exception {
        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hey");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        final User peer = makeUser(RECEIVER_ID, "Bob", "bob@test.com");
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peer));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        final InboxMessageDto dto = response.getBody().get(0);
        assertThat(dto.getPeerId()).isEqualTo(RECEIVER_ID);
        assertThat(dto.getPeerName()).isEqualTo("Bob");
        assertThat(dto.getPeerEmail()).isEqualTo("bob@test.com");
        assertThat(dto.getContent()).isEqualTo("Hey");
    }

    @Test
    @DisplayName("TC-MSG-CTL-006 getInbox shows the sender as the peer of a message the user received")
    void getInbox_userIsReceiver_peerIsSender() throws Exception {
        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hi from sender");
        when(messageRepo.findAllUserMessages(RECEIVER_ID)).thenReturn(List.of(msg));
        final User peer = makeUser(SENDER_ID, "Alice", "alice@test.com");
        when(userRepo.findById(SENDER_ID)).thenReturn(Optional.of(peer));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerId()).isEqualTo(SENDER_ID);
        assertThat(response.getBody().get(0).getPeerName()).isEqualTo("Alice");
    }

    @Test
    @DisplayName("TC-MSG-CTL-007 getInbox skips a peer that has no user record")
    void getInbox_peerNotFoundInRepo_skipsEntry() throws Exception {
        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hello");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.empty());

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEmpty();
    }

    @Test
    @DisplayName("TC-MSG-CTL-008 getInbox keeps only the first (latest) message from each peer")
    void getInbox_multipleMsgsFromSamePeer_onlyFirstKept() throws Exception {
        // Two messages from same peer — inbox should only show the most recent (first in list)
        final Message msg1 = makeMessage(1L, SENDER_ID, RECEIVER_ID, "First");
        final Message msg2 = makeMessage(2L, SENDER_ID, RECEIVER_ID, "Second");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg1, msg2));
        final User peer = makeUser(RECEIVER_ID, "Bob", "bob@test.com");
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peer));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getContent()).isEqualTo("First");
    }

    @Test
    @DisplayName("TC-MSG-CTL-009 getInbox lists one entry for each distinct peer")
    void getInbox_multipleDistinctPeers_allIncluded() throws Exception {
        final Long peer2Id = 3L;
        final Message msg1 = makeMessage(1L, SENDER_ID, RECEIVER_ID, "To Peer1");
        final Message msg2 = makeMessage(2L, SENDER_ID, peer2Id, "To Peer2");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg1, msg2));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(makeUser(RECEIVER_ID, "Bob", "b@t.com")));
        when(userRepo.findById(peer2Id)).thenReturn(Optional.of(makeUser(peer2Id, "Carol", "c@t.com")));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(2);
    }

    // ─── getConversation - additional edge cases ─────────────────────────────

    @Test
    @DisplayName("TC-MSG-CTL-010 getConversation allows admin to view any conversation")
    void getConversation_adminCanViewAnyConversation() throws Exception {
        final User admin = User.builder().id(99L).email("admin@test.com")
                .role(Role.ADMIN).password("p").status("ACTIVE").build();
        when(securityUtil.resolveCurrentUser()).thenReturn(admin);
        when(messageRepo.findConversation(SENDER_ID, RECEIVER_ID)).thenReturn(List.of());

        final ResponseEntity<List<Message>> response =
                controller.getConversation(SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    }

    @Test
    @DisplayName("TC-MSG-CTL-011 getConversation throws UnauthorizedException when user is not participant and not admin")
    void getConversation_nonParticipantNonAdmin_throwsUnauthorized() throws Exception {
        final User otherUser = User.builder().id(99L).email("other@test.com")
                .role(Role.PATIENT).password("p").status("ACTIVE").build();
        when(securityUtil.resolveCurrentUser()).thenReturn(otherUser);

        assertThatThrownBy(() -> controller.getConversation(SENDER_ID, RECEIVER_ID))
                .isInstanceOf(UnauthorizedException.class)
                .hasMessageContaining("only view conversations you are a participant in");
    }

    @Test
    @DisplayName("TC-MSG-CTL-012 getConversation allows when current user equals user2")
    void getConversation_currentUserIsUser2_succeeds() throws Exception {
        final User currentUser = User.builder().id(RECEIVER_ID).email("receiver@test.com")
                .role(Role.PATIENT).password("p").status("ACTIVE").build();
        when(securityUtil.resolveCurrentUser()).thenReturn(currentUser);
        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hello");
        when(messageRepo.findConversation(SENDER_ID, RECEIVER_ID)).thenReturn(List.of(msg));

        final ResponseEntity<List<Message>> response =
                controller.getConversation(SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
    }

    // ─── getInbox - additional edge cases ────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-CTL-013 getInbox marks unread correctly when receiver is inbox user and message is unread")
    void getInbox_unreadMessage_hasUnreadTrue() throws Exception {
        final Message msg = new Message();
        msg.setSenderId(RECEIVER_ID);
        msg.setReceiverId(SENDER_ID);
        msg.setContent("New message");
        msg.setTimestamp(LocalDateTime.now());
        msg.setRead(false);

        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        final User peer = makeUser(RECEIVER_ID, "Bob", "bob@test.com");
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peer));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).isHasUnread()).isTrue();
    }

    @Test
    @DisplayName("TC-MSG-CTL-014 getInbox resolves patient display name from patient profile")
    void getInbox_peerIsPatient_resolvesPatientDisplayName() throws Exception {
        final User peerUser = makeUser(RECEIVER_ID, null, "patient@test.com");
        peerUser.setRole(Role.PATIENT);

        final Patient patient = new Patient();
        patient.setFirstName("John");
        patient.setLastName("Doe");

        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hey");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peerUser));
        when(patientRepo.findByUserId(RECEIVER_ID)).thenReturn(Optional.of(patient));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerName()).isEqualTo("John Doe");
    }

    @Test
    @DisplayName("TC-MSG-CTL-015 getInbox resolves caregiver display name from caregiver profile")
    void getInbox_peerIsCaregiver_resolvesCaregiverDisplayName() throws Exception {
        final User peerUser = makeUser(RECEIVER_ID, null, "caregiver@test.com");
        peerUser.setRole(Role.CAREGIVER);

        final Caregiver caregiver = new Caregiver();
        caregiver.setFirstName("Jane");
        caregiver.setLastName("Smith");

        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hey");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peerUser));
        lenient().when(patientRepo.findByUserId(RECEIVER_ID)).thenReturn(Optional.empty());
        when(caregiverRepo.findByUserId(RECEIVER_ID)).thenReturn(Optional.of(caregiver));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerName()).isEqualTo("Jane Smith");
    }

    @Test
    @DisplayName("TC-MSG-CTL-016 getInbox falls back to user name when no profile name found")
    void getInbox_noProfileName_fallsBackToUserName() throws Exception {
        final User peerUser = makeUser(RECEIVER_ID, "FallbackName", "peer@test.com");
        peerUser.setRole(Role.ADMIN);

        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hi");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peerUser));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerName()).isEqualTo("FallbackName");
    }

    @Test
    @DisplayName("TC-MSG-CTL-017 getInbox falls back to email local part when no name available")
    void getInbox_noName_fallsBackToEmailLocalPart() throws Exception {
        final User peerUser = makeUser(RECEIVER_ID, null, "someone@example.com");
        peerUser.setRole(Role.ADMIN);

        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hi");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peerUser));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerName()).isEqualTo("someone");
    }

    @Test
    @DisplayName("TC-MSG-CTL-018 getInbox returns Unknown when no name and no email")
    void getInbox_noNameNoEmail_returnsUnknown() throws Exception {
        final User peerUser = makeUser(RECEIVER_ID, null, null);
        peerUser.setRole(Role.ADMIN);

        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hi");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peerUser));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerName()).isEqualTo("Unknown");
    }

    @Test
    @DisplayName("TC-MSG-CTL-019 getInbox shows UNKNOWN role when peer has null role")
    void getInbox_peerNullRole_showsUnknown() throws Exception {
        final User peerUser = makeUser(RECEIVER_ID, "Bob", "bob@test.com");
        peerUser.setRole(null);

        final Message msg = makeMessage(1L, SENDER_ID, RECEIVER_ID, "Hi");
        when(messageRepo.findAllUserMessages(SENDER_ID)).thenReturn(List.of(msg));
        when(userRepo.findById(RECEIVER_ID)).thenReturn(Optional.of(peerUser));

        final ResponseEntity<List<InboxMessageDto>> response = controller.getInbox(SENDER_ID);

        assertThat(response.getBody()).hasSize(1);
        assertThat(response.getBody().get(0).getPeerRole()).isEqualTo("UNKNOWN");
    }

    // ─── share ────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("share passes the signed-in user, never a client value, and returns the card and receiverCanView")
    void share_returnsCardAndReceiverCanView() {
        final User patient = makeUser(SENDER_ID, "Pat", "pat@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(patient);
        final Message card = makeMessage(5L, SENDER_ID, RECEIVER_ID, "Shared my Medicare records");
        card.setShareKind(Message.ShareKind.MEDICARE);
        when(messageShareService.share(patient, RECEIVER_ID, "MEDICARE"))
                .thenReturn(new MessageShareService.ShareResult(card, false));

        final ResponseEntity<Map<String, Object>> response =
                controller.share(new MessageController.ShareRequest(RECEIVER_ID, "MEDICARE"));

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).containsEntry("message", card).containsEntry("receiverCanView", false);
    }

    // ─── sendAttachment ──────────────────────────────────────────────────────

    @Test
    @DisplayName("TC-MSG-SEC-001 sendAttachment refuses a senderId that isn't the signed-in user, and sends nothing")
    void sendAttachment_senderNotCurrentUser_throwsAndSendsNothing() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        final User signedIn = makeUser(99L, "Mallory", "mallory@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(signedIn);
        doThrow(new UnauthorizedException("You can only access your own data unless you are an administrator"))
                .when(authorizationService).requireSelfOrAdmin(signedIn, SENDER_ID);

        assertThatThrownBy(() -> controller.sendAttachment(file, SENDER_ID, RECEIVER_ID))
                .isInstanceOf(UnauthorizedException.class);

        verifyNoInteractions(messagingPolicy, fileManagementService, messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-SEC-002 sendAttachment checks the sender against the signed-in user before anything else")
    void sendAttachment_checksSenderIsSignedInUser() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        final User signedIn = makeUser(SENDER_ID, "Alice", "alice@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(signedIn);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(false);

        controller.sendAttachment(file, SENDER_ID, RECEIVER_ID);

        final org.mockito.InOrder order = inOrder(authorizationService, messagingPolicy);
        order.verify(authorizationService).requireSelfOrAdmin(signedIn, SENDER_ID);
        order.verify(messagingPolicy).canMessage(SENDER_ID, RECEIVER_ID);
    }

    @Test
    @DisplayName("TC-MSG-CTL-020 sendAttachment returns 403 when the users may not message each other")
    void sendAttachment_messagingNotEnabled_returnsForbidden() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        final User signedIn = makeUser(SENDER_ID, "Alice", "alice@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(signedIn);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(false);

        final ResponseEntity<?> response =
                controller.sendAttachment(file, SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(response.getBody()).isEqualTo(MessageController.NOT_ALLOWED);
        verify(authorizationService).requireSelfOrAdmin(signedIn, SENDER_ID);
        verifyNoInteractions(fileManagementService, messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-CTL-021 sendAttachment succeeds when the caregiver may message the patient")
    void sendAttachment_messagingEnabledForward_succeeds() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.getSize()).thenReturn(1024L);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(true);

        final User sender = makeUser(SENDER_ID, "Alice", "alice@test.com");
        sender.setRole(Role.CAREGIVER);
        when(securityUtil.resolveCurrentUser()).thenReturn(sender);
        when(userRepo.findById(SENDER_ID)).thenReturn(Optional.of(sender));

        final FileUploadResponse uploadResponse = FileUploadResponse.builder()
                .fileId(50L)
                .originalFilename("doc.pdf")
                .contentType("application/pdf")
                .build();
        when(fileManagementService.uploadFile(
                eq(file), eq(SENDER_ID), eq("CAREGIVER"),
                eq("CHAT_ATTACHMENT"), eq("Chat attachment"), eq(null)))
                .thenReturn(uploadResponse);

        final Message saved = makeMessage(1L, SENDER_ID, RECEIVER_ID, "");
        saved.setAttachmentId(50L);
        when(messageRepo.save(any(Message.class))).thenReturn(saved);

        final ResponseEntity<?> response =
                controller.sendAttachment(file, SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        @SuppressWarnings("unchecked")
        Map<String, Object> body = (Map<String, Object>) response.getBody();
        assertThat(body).containsKey("message");
        assertThat(body).containsKey("downloadUrl");
        assertThat(body.get("downloadUrl")).isEqualTo("/v1/api/files/50/download");
        verify(authorizationService).requireSelfOrAdmin(sender, SENDER_ID);
        verify(messageRepo).save(argThat(m -> SENDER_ID.equals(m.getSenderId())
                && RECEIVER_ID.equals(m.getReceiverId()) && Long.valueOf(50L).equals(m.getAttachmentId())));
    }

    @Test
    @DisplayName("TC-MSG-CTL-022 sendAttachment succeeds when the patient may message the caregiver")
    void sendAttachment_messagingEnabledReverse_succeeds() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.getSize()).thenReturn(2048L);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(true);

        final User sender = makeUser(SENDER_ID, "Alice", "alice@test.com");
        sender.setRole(Role.PATIENT);
        when(securityUtil.resolveCurrentUser()).thenReturn(sender);
        when(userRepo.findById(SENDER_ID)).thenReturn(Optional.of(sender));

        final FileUploadResponse uploadResponse = FileUploadResponse.builder()
                .fileId(51L)
                .originalFilename("photo.jpg")
                .contentType("image/jpeg")
                .build();
        when(fileManagementService.uploadFile(
                eq(file), eq(SENDER_ID), eq("PATIENT"),
                eq("CHAT_ATTACHMENT"), eq("Chat attachment"), eq(null)))
                .thenReturn(uploadResponse);

        final Message saved = makeMessage(1L, SENDER_ID, RECEIVER_ID, "");
        when(messageRepo.save(any(Message.class))).thenReturn(saved);

        final ResponseEntity<?> response =
                controller.sendAttachment(file, SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(authorizationService).requireSelfOrAdmin(sender, SENDER_ID);
    }

    @Test
    @DisplayName("TC-MSG-CTL-023 sendAttachment returns 500 when file upload fails")
    void sendAttachment_uploadFails_returns500() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(true);

        final User sender = makeUser(SENDER_ID, "Alice", "alice@test.com");
        sender.setRole(Role.CAREGIVER);
        when(securityUtil.resolveCurrentUser()).thenReturn(sender);
        when(userRepo.findById(SENDER_ID)).thenReturn(Optional.of(sender));

        when(fileManagementService.uploadFile(
                eq(file), eq(SENDER_ID), eq("CAREGIVER"),
                eq("CHAT_ATTACHMENT"), eq("Chat attachment"), eq(null)))
                .thenThrow(new RuntimeException("S3 bucket unavailable"));

        final ResponseEntity<?> response =
                controller.sendAttachment(file, SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);
        assertThat((String) response.getBody())
                .contains("Failed to upload attachment");
        verify(authorizationService).requireSelfOrAdmin(sender, SENDER_ID);
        verifyNoInteractions(messageRepo);
    }

    @Test
    @DisplayName("TC-MSG-CTL-024 sendAttachment defaults to PATIENT role when sender not found")
    void sendAttachment_senderNotFound_defaultsToPatientRole() throws Exception {
        final MultipartFile file = mock(MultipartFile.class);
        when(file.getSize()).thenReturn(512L);
        final User signedIn = makeUser(SENDER_ID, "Alice", "alice@test.com");
        when(securityUtil.resolveCurrentUser()).thenReturn(signedIn);
        when(messagingPolicy.canMessage(SENDER_ID, RECEIVER_ID)).thenReturn(true);
        when(userRepo.findById(SENDER_ID)).thenReturn(Optional.empty());

        final FileUploadResponse uploadResponse = FileUploadResponse.builder()
                .fileId(52L)
                .originalFilename("file.txt")
                .contentType("text/plain")
                .build();
        when(fileManagementService.uploadFile(
                eq(file), eq(SENDER_ID), eq("PATIENT"),
                eq("CHAT_ATTACHMENT"), eq("Chat attachment"), eq(null)))
                .thenReturn(uploadResponse);

        final Message saved = makeMessage(1L, SENDER_ID, RECEIVER_ID, "");
        when(messageRepo.save(any(Message.class))).thenReturn(saved);

        final ResponseEntity<?> response =
                controller.sendAttachment(file, SENDER_ID, RECEIVER_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        verify(fileManagementService).uploadFile(
                eq(file), eq(SENDER_ID), eq("PATIENT"),
                eq("CHAT_ATTACHMENT"), eq("Chat attachment"), eq(null));
        verify(authorizationService).requireSelfOrAdmin(signedIn, SENDER_ID);
    }
}
