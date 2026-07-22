package com.careconnect.service.ai.hitl;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.dto.ai.AiConfirmationHint;
import com.careconnect.dto.ai.AiDisclaimer;
import com.careconnect.dto.ai.hitl.HitlDetailResponse;
import com.careconnect.dto.ai.hitl.HitlQueueItem;
import com.careconnect.dto.ai.hitl.HitlStatusResponse;
import com.careconnect.model.Patient;
import com.careconnect.model.User;
import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.model.ai.hitl.AiHeldItemStatus;
import com.careconnect.model.ai.hitl.AiSafetyAuditEvent;
import com.careconnect.repository.PatientRepository;
import com.careconnect.repository.ai.hitl.AiHeldItemRepository;
import com.careconnect.repository.ai.hitl.AiSafetyAuditEventRepository;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.CaregiverPatientLinkService;
import com.careconnect.service.FamilyMemberService;
import com.careconnect.service.ai.AskAiSafetyCopy;
import com.careconnect.service.ai.safety.SafetyDecision;
import com.careconnect.service.ai.safety.SafetyInput;
import com.careconnect.service.ai.safety.SafetyOutcome;
import com.careconnect.service.ai.safety.SafetyPipeline;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.HexFormat;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

/**
 * Tier-2 HITL hold queue (create / release / reject / poll).
 */
@Service
public class HitlService {

    public static final String REVIEWING_MESSAGE =
            "We're reviewing this before showing it to you.";
    public static final String REJECTED_MESSAGE =
            "A reviewer could not release this answer. Please contact your care provider.";
    public static final String EXPIRED_MESSAGE =
            "This review request expired without a decision. Please ask again or contact your care provider.";

    private final AiHeldItemRepository heldItemRepository;
    private final AiSafetyAuditEventRepository auditEventRepository;
    private final PatientRepository patientRepository;
    private final CaregiverPatientLinkService caregiverPatientLinkService;
    private final FamilyMemberService familyMemberService;
    private final SafetyPipeline safetyPipeline;
    private final ObjectMapper objectMapper;
    private final long ttlHours;

    public HitlService(
            final AiHeldItemRepository heldItemRepository,
            final AiSafetyAuditEventRepository auditEventRepository,
            final PatientRepository patientRepository,
            final CaregiverPatientLinkService caregiverPatientLinkService,
            final FamilyMemberService familyMemberService,
            final SafetyPipeline safetyPipeline,
            final ObjectMapper objectMapper,
            @Value("${careconnect.ai.hitl.ttl-hours:72}") final long ttlHours) {
        this.heldItemRepository = heldItemRepository;
        this.auditEventRepository = auditEventRepository;
        this.patientRepository = patientRepository;
        this.caregiverPatientLinkService = caregiverPatientLinkService;
        this.familyMemberService = familyMemberService;
        this.safetyPipeline = safetyPipeline;
        this.objectMapper = objectMapper;
        this.ttlHours = ttlHours <= 0 ? 72 : ttlHours;
    }

    @Transactional
    public AiHeldItem createHold(
            final SafetyInput input,
            final SafetyOutcome outcome,
            final List<AiCitation> citations) {
        final Instant now = Instant.now();
        final AiHeldItem item = AiHeldItem.builder()
                .id(UUID.randomUUID())
                .patientId(input.patientId())
                .requesterUserId(input.callerUserId())
                .sessionId(input.sessionId())
                .auditId(input.auditId())
                .requestId(input.requestId())
                .sourceSurface(input.sourceSurface() == null ? "ASK_AI" : input.sourceSurface())
                .status(AiHeldItemStatus.PENDING_REVIEW)
                .tier(2)
                .triggerCodesJson(writeJson(outcome.triggerCodes()))
                .queryText(truncateQueryText(input.query()))
                .queryTextHash(sha256(input.query()))
                .draftAnswer(input.draftAnswerText() == null ? "" : input.draftAnswerText())
                .citationsJson(writeJson(citations == null ? List.of() : citations))
                .validationFindingsJson(writeJson(outcome.findings()))
                .deliveryStatus("HELD")
                .expiresAt(now.plus(ttlHours, ChronoUnit.HOURS))
                .createdAt(now)
                .updatedAt(now)
                .build();
        final AiHeldItem saved = heldItemRepository.save(item);
        appendAudit(
                saved.getAuditId(),
                saved.getId(),
                "HITL_HELD",
                input.callerUserId(),
                "{\"triggerCodes\":" + saved.getTriggerCodesJson() + "}");
        return saved;
    }

    @Transactional
    public HitlStatusResponse getStatus(final UUID heldItemId, final User caller)
            throws UnauthorizedException {
        final AiHeldItem item = requireItem(heldItemId);
        assertStatusPollAccess(caller, item);
        expireIfNeeded(item);
        return toStatus(item);
    }

    @Transactional
    public List<HitlQueueItem> listQueue(final User reviewer) throws UnauthorizedException {
        assertReviewerRole(reviewer);
        final List<AiHeldItem> pending = loadPendingForReviewer(reviewer);
        return pending.stream()
                .peek(this::expireIfNeeded)
                .filter(item -> item.getStatus() == AiHeldItemStatus.PENDING_REVIEW)
                .map(this::toQueueItem)
                .toList();
    }

    /**
     * Expire past-due PENDING holds in batches (background scanner).
     *
     * @return number of rows this scan transitioned to EXPIRED
     */
    @Transactional
    public int expireDueHolds(final int batchSize) {
        final int limit = Math.max(1, batchSize);
        final Instant now = Instant.now();
        final List<AiHeldItem> due = heldItemRepository
                .findByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(
                        AiHeldItemStatus.PENDING_REVIEW,
                        now,
                        PageRequest.of(0, limit));
        int expired = 0;
        for (final AiHeldItem item : due) {
            expireIfNeeded(item);
            if (item.getStatus() == AiHeldItemStatus.EXPIRED) {
                expired++;
            }
        }
        return expired;
    }

    @Transactional
    public HitlDetailResponse getDetail(final UUID heldItemId, final User reviewer)
            throws UnauthorizedException {
        assertReviewerRole(reviewer);
        final AiHeldItem item = requireItem(heldItemId);
        assertReviewerPatientAccess(reviewer, item);
        expireIfNeeded(item);
        return toDetail(item);
    }

    @Transactional
    public HitlDetailResponse release(
            final UUID heldItemId,
            final User reviewer,
            final String editedAnswer,
            final String notes) throws UnauthorizedException {
        assertReviewerRole(reviewer);
        final AiHeldItem item = requireItem(heldItemId);
        assertReviewerPatientAccess(reviewer, item);
        expireIfNeeded(item);
        if (item.getStatus() != AiHeldItemStatus.PENDING_REVIEW) {
            throw new HitlConflictException("Held item is not pending review");
        }
        final boolean requiresEditedAnswer = hasUnsupportedClaimTrigger(item);
        if (requiresEditedAnswer && (editedAnswer == null || editedAnswer.isBlank())) {
            throw new HitlConflictException(
                    "Unsupported-claim holds require an edited answer before release");
        }
        final Instant now = Instant.now();
        final boolean edited = editedAnswer != null && !editedAnswer.isBlank()
                && !editedAnswer.trim().equals(item.getDraftAnswer());
        if (requiresEditedAnswer && !edited) {
            throw new HitlConflictException(
                    "Unsupported-claim holds require an edited answer before release");
        }
        final String finalAnswer = edited ? editedAnswer.trim() : item.getDraftAnswer();
        if (edited) {
            assertEditedReleaseSafe(item, reviewer, finalAnswer);
        }
        // Edited text is clinician-authored; do not ship stale model citations with it.
        final String citationsJson = edited ? "[]" : item.getCitationsJson();
        final String reviewNotes = truncateNotes(notes);
        final int updated = heldItemRepository.updateOutcomeIfStatus(
                item.getId(),
                AiHeldItemStatus.PENDING_REVIEW,
                AiHeldItemStatus.DELIVERED,
                "DELIVERED",
                finalAnswer,
                citationsJson,
                reviewer.getId(),
                now,
                reviewNotes,
                now);
        if (updated != 1) {
            throw new HitlConflictException("Held item is not pending review");
        }
        item.setFinalAnswer(finalAnswer);
        item.setCitationsJson(citationsJson);
        item.setReviewerUserId(reviewer.getId());
        item.setReviewedAt(now);
        item.setReviewNotes(reviewNotes);
        item.setDeliveryStatus("DELIVERED");
        item.setStatus(AiHeldItemStatus.DELIVERED);
        item.setUpdatedAt(now);
        appendAudit(
                item.getAuditId(),
                item.getId(),
                "HITL_RELEASED",
                reviewer.getId(),
                "{\"edited\":" + edited + "}");
        return toDetail(item);
    }

    @Transactional
    public HitlDetailResponse reject(
            final UUID heldItemId,
            final User reviewer,
            final String reason) throws UnauthorizedException {
        assertReviewerRole(reviewer);
        final AiHeldItem item = requireItem(heldItemId);
        assertReviewerPatientAccess(reviewer, item);
        expireIfNeeded(item);
        if (item.getStatus() != AiHeldItemStatus.PENDING_REVIEW) {
            throw new HitlConflictException("Held item is not pending review");
        }
        final Instant now = Instant.now();
        final String reviewNotes = truncateNotes(reason);
        final int updated = heldItemRepository.updateOutcomeIfStatus(
                item.getId(),
                AiHeldItemStatus.PENDING_REVIEW,
                AiHeldItemStatus.REJECTED,
                "WITHHELD_PERMANENTLY",
                null,
                item.getCitationsJson(),
                reviewer.getId(),
                now,
                reviewNotes,
                now);
        if (updated != 1) {
            throw new HitlConflictException("Held item is not pending review");
        }
        item.setStatus(AiHeldItemStatus.REJECTED);
        item.setReviewerUserId(reviewer.getId());
        item.setReviewedAt(now);
        item.setReviewNotes(reviewNotes);
        item.setDeliveryStatus("WITHHELD_PERMANENTLY");
        item.setFinalAnswer(null);
        item.setUpdatedAt(now);
        appendAudit(
                item.getAuditId(),
                item.getId(),
                "HITL_REJECTED",
                reviewer.getId(),
                "{\"reason\":" + writeJson(reason == null ? "" : reason) + "}");
        return toDetail(item);
    }

    public static String pollUrl(final UUID heldItemId) {
        return "/v1/api/ai/hitl/" + heldItemId + "/status";
    }

    private AiHeldItem requireItem(final UUID heldItemId) {
        return heldItemRepository.findById(heldItemId)
                .orElseThrow(() -> new HitlNotFoundException("Held item not found"));
    }

    private void expireIfNeeded(final AiHeldItem item) {
        if (item.getStatus() != AiHeldItemStatus.PENDING_REVIEW || !isExpired(item)) {
            return;
        }
        final Instant now = Instant.now();
        final int updated = heldItemRepository.expireIfPending(item.getId(), now);
        if (updated != 1) {
            // Release/reject won the race — refresh in-memory view for accurate poll/detail.
            heldItemRepository.findById(item.getId()).ifPresent(fresh -> {
                item.setStatus(fresh.getStatus());
                item.setDeliveryStatus(fresh.getDeliveryStatus());
                item.setFinalAnswer(fresh.getFinalAnswer());
                item.setReviewerUserId(fresh.getReviewerUserId());
                item.setReviewedAt(fresh.getReviewedAt());
                item.setReviewNotes(fresh.getReviewNotes());
                item.setUpdatedAt(fresh.getUpdatedAt());
            });
            return;
        }
        item.setStatus(AiHeldItemStatus.EXPIRED);
        item.setDeliveryStatus("WITHHELD_PERMANENTLY");
        item.setUpdatedAt(now);
        appendAudit(
                item.getAuditId(),
                item.getId(),
                "HITL_EXPIRED",
                null,
                "{}");
    }

    private boolean isExpired(final AiHeldItem item) {
        return item.getExpiresAt() != null && Instant.now().isAfter(item.getExpiresAt());
    }

    private void assertStatusPollAccess(final User caller, final AiHeldItem item)
            throws UnauthorizedException {
        if (caller == null || caller.getId() == null) {
            throw new UnauthorizedException("Authenticated user required");
        }
        if (caller.getRole() == Role.ADMIN) {
            return;
        }
        // Always re-check live Ask patient scope. Requester identity alone is not enough:
        // a caregiver may lose the patient link after creating the hold.
        // Deny with NOT_FOUND so unscoped callers cannot distinguish missing vs forbidden IDs.
        if (!hasAskPatientAccess(caller, item.getPatientId())) {
            throw new HitlNotFoundException("Held item not found");
        }
    }

    private boolean hasAskPatientAccess(final User caller, final Long patientId) {
        if (caller == null || caller.getId() == null || caller.getRole() == null || patientId == null) {
            return false;
        }
        final Patient patient = patientRepository.findById(patientId).orElse(null);
        if (patient == null || patient.getUser() == null || patient.getUser().getId() == null) {
            return false;
        }
        final Long patientUserId = patient.getUser().getId();
        return switch (caller.getRole()) {
            case ADMIN -> true;
            case PATIENT -> Objects.equals(caller.getId(), patientUserId);
            case CAREGIVER -> caregiverPatientLinkService.hasAccessToPatient(
                    caller.getId(), patientUserId);
            case FAMILY_MEMBER -> familyMemberService.hasAccessToPatient(
                    caller.getId(), patientUserId);
            default -> false;
        };
    }

    private void assertReviewerRole(final User reviewer) throws UnauthorizedException {
        if (reviewer == null || reviewer.getId() == null) {
            throw new UnauthorizedException("Authenticated user required");
        }
        final Role role = reviewer.getRole();
        if (role != Role.ADMIN && role != Role.CAREGIVER) {
            throw new UnauthorizedException("Reviewer role required");
        }
    }

    private void assertReviewerPatientAccess(final User reviewer, final AiHeldItem item) {
        if (!hasReviewerPatientAccess(reviewer, item)) {
            // Uniform NOT_FOUND so unscoped reviewers cannot distinguish missing vs forbidden IDs.
            throw new HitlNotFoundException("Held item not found");
        }
    }

    private boolean hasReviewerPatientAccess(final User reviewer, final AiHeldItem item) {
        if (reviewer == null || reviewer.getId() == null || reviewer.getRole() == null) {
            return false;
        }
        if (reviewer.getRole() == Role.ADMIN) {
            return true;
        }
        if (reviewer.getRole() != Role.CAREGIVER) {
            return false;
        }
        final Long patientUserId = patientRepository.findById(item.getPatientId())
                .map(Patient::getUser)
                .map(User::getId)
                .orElse(null);
        if (patientUserId == null) {
            return false;
        }
        return caregiverPatientLinkService.hasAccessToPatient(reviewer.getId(), patientUserId);
    }

    private List<AiHeldItem> loadPendingForReviewer(final User reviewer) {
        if (reviewer.getRole() == Role.ADMIN) {
            return heldItemRepository.findByStatusOrderByCreatedAtAsc(AiHeldItemStatus.PENDING_REVIEW);
        }
        final List<Long> linkedPatientIds = patientRepository.findIdsLinkedToCaregiver(
                reviewer.getId(), LocalDateTime.now());
        if (linkedPatientIds.isEmpty()) {
            return List.of();
        }
        return heldItemRepository.findByPatientIdInAndStatusOrderByCreatedAtAsc(
                linkedPatientIds, AiHeldItemStatus.PENDING_REVIEW);
    }

    private void assertEditedReleaseSafe(
            final AiHeldItem item,
            final User reviewer,
            final String finalAnswer) {
        final SafetyOutcome recheck = safetyPipeline.process(new SafetyInput(
                item.getQueryText(),
                finalAnswer,
                List.of(),
                item.getPatientId(),
                reviewer.getId(),
                item.getSessionId(),
                item.getAuditId(),
                item.getRequestId(),
                item.getSourceSurface(),
                "en-US",
                false,
                List.of()));
        final boolean emergency = recheck.triggerCodes().stream()
                .anyMatch(code -> "EMERGENCY_SYMPTOM".equals(code));
        if (recheck.decision() == SafetyDecision.BLOCK || emergency) {
            throw new HitlConflictException(
                    "Edited answer still matches emergency or blocked safety patterns; "
                            + "revise before release");
        }
    }

    private boolean hasUnsupportedClaimTrigger(final AiHeldItem item) {
        return readStringList(item.getTriggerCodesJson()).stream()
                .anyMatch(code -> "UNSUPPORTED_CLAIM".equals(code));
    }

    private HitlStatusResponse toStatus(final AiHeldItem item) {
        return switch (item.getStatus()) {
            case PENDING_REVIEW -> new HitlStatusResponse(
                    item.getId(),
                    item.getStatus().name(),
                    "HELD",
                    REVIEWING_MESSAGE,
                    null,
                    List.of(),
                    item.getExpiresAt(),
                    null,
                    null);
            case DELIVERED, APPROVED_AS_IS, APPROVED_EDITED -> new HitlStatusResponse(
                    item.getId(),
                    AiHeldItemStatus.DELIVERED.name(),
                    "DELIVERED",
                    null,
                    item.getFinalAnswer() != null ? item.getFinalAnswer() : item.getDraftAnswer(),
                    readJsonList(item.getCitationsJson()),
                    item.getExpiresAt(),
                    deliveredDisclaimer(),
                    deliveredConfirmation());
            case REJECTED -> new HitlStatusResponse(
                    item.getId(),
                    item.getStatus().name(),
                    "WITHHELD_PERMANENTLY",
                    REJECTED_MESSAGE,
                    null,
                    List.of(),
                    item.getExpiresAt(),
                    null,
                    null);
            case EXPIRED -> new HitlStatusResponse(
                    item.getId(),
                    item.getStatus().name(),
                    "WITHHELD_PERMANENTLY",
                    EXPIRED_MESSAGE,
                    null,
                    List.of(),
                    item.getExpiresAt(),
                    null,
                    null);
        };
    }

    private static AiDisclaimer deliveredDisclaimer() {
        return new AiDisclaimer(AskAiSafetyCopy.DISCLAIMER_EN, true, true, "en-US");
    }

    private static AiConfirmationHint deliveredConfirmation() {
        return new AiConfirmationHint(true, AskAiSafetyCopy.CONFIRM_EN);
    }

    private HitlQueueItem toQueueItem(final AiHeldItem item) {
        return new HitlQueueItem(
                item.getId(),
                item.getPatientId(),
                readStringList(item.getTriggerCodesJson()),
                previewQueryText(item.getQueryText()),
                item.getSourceSurface(),
                item.getCreatedAt(),
                item.getExpiresAt());
    }

    private HitlDetailResponse toDetail(final AiHeldItem item) {
        return new HitlDetailResponse(
                item.getId(),
                item.getPatientId(),
                item.getRequesterUserId(),
                item.getStatus().name(),
                item.getDeliveryStatus(),
                readStringList(item.getTriggerCodesJson()),
                item.getQueryText(),
                item.getDraftAnswer(),
                item.getFinalAnswer(),
                item.getCitationsJson(),
                item.getValidationFindingsJson(),
                item.getCreatedAt(),
                item.getExpiresAt(),
                item.getReviewedAt(),
                item.getReviewerUserId(),
                item.getReviewNotes());
    }

    private void appendAudit(
            final UUID auditId,
            final UUID heldItemId,
            final String eventType,
            final Long actorUserId,
            final String payloadJson) {
        auditEventRepository.save(AiSafetyAuditEvent.builder()
                .id(UUID.randomUUID())
                .auditId(auditId)
                .heldItemId(heldItemId)
                .eventType(eventType)
                .actorUserId(actorUserId)
                .payloadJson(payloadJson)
                .createdAt(Instant.now())
                .build());
    }

    private String writeJson(final Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (final JsonProcessingException ex) {
            throw new IllegalStateException("Unable to serialize HITL payload", ex);
        }
    }

    private List<Object> readJsonList(final String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<Object>>() { });
        } catch (final JsonProcessingException ex) {
            return List.of();
        }
    }

    private List<String> readStringList(final String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return objectMapper.readValue(json, new TypeReference<List<String>>() { });
        } catch (final JsonProcessingException ex) {
            return List.of();
        }
    }

    private static String truncateNotes(final String notes) {
        if (notes == null) {
            return null;
        }
        final String trimmed = notes.trim();
        return trimmed.length() <= 500 ? trimmed : trimmed.substring(0, 500);
    }

    private static final int QUERY_TEXT_MAX_CHARS = 2000;
    private static final int QUERY_PREVIEW_MAX_CHARS = 120;

    private static String truncateQueryText(final String query) {
        if (query == null) {
            return null;
        }
        final String trimmed = query.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        return trimmed.length() <= QUERY_TEXT_MAX_CHARS
                ? trimmed
                : trimmed.substring(0, QUERY_TEXT_MAX_CHARS);
    }

    private static String previewQueryText(final String queryText) {
        if (queryText == null || queryText.isBlank()) {
            return null;
        }
        final String trimmed = queryText.trim();
        return trimmed.length() <= QUERY_PREVIEW_MAX_CHARS
                ? trimmed
                : trimmed.substring(0, QUERY_PREVIEW_MAX_CHARS);
    }

    private static String sha256(final String value) {
        if (value == null) {
            return null;
        }
        try {
            final MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(
                    digest.digest(value.getBytes(StandardCharsets.UTF_8)));
        } catch (final NoSuchAlgorithmException ex) {
            throw new IllegalStateException(ex);
        }
    }
}
