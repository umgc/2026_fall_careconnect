package com.careconnect.controller;

import com.careconnect.dto.*;
import com.careconnect.model.ChatConversation;
import com.careconnect.service.AIChatService;
import com.careconnect.service.ChatCleanupService;
import com.careconnect.service.UserAIConfigService;
import com.careconnect.repository.ChatConversationRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.HashMap;
import java.util.stream.Collectors;

@ConditionalOnProperty(
        name = "careconnect.ai.enabled",
        havingValue = "true",
        matchIfMissing = false
)
@RestController
@RequestMapping("/v1/api/ai-chat")
@RequiredArgsConstructor
@Tag(name = "AI Chat", description = "AI-powered chat functionality with medical context")
public class AIChatController {
    private static final org.slf4j.Logger LOG = org.slf4j.LoggerFactory.getLogger(AIChatController.class);
    private final AIChatService aiChatService;
    private final UserAIConfigService userAIConfigService;
    private final ChatConversationRepository chatConversationRepository;
    private final ChatCleanupService chatCleanupService;

    @PostMapping("/chat")
    @Operation(
            summary = "Send chat message to AI",
            description = "Send a message to AI with optional medical context and optional uploaded files. Creates new conversation if conversationId not provided."
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Chat response received successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request data"),
            @ApiResponse(responseCode = "401", description = "Unauthorized"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "500", description = "Internal server error")
    })
    public ResponseEntity<ChatResponse> sendMessage(@Valid @RequestBody ChatRequest request) {
        LOG.info("Processing chat request for patient: {}, user: {}. Uploaded files: {}", request.getPatientId(), request.getUserId(), request.getUploadedFiles());
        try {
            ChatResponse response = aiChatService.processChat(request);
            if (response.getSuccess()) {
                return ResponseEntity.ok(response);
            } else {
                return ResponseEntity.badRequest().body(response);
            }
        } catch (Exception e) {
            LOG.error("Error processing chat request", e);
            return ResponseEntity.status(500).body(
                    ChatResponse.builder()
                            .success(false)
                            .errorMessage("An unexpected error occurred")
                            .errorCode("INTERNAL_ERROR")
                            .build()
            );
        }
    }

    @GetMapping("/conversations/{patientId}")
    @Operation(
            summary = "Get patient's chat conversations",
            description = "Retrieve all active chat conversations for a specific patient"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Conversations retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Patient not found")
    })
    // @PreAuthorize("hasRole('PATIENT') or hasRole('CAREGIVER') or hasRole('FAMILY_MEMBER')")
    public ResponseEntity<List<ChatConversationSummary>> getPatientConversations(
            @Parameter(description = "Patient ID") @PathVariable Long patientId) {

        LOG.info("Retrieving conversations for patient: {}", patientId);

        try {
            List<ChatConversationSummary> conversations = aiChatService.getPatientConversations(patientId);
            return ResponseEntity.ok(conversations);
        } catch (Exception e) {
            LOG.error("Error retrieving conversations for patient {}: ", patientId, e);
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/conversation/{conversationId}/messages")
    @Operation(
            summary = "Get conversation messages",
            description = "Retrieve all messages from a specific conversation"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Messages retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Conversation not found")
    })
    // @PreAuthorize("hasRole('PATIENT') or hasRole('CAREGIVER') or hasRole('FAMILY_MEMBER')")
    public ResponseEntity<List<ChatMessageSummary>> getConversationMessages(
            @Parameter(description = "Conversation ID") @PathVariable String conversationId) {

        LOG.info("Retrieving messages for conversation: {}", conversationId);

        try {
            List<ChatMessageSummary> messages = aiChatService.getConversationMessages(conversationId);
            return ResponseEntity.ok(messages);
        } catch (Exception e) {
            LOG.error("Error retrieving messages for conversation {}: ", conversationId, e);
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/history")
    @Operation(
            summary = "Get conversation history",
            description = "Retrieve conversation history for a user, optionally filtered by conversation ID"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "History retrieved successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid request parameters"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<Map<String, Object>> getConversationHistory(
            @RequestParam Long userId,
            @RequestParam(required = false) String conversationId,
            @RequestParam(defaultValue = "50") int limit) {

        LOG.info("Retrieving conversation history for user: {}, conversation: {}, limit: {}",
                userId, conversationId, limit);

        try {
            List<ChatMessageSummary> messages;

            if (conversationId != null && !conversationId.trim().isEmpty()) {
                // Get messages for specific conversation
                messages = aiChatService.getConversationMessages(conversationId);
            } else {
                // Get recent messages from the most recent active conversation for the user
                messages = aiChatService.getRecentMessagesForUser(userId, limit);
            }

            // Convert to the format expected by frontend
            List<Map<String, Object>> messageList = messages.stream()
                    .map(msg -> {
                        Map<String, Object> messageMap = new HashMap<>();
                        messageMap.put("content", msg.getContent());
                        messageMap.put("messageType", msg.getMessageType());
                        messageMap.put("createdAt", msg.getCreatedAt());
                        return messageMap;
                    })
                    .collect(Collectors.toList());

            Map<String, Object> response = new HashMap<>();
            response.put("messages", messageList);

            // If we loaded recent messages (no specific conversationId), include the conversationId
            if (conversationId == null || conversationId.trim().isEmpty()) {
                if (!messages.isEmpty()) {
                    // Get the conversationId from the first message (they're all from the same conversation)
                    ChatMessageSummary firstMessage = messages.get(0);
                    // We need to get the conversationId from the message - let me check if it's available
                    // For now, we'll get it from the most recent conversation
                    List<ChatConversation> conversations = chatConversationRepository
                            .findByUserIdAndIsActiveTrueOrderByUpdatedAtDesc(userId);
                    if (!conversations.isEmpty()) {
                        response.put("conversationId", conversations.get(0).getConversationId());
                    }
                }
            }

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            LOG.error("Error retrieving conversation history for user {}: ", userId, e);
            return ResponseEntity.badRequest().build();
        }
    }

    @PostMapping("/conversation/{conversationId}/deactivate")
    @Operation(
            summary = "Deactivate conversation",
            description = "Mark a conversation as inactive (soft delete)"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Conversation deactivated successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Conversation not found")
    })
    // @PreAuthorize("hasRole('PATIENT') or hasRole('CAREGIVER')")
    public ResponseEntity<Void> deactivateConversation(
            @Parameter(description = "Conversation ID") @PathVariable String conversationId) {

        LOG.info("Deactivating conversation: {}", conversationId);

        try {
            aiChatService.deactivateConversation(conversationId);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            LOG.error("Error deactivating conversation {}: ", conversationId, e);
            return ResponseEntity.badRequest().build();
        }
    }

    // AI Configuration endpoints
    @GetMapping("/config")
    @Operation(
            summary = "Get AI configuration",
            description = "Retrieve AI configuration settings for a user (optionally filtered by patient)"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Configuration retrieved successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Configuration not found")
    })
    public ResponseEntity<UserAIConfigDTO> getUserAIConfig(
            @RequestParam Long userId,
            @RequestParam(required = false) Long patientId) {
        LOG.info("Retrieving AI config for user: {}, patient: {}", userId, patientId);
        try {
            UserAIConfigDTO config = userAIConfigService.getUserAIConfig(userId, patientId);
            return ResponseEntity.ok(config);
        } catch (Exception e) {
            LOG.error("Error retrieving AI config for user: {}, patient: {}: ", userId, patientId, e);
            return ResponseEntity.badRequest().build();
        }
    }

    @PostMapping("/config")
    @Operation(
            summary = "Create or update AI configuration",
            description = "Create or update AI configuration settings for a user (optionally filtered by patient)"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Configuration updated successfully"),
            @ApiResponse(responseCode = "201", description = "Configuration created successfully"),
            @ApiResponse(responseCode = "400", description = "Invalid configuration data"),
            @ApiResponse(responseCode = "403", description = "Access denied")
    })
    public ResponseEntity<UserAIConfigDTO> saveUserAIConfig(
            @Valid @RequestBody UserAIConfigDTO configDTO) {
        LOG.info("Saving AI config for user: {}, patient: {}", configDTO.getUserId(), configDTO.getPatientId());
        try {
            UserAIConfigDTO savedConfig = userAIConfigService.saveUserAIConfig(configDTO);
            boolean isNew = configDTO.getId() == null;
            return isNew ? ResponseEntity.status(201).body(savedConfig) : ResponseEntity.ok(savedConfig);
        } catch (Exception e) {
            LOG.error("Error saving AI config for user: {}, patient: {}: ", configDTO.getUserId(), configDTO.getPatientId(), e);
            return ResponseEntity.badRequest().build();
        }
    }

    @DeleteMapping("/config")
    @Operation(
            summary = "Deactivate AI configuration",
            description = "Deactivate AI configuration for a user (optionally filtered by patient, soft delete)"
    )
    @ApiResponses(value = {
            @ApiResponse(responseCode = "200", description = "Configuration deactivated successfully"),
            @ApiResponse(responseCode = "403", description = "Access denied"),
            @ApiResponse(responseCode = "404", description = "Configuration not found")
    })
    public ResponseEntity<Void> deactivateUserAIConfig(
            @RequestParam Long userId,
            @RequestParam(required = false) Long patientId) {
        LOG.info("Deactivating AI config for user: {}, patient: {}", userId, patientId);
        try {
            userAIConfigService.deactivateUserAIConfig(userId, patientId);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            LOG.error("Error deactivating AI config for user: {}, patient: {}: ", userId, patientId, e);
            return ResponseEntity.badRequest().build();
        }
    }

    @GetMapping("/retention-policy")
    @Operation(
            summary = "Get chat retention policy information",
            description = "Returns information about how long chat conversations are retained"
    )
    @ApiResponse(responseCode = "200", description = "Retention policy information retrieved successfully")
    public ResponseEntity<Map<String, String>> getRetentionPolicy() {
        try {
            String policyInfo = chatCleanupService.getRetentionPolicyInfo();
            Map<String, String> response = new HashMap<>();
            response.put("retentionPolicy", policyInfo);
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            LOG.error("Error retrieving retention policy info: ", e);
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", "Unable to retrieve retention policy information");
            return ResponseEntity.status(500).body(errorResponse);
        }
    }
}
