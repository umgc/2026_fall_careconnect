package com.careconnect.controller;

import com.careconnect.security.Permission;
import com.careconnect.security.RequirePermission;
import com.careconnect.security.Role;

import com.careconnect.model.Message;
import com.careconnect.model.User;
import com.careconnect.dto.FileUploadResponse;
import com.careconnect.dto.InboxMessageDto;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.MessageRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.UserRepository;
import com.careconnect.service.FileManagementService;
import com.careconnect.service.MessageShareService;
import com.careconnect.service.MessagingPolicy;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import com.careconnect.security.AuthorizationService;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;

import java.time.LocalDateTime;
import java.util.*;

@RestController
@RequestMapping("/v1/api/messages")
public class MessageController {

    @Autowired
    private MessageRepository messageRepo;

    @Autowired
    private UserRepository userRepo;

    @Autowired
    private PatientRepository patientRepo;

    @Autowired
    private CaregiverRepository caregiverRepo;

    @Autowired
    private FileManagementService fileManagementService;

    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    @Autowired
    private MessagingPolicy messagingPolicy;

    @Autowired
    private MessageShareService messageShareService;

    static final String NOT_ALLOWED = MessagingPolicy.NOT_ALLOWED;

    private static String fullName(String first, String last) {
        String f = (first != null) ? first.trim() : "";
        String l = (last != null) ? last.trim() : "";
        return (f + " " + l).trim();
    }

    // ✅ Send a new message
    @RequirePermission(Permission.SEND_MESSAGES)

    @PostMapping("/send")
    public ResponseEntity<?> sendMessage(@RequestBody Message request) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, request.getSenderId());
        if (!messagingPolicy.canMessage(request.getSenderId(), request.getReceiverId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(NOT_ALLOWED);
        }

        // Only the sender, receiver and content come from the request. Saving the body as sent would let a
        // client set id (overwriting another message) or attachmentId (FileController lets anyone in a
        // conversation download its attachments, so that would expose any file by id).
        Message message = new Message(request.getSenderId(), request.getReceiverId(), request.getContent());
        Message saved = messageRepo.save(message);
        return ResponseEntity.ok(saved);
    }

    /** Body of {@code POST /share}: who gets the card and what it opens, for example MEDICARE. */
    public record ShareRequest(Long receiverId, String kind) {
    }

    /**
     * A patient shares one kind of their data with a linked caregiver as a card in chat. The patient
     * is the signed-in user; the card holds only what it opens, and the data's own access rule is
     * checked when the caregiver opens it (see {@link MessageShareService}).
     *
     * @return {@code { message, receiverCanView }}. receiverCanView false means the caregiver cannot
     *         open the card yet, because the patient has not given the consent.
     */
    @RequirePermission(Permission.SEND_MESSAGES)
    @PostMapping("/share")
    public ResponseEntity<Map<String, Object>> share(@RequestBody ShareRequest request) {
        User currentUser = securityUtil.resolveCurrentUser();
        MessageShareService.ShareResult result = messageShareService.share(
                currentUser, request.receiverId(), request.kind());
        return ResponseEntity.ok(Map.of(
                "message", result.message(),
                "receiverCanView", result.receiverCanView()
        ));
    }

    // ✅ Fetch full conversation between two users
    @RequirePermission(Permission.VIEW_MESSAGES)

    @GetMapping("/conversation")
    public ResponseEntity<List<Message>> getConversation(
            @RequestParam Long user1,
            @RequestParam Long user2
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        Long currentUserId = currentUser.getId();
        if (!currentUserId.equals(user1) && !currentUserId.equals(user2) && !currentUser.isAdmin()) {
            throw new UnauthorizedException("You can only view conversations you are a participant in");
        }
        List<Message> conversation = messageRepo.findConversation(user1, user2);
        return ResponseEntity.ok(conversation);
    }

    // ✅ Inbox view: list all recent conversations with peer info
    @RequirePermission(Permission.VIEW_MESSAGES)

    @GetMapping("/inbox/{userId}")
    public ResponseEntity<List<InboxMessageDto>> getInbox(@PathVariable Long userId) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, userId);
        List<Message> messages = messageRepo.findAllUserMessages(userId);
        Map<Long, InboxMessageDto> map = new LinkedHashMap<>(); // keep order

        for (Message m : messages) {
            Long peerId = m.getSenderId().equals(userId) ? m.getReceiverId() : m.getSenderId();
            if (map.containsKey(peerId)) continue; // already got latest from this peer

            Optional<User> peer = userRepo.findById(peerId);
            if (peer.isPresent()) {
                User u = peer.get();
                String peerName = resolveDisplayName(u);
                String peerRole = u.getRole() != null ? u.getRole().name() : "UNKNOWN";
                boolean hasUnread = m.getReceiverId().equals(userId) && !m.isRead();
                InboxMessageDto dto = new InboxMessageDto(
                        m.getId(),
                        peerId,
                        peerName,
                        u.getEmail(),
                        peerRole,
                        m.getContent(),
                        m.getTimestamp(),
                        hasUnread
                );
                map.put(peerId, dto);
            }
        }

        return ResponseEntity.ok(new ArrayList<>(map.values()));
    }

    // ✅ Send a message with a file attachment (multipart)
    @RequirePermission(Permission.SEND_MESSAGES)
    @PostMapping("/send-attachment")
    public ResponseEntity<?> sendAttachment(
            @RequestParam("file") MultipartFile file,
            @RequestParam Long senderId,
            @RequestParam Long receiverId
    ) throws UnauthorizedException {
        User currentUser = securityUtil.resolveCurrentUser();
        authorizationService.requireSelfOrAdmin(currentUser, senderId);
        if (!messagingPolicy.canMessage(senderId, receiverId)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body(NOT_ALLOWED);
        }

        try {
            User sender = userRepo.findById(senderId).orElse(null);
            String userType = sender != null ? sender.getRole().name() : "PATIENT";

            FileUploadResponse uploaded = fileManagementService.uploadFile(
                    file, senderId, userType, "CHAT_ATTACHMENT", "Chat attachment", null);

            Message message = new Message();
            message.setSenderId(senderId);
            message.setReceiverId(receiverId);
            message.setContent("");
            message.setTimestamp(LocalDateTime.now());
            message.setRead(false);
            message.setAttachmentId(uploaded.getFileId());
            message.setAttachmentName(uploaded.getOriginalFilename());
            message.setAttachmentContentType(uploaded.getContentType());
            message.setAttachmentSize(file.getSize());

            Message saved = messageRepo.save(message);
            return ResponseEntity.ok(Map.of(
                    "message", saved,
                    "downloadUrl", "/v1/api/files/" + uploaded.getFileId() + "/download"
            ));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body("Failed to upload attachment: " + e.getMessage());
        }
    }

    private String resolveDisplayName(User u) {
        Role role = u.getRole();
        if (role == Role.PATIENT) {
            String profileName = patientRepo.findByUserId(u.getId())
                    .map(p -> fullName(p.getFirstName(), p.getLastName()))
                    .filter(s -> !s.isBlank())
                    .orElse(null);
            if (profileName != null) return profileName;
        }
        if (role == Role.CAREGIVER) {
            String profileName = caregiverRepo.findByUserId(u.getId())
                    .map(c -> fullName(c.getFirstName(), c.getLastName()))
                    .filter(s -> !s.isBlank())
                    .orElse(null);
            if (profileName != null) return profileName;
        }
        if (u.getName() != null && !u.getName().isBlank()) return u.getName().trim();
        String email = u.getEmail();
        if (email != null && !email.isBlank()) {
            int at = email.indexOf('@');
            return at > 0 ? email.substring(0, at) : email;
        }
        return "Unknown";
    }
}