package com.careconnect.service.ai.ask;

import com.careconnect.dto.CaregiverPatientLinkResponse;
import com.careconnect.dto.ai.AiAskShareRequest;
import com.careconnect.dto.ai.AiAskShareResponse;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ai.ask.AiAskConversationShare;
import com.careconnect.model.ai.ask.AiAskShareRecipient;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ai.ask.AiAskConversationShareRepository;
import com.careconnect.repository.ai.ask.AiAskShareRecipientRepository;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.ChatAuditService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.util.ContentHashUtil;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * Persists Ask AI conversation shares for linked caregiver review.
 */
@Service
public class AiAskShareService {

    private static final Logger log = LoggerFactory.getLogger(AiAskShareService.class);
    private static final int MAX_TRANSCRIPT_CHARS = 200_000;
    private static final TypeReference<List<Long>> LONG_LIST = new TypeReference<>() {};

    private final RetrievalScopeService retrievalScopeService;
    private final PatientRepository patientRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;
    private final AiAskConversationShareRepository shareRepository;
    private final AiAskShareRecipientRepository recipientRepository;
    private final ChatAuditService chatAuditService;
    private final ObjectMapper objectMapper;
    private final AiAskShareService self;

    @Autowired
    public AiAskShareService(
            final RetrievalScopeService retrievalScopeService,
            final PatientRepository patientRepository,
            final CaregiverPatientLinkService caregiverPatientLinkService,
            final AiAskConversationShareRepository shareRepository,
            final AiAskShareRecipientRepository recipientRepository,
            final ChatAuditService chatAuditService,
            final ObjectMapper objectMapper,
            @Lazy final AiAskShareService self) {
        this.retrievalScopeService = retrievalScopeService;
        this.patientRepository = patientRepository;
        this.caregiverPatientLinkService = caregiverPatientLinkService;
        this.shareRepository = shareRepository;
        this.recipientRepository = recipientRepository;
        this.chatAuditService = chatAuditService;
        this.objectMapper = objectMapper;
        this.self = self != null ? self : this;
    }

    /**
     * Creates a share receipt. Outer method is intentionally non-transactional so a unique
     * constraint race can be recovered via {@link Propagation#REQUIRES_NEW} without leaving
     * the caller transaction rollback-only.
     */
    public AiAskShareResponse share(final User caller, final AiAskShareRequest request)
            throws UnauthorizedException, ForbiddenScopeException {
        if (caller == null || caller.getId() == null) {
            throw new UnauthorizedException("Authenticated caller required");
        }
        if (request == null || request.patientId() == null) {
            throw new AskAiRejectedException(
                    "INVALID_REQUEST", "patientId is required", 400);
        }
        if (request.messages() == null || request.messages().isEmpty()) {
            throw new AskAiRejectedException(
                    "INVALID_REQUEST", "messages are required", 400);
        }

        retrievalScopeService.resolveRetrievalScope(caller, request.patientId());

        final Patient patient = patientRepository
                .findById(request.patientId())
                .orElseThrow(() -> new AskAiRejectedException(
                        "PATIENT_NOT_FOUND", "Patient not found", 404));
        if (patient.getUser() == null || patient.getUser().getId() == null) {
            throw new AskAiRejectedException(
                    "PATIENT_NOT_FOUND", "Patient user missing", 404);
        }

        final List<Long> recipients =
                resolveRecipients(patient.getUser().getId(), request.caregiverUserId());
        if (recipients.isEmpty()) {
            throw new AskAiRejectedException(
                    "NO_CAREGIVER",
                    "No linked caregiver is available to receive this share",
                    400);
        }

        final TranscriptPayload transcript = serializeTranscript(request.messages());
        if (transcript.json().length() > MAX_TRANSCRIPT_CHARS) {
            throw new AskAiRejectedException(
                    "TRANSCRIPT_TOO_LARGE",
                    "Conversation is too large to share",
                    400);
        }

        final String transcriptSha256 = ContentHashUtil.sha256(transcript.json());
        final Optional<AiAskConversationShare> existing = shareRepository
                .findFirstByPatientIdAndSharedByUserIdAndTranscriptSha256OrderByCreatedAtDesc(
                        request.patientId(), caller.getId(), transcriptSha256);
        if (existing.isPresent()) {
            return self.mergeRecipientsIfNeeded(existing.get(), recipients);
        }

        final String recipientJson = writeRecipientJson(recipients);

        try {
            return self.persistNewShare(
                    caller,
                    request,
                    recipients,
                    recipientJson,
                    transcript,
                    transcriptSha256);
        } catch (DataIntegrityViolationException dup) {
            return self.findDuplicateShareEntity(
                            request.patientId(), caller.getId(), transcriptSha256)
                    .map(existingShare -> self.mergeRecipientsIfNeeded(existingShare, recipients))
                    .orElseThrow(() -> dup);
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public AiAskShareResponse persistNewShare(
            final User caller,
            final AiAskShareRequest request,
            final List<Long> recipients,
            final String recipientJson,
            final TranscriptPayload transcript,
            final String transcriptSha256) {
        final AiAskConversationShare saved = shareRepository.save(AiAskConversationShare.builder()
                .id(UUID.randomUUID())
                .patientId(request.patientId())
                .sharedByUserId(caller.getId())
                .sessionId(request.sessionId())
                .recipientUserIds(recipientJson)
                .messageCount(transcript.messageCount())
                .transcriptJson(transcript.json())
                .transcriptSha256(transcriptSha256)
                .build());

        replaceRecipientRows(saved.getId(), recipients);
        auditShare(caller, request.sessionId(), saved.getId(), recipients);

        log.info(
                "Ask AI conversation shared shareId={} patientId={} recipients={} messages={}",
                saved.getId(),
                request.patientId(),
                recipients.size(),
                transcript.messageCount());

        return toResponse(saved);
    }

    /**
     * Unions new recipients onto an existing soft-deduped share (R4).
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public AiAskShareResponse mergeRecipientsIfNeeded(
            final AiAskConversationShare existing, final List<Long> recipients) {
        final Set<Long> merged = new LinkedHashSet<>(parseRecipientIds(existing.getRecipientUserIds()));
        boolean changed = false;
        if (recipients != null) {
            for (final Long recipientId : recipients) {
                if (recipientId != null && merged.add(recipientId)) {
                    changed = true;
                }
            }
        }
        final List<Long> mergedList = new ArrayList<>(merged);
        if (changed) {
            existing.setRecipientUserIds(writeRecipientJson(mergedList));
            shareRepository.save(existing);
        }
        // Ensure join table is populated for legacy rows / recipient unions.
        replaceRecipientRows(existing.getId(), mergedList);
        return toResponse(existing);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW, readOnly = true)
    public Optional<AiAskConversationShare> findDuplicateShareEntity(
            final Long patientId, final Long sharedByUserId, final String transcriptSha256) {
        return shareRepository
                .findFirstByPatientIdAndSharedByUserIdAndTranscriptSha256OrderByCreatedAtDesc(
                        patientId, sharedByUserId, transcriptSha256);
    }

    /**
     * Lists share receipts for a patient the caller may access (FR-AI-1 scope).
     * Admins see all shares; everyone else only shares they created or are a recipient of (R3/R5).
     */
    @Transactional(readOnly = true)
    public List<AiAskShareResponse> listShares(final User caller, final Long patientId)
            throws UnauthorizedException, ForbiddenScopeException {
        if (caller == null || caller.getId() == null) {
            throw new UnauthorizedException("Authenticated caller required");
        }
        if (patientId == null) {
            throw new AskAiRejectedException("INVALID_REQUEST", "patientId is required", 400);
        }
        retrievalScopeService.resolveRetrievalScope(caller, patientId);
        final boolean elevated = caller.getRole() == Role.ADMIN;
        return shareRepository
                .findVisibleForCaller(patientId, caller.getId(), elevated)
                .stream()
                .map(this::toResponse)
                .toList();
    }

    private void replaceRecipientRows(final UUID shareId, final List<Long> recipients) {
        recipientRepository.deleteByShareId(shareId);
        final List<AiAskShareRecipient> rows = new ArrayList<>(recipients.size());
        for (final Long userId : recipients) {
            rows.add(AiAskShareRecipient.builder().shareId(shareId).userId(userId).build());
        }
        if (!rows.isEmpty()) {
            recipientRepository.saveAll(rows);
        }
    }

    private void auditShare(
            final User caller,
            final UUID sessionId,
            final UUID shareId,
            final List<Long> recipients) {
        for (final Long caregiverUserId : recipients) {
            try {
                chatAuditService.logConversationShared(
                        caller.getId(),
                        sessionId == null ? shareId.toString() : sessionId.toString(),
                        caregiverUserId);
            } catch (Exception e) {
                log.warn(
                        "Chat audit share log failed shareId={} caregiverUserId={}: {}",
                        shareId,
                        caregiverUserId,
                        e.getMessage());
            }
        }
    }

    private String writeRecipientJson(final List<Long> recipients) {
        try {
            return objectMapper.writeValueAsString(recipients);
        } catch (JsonProcessingException e) {
            throw new AskAiRejectedException(
                    "INTERNAL_ERROR", "Could not serialize recipients", 500);
        }
    }

    private AiAskShareResponse toResponse(final AiAskConversationShare share) {
        return new AiAskShareResponse(
                share.getId(),
                share.getPatientId(),
                share.getSessionId(),
                parseRecipientIds(share.getRecipientUserIds()),
                share.getMessageCount(),
                share.getCreatedAt(),
                share.getTranscriptJson());
    }

    private List<Long> parseRecipientIds(final String recipientJson) {
        if (recipientJson == null || recipientJson.isBlank()) {
            return List.of();
        }
        try {
            final List<Long> parsed = objectMapper.readValue(recipientJson, LONG_LIST);
            return parsed == null ? List.of() : List.copyOf(parsed);
        } catch (JsonProcessingException e) {
            log.warn("Could not parse share recipient_user_ids: {}", e.getMessage());
            return List.of();
        }
    }

    private List<Long> resolveRecipients(final Long patientUserId, final Long caregiverUserId) {
        final List<CaregiverPatientLinkResponse> links =
                caregiverPatientLinkService.getCaregiversByPatient(patientUserId);
        final Set<Long> activeCaregiverIds = new LinkedHashSet<>();
        for (final CaregiverPatientLinkResponse link : links) {
            if (link != null && link.caregiverUserId() != null && link.isActive() && !link.isExpired()) {
                activeCaregiverIds.add(link.caregiverUserId());
            }
        }
        if (caregiverUserId != null) {
            if (!activeCaregiverIds.contains(caregiverUserId)) {
                throw new AskAiRejectedException(
                        "CAREGIVER_NOT_LINKED",
                        "Selected caregiver is not an active linked caregiver for this patient",
                        400);
            }
            return List.of(caregiverUserId);
        }
        return new ArrayList<>(activeCaregiverIds);
    }

    private TranscriptPayload serializeTranscript(final List<AiAskShareRequest.AiAskShareMessage> messages) {
        final List<Map<String, Object>> rows = new ArrayList<>(messages.size());
        for (final AiAskShareRequest.AiAskShareMessage message : messages) {
            if (message == null || message.text() == null || message.text().isBlank()) {
                continue;
            }
            final Map<String, Object> row = new LinkedHashMap<>();
            row.put("role", normalizeRole(message.role()));
            row.put("text", message.text().trim());
            if (message.occurredAt() != null && !message.occurredAt().isBlank()) {
                row.put("occurredAt", message.occurredAt().trim());
            }
            rows.add(row);
        }
        if (rows.isEmpty()) {
            throw new AskAiRejectedException(
                    "INVALID_REQUEST", "messages must include non-empty text", 400);
        }
        try {
            return new TranscriptPayload(objectMapper.writeValueAsString(rows), rows.size());
        } catch (JsonProcessingException e) {
            throw new AskAiRejectedException(
                    "INTERNAL_ERROR", "Could not serialize transcript", 500);
        }
    }

    private static String normalizeRole(final String role) {
        if (role == null || role.isBlank()) {
            return "assistant";
        }
        final String normalized = role.trim().toLowerCase();
        if (Objects.equals(normalized, "user")
                || Objects.equals(normalized, "assistant")
                || Objects.equals(normalized, "system")) {
            return normalized;
        }
        return "assistant";
    }

    /** Visible for persistNewShare signature / unit tests. */
    public record TranscriptPayload(String json, int messageCount) {}
}
