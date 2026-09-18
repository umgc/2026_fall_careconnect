package com.careconnect.service;

import com.careconnect.dto.SummaryItemConfirmRequest;
import com.careconnect.dto.SummaryItemConfirmResponse;
import com.careconnect.model.CallSummary;
import com.careconnect.model.CallSummaryItemDecision;
import com.careconnect.model.User;
import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.repository.CallSummaryItemDecisionRepository;
import com.careconnect.repository.CallSummaryRepository;
import com.careconnect.service.ai.hitl.HitlService;
import com.careconnect.service.ai.safety.SafetyDecision;
import com.careconnect.service.ai.safety.SafetyInput;
import com.careconnect.service.ai.safety.SafetyOutcome;
import com.careconnect.service.ai.safety.SafetyPipeline;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Task 6.7 — per-item human-in-the-loop confirmation for call summary items
 * ({@code action_item}, {@code appointment}, {@code care_instruction}), per FR-SUM-4 /
 * REQ-SC-5.
 *
 * <p>Medication care instructions are re-validated through {@link SafetyPipeline} before the
 * decision is recorded; when the pipeline escalates to Tier-2, a HITL hold is created instead
 * of clearing the item's confirmation gate, so a clinician reviews it first.
 *
 * <p>{@code approve-for-session} installs Ask-style {@code APPROVE_SESSION} suppression via
 * {@link com.careconnect.service.ai.ask.AiAskConfirmationService} (deterministic session id
 * per call) and clears remaining {@code needsConfirmation} flags on the summary payload.
 *
 * <p>HITL hold creation uses {@link HitlService#createHold} with a unique open-hold claim so
 * concurrent retries reuse the same PENDING_REVIEW row.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CallSummaryItemConfirmService {

    private static final Set<String> VALID_DECISIONS =
            Set.of("approve", "approve-for-session", "decline");
    private static final String DECISION_APPROVE_FOR_SESSION = "approve-for-session";
    private static final String CATEGORY_ACTION_ITEMS = "actionItems";
    private static final String CATEGORY_APPOINTMENTS = "appointments";
    private static final String CATEGORY_CARE_INSTRUCTIONS = "careInstructions";
    private static final List<String> ITEM_CATEGORIES =
            List.of(CATEGORY_ACTION_ITEMS, CATEGORY_APPOINTMENTS, CATEGORY_CARE_INSTRUCTIONS);
    private static final String DECISION_DECLINE = "decline";
    private static final String CARE_INSTRUCTION_TYPE_MEDICATION = "medication";
    private static final String SOURCE_SURFACE_CALL_SUMMARY = "CALL_SUMMARY";

    private final CallSummaryRepository callSummaryRepository;
    private final CallSummaryItemDecisionRepository decisionRepository;
    private final ObjectMapper objectMapper;
    private final SafetyPipeline safetyPipeline;
    private final HitlService hitlService;
    private final com.careconnect.service.ai.ask.AiAskConfirmationService askConfirmationService;

    static String summaryItemCorrelationKey(final String callId, final String itemId) {
        return "call-summary:" + callId + ":" + itemId;
    }

    private static String normalizeDecision(final String rawDecision) {
        if (rawDecision == null) {
            throw new IllegalArgumentException("decision is required");
        }
        final String normalized = rawDecision.trim().toLowerCase(Locale.ROOT);
        if (!VALID_DECISIONS.contains(normalized)) {
            throw new IllegalArgumentException(
                    "decision must be one of " + VALID_DECISIONS + " but was '" + rawDecision + "'");
        }
        return normalized;
    }

    private static String mapCategoryToItemType(final String category) {
        return switch (category) {
            case CATEGORY_ACTION_ITEMS -> "action_item";
            case CATEGORY_APPOINTMENTS -> "appointment";
            case CATEGORY_CARE_INSTRUCTIONS -> "care_instruction";
            default -> category;
        };
    }

    private static String trimToNull(final String value) {
        if (value == null) {
            return null;
        }
        final String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    /**
     * Confirms or declines a single extracted item on the latest stored summary for a call.
     *
     * @param callId  call identifier whose latest summary contains the item
     * @param itemId  server-assigned identifier of the item within the summary payload
     * @param actor   user recording the decision
     * @param request decision, optional destination, and optional notes
     * @return the recorded decision, or a held response when the item required clinician review
     */
    @Transactional
    public SummaryItemConfirmResponse confirm(
            final String callId,
            final String itemId,
            final User actor,
            final SummaryItemConfirmRequest request) {
        if (callId == null || callId.isBlank()) {
            throw new IllegalArgumentException("callId is required");
        }
        if (itemId == null || itemId.isBlank()) {
            throw new IllegalArgumentException("itemId is required");
        }
        if (actor == null || actor.getId() == null) {
            throw new IllegalArgumentException("An authenticated actor is required");
        }
        final String decision = normalizeDecision(request == null ? null : request.decision());

        final CallSummary summary = callSummaryRepository
                .findTopByCallIdOrderByGeneratedAtDesc(callId)
                .orElseThrow(() -> new IllegalArgumentException(
                        "No summary found for callId " + callId));

        final Map<String, Object> payload = parsePayload(summary.getSummaryJson());
        final ItemLookup lookup = findItem(payload, itemId);
        if (lookup == null) {
            throw new IllegalArgumentException(
                    "Item not found in summary: itemId=" + itemId);
        }

        // Idempotency first: already-confirmed items must not re-enter medication
        // safety / HITL (retries would otherwise return held=true again).
        final Object needsConfirmationRaw = lookup.item().get("needsConfirmation");
        final boolean alreadyConfirmed = Boolean.FALSE.equals(needsConfirmationRaw)
                || "false".equalsIgnoreCase(String.valueOf(needsConfirmationRaw));
        if (alreadyConfirmed) {
            final Optional<CallSummaryItemDecision> prior =
                    decisionRepository.findTopBySummaryIdAndItemIdOrderByDecidedAtDesc(
                            summary.getId(), itemId);
            if (prior.isPresent()) {
                final CallSummaryItemDecision existing = prior.get();
                return new SummaryItemConfirmResponse(
                        itemId,
                        existing.getDecision(),
                        false,
                        null,
                        existing.getId());
            }
        }

        final boolean isMedicationInstruction =
                CATEGORY_CARE_INSTRUCTIONS.equals(lookup.category())
                        && CARE_INSTRUCTION_TYPE_MEDICATION.equalsIgnoreCase(
                        String.valueOf(lookup.item().get("type")));

        final boolean approveForSession = DECISION_APPROVE_FOR_SESSION.equals(decision);
        final boolean sessionApproved = askConfirmationService.hasCallSummarySessionApproval(
                callId, summary.getPatientId(), actor.getId());

        // Session-wide approve must install APPROVE_SESSION / clear gates — do not
        // dead-end the first med item in HITL before that happens.
        if (isMedicationInstruction
                && !DECISION_DECLINE.equals(decision)
                && !sessionApproved
                && !approveForSession) {
            final SummaryItemConfirmResponse held =
                    tryHoldForMedicationSafety(summary, callId, itemId, actor, lookup.item());
            if (held != null) {
                return held;
            }
        }

        return recordDecision(summary, payload, lookup, itemId, decision, actor, request, callId);
    }

    /**
     * Re-validates a medication care-instruction item via {@link SafetyPipeline}. Returns a
     * held response when the pipeline escalates to Tier-2, or {@code null} when the item is
     * safe to record immediately.
     */
    private SummaryItemConfirmResponse tryHoldForMedicationSafety(
            final CallSummary summary,
            final String callId,
            final String itemId,
            final User actor,
            final Map<String, Object> item) {
        final Long patientId = summary.getPatientId();
        if (patientId == null) {
            throw new IllegalStateException(
                    "Cannot confirm medication care instruction without patientId on summary "
                            + summary.getId());
        }

        final String correlationKey = summaryItemCorrelationKey(callId, itemId);
        final Optional<AiHeldItem> openHold =
                hitlService.findOpenHold(patientId, SOURCE_SURFACE_CALL_SUMMARY, correlationKey);
        if (openHold.isPresent()) {
            if (log.isInfoEnabled()) {
                log.info(
                        "Reusing open HITL hold {} for call summary item {} callId={}",
                        openHold.get().getId(), itemId, callId);
            }
            return new SummaryItemConfirmResponse(
                    itemId, null, true, openHold.get().getId(), null);
        }

        final String instructionText = String.valueOf(item.getOrDefault("text", ""));
        final SafetyInput safetyInput = new SafetyInput(
                correlationKey,
                instructionText,
                List.of(),
                patientId,
                actor.getId(),
                null,
                UUID.randomUUID(),
                null,
                SOURCE_SURFACE_CALL_SUMMARY,
                "en-US",
                false,
                List.of());
        final SafetyOutcome outcome = safetyPipeline.process(safetyInput);
        if (outcome.decision() != SafetyDecision.HOLD_TIER2) {
            return null;
        }
        final AiHeldItem held = hitlService.createHold(safetyInput, outcome, List.of());
        if (log.isInfoEnabled()) {
            log.info(
                    "Call summary item {} routed to HITL hold {} for callId={}",
                    itemId, held.getId(), summary.getCallId());
        }
        return new SummaryItemConfirmResponse(itemId, null, true, held.getId(), null);
    }

    private SummaryItemConfirmResponse recordDecision(
            final CallSummary summary,
            final Map<String, Object> payload,
            final ItemLookup lookup,
            final String itemId,
            final String decision,
            final User actor,
            final SummaryItemConfirmRequest request,
            final String callId) {
        final CallSummaryItemDecision decisionRow = CallSummaryItemDecision.builder()
                .summaryId(summary.getId())
                .itemId(itemId)
                .itemType(mapCategoryToItemType(lookup.category()))
                .decision(decision)
                .destination(DECISION_DECLINE.equals(decision)
                        ? null
                        : (request == null ? null : trimToNull(request.destination())))
                .decidedByUserId(actor.getId())
                .decidedAt(LocalDateTime.now())
                .notes(request == null ? null : trimToNull(request.notes()))
                .build();
        final CallSummaryItemDecision savedDecision = decisionRepository.save(decisionRow);

        lookup.item().put("needsConfirmation", Boolean.FALSE);
        if (DECISION_APPROVE_FOR_SESSION.equals(decision)) {
            // Persist Ask APPROVE_SESSION first; only clear sibling gates on success
            // so the UI cannot show "all confirmed" without session suppression.
            if (summary.getPatientId() == null) {
                throw new IllegalStateException(
                        "Cannot approve-for-session without patientId on summary "
                                + summary.getId());
            }
            askConfirmationService.installCallSummarySessionApproval(
                    actor, summary.getPatientId(), callId);
            clearAllNeedsConfirmation(payload);
        }
        summary.setSummaryJson(toJsonSafe(payload));
        callSummaryRepository.save(summary);

        return new SummaryItemConfirmResponse(
                itemId, decision, false, null, savedDecision.getId());
    }

    @SuppressWarnings("unchecked")
    private void clearAllNeedsConfirmation(final Map<String, Object> payload) {
        for (final String category : ITEM_CATEGORIES) {
            final Object rawList = payload.get(category);
            if (!(rawList instanceof List<?> list)) {
                continue;
            }
            for (final Object rawItem : list) {
                if (rawItem instanceof Map<?, ?> rawMap) {
                    ((Map<String, Object>) rawMap).put("needsConfirmation", Boolean.FALSE);
                }
            }
        }
    }

    @SuppressWarnings("unchecked")
    private ItemLookup findItem(final Map<String, Object> payload, final String itemId) {
        for (final String category : ITEM_CATEGORIES) {
            final Object rawList = payload.get(category);
            if (!(rawList instanceof List<?> list)) {
                continue;
            }
            for (final Object rawItem : list) {
                if (!(rawItem instanceof Map<?, ?> rawMap)) {
                    continue;
                }
                final Map<String, Object> item = (Map<String, Object>) rawMap;
                if (itemId.equals(String.valueOf(item.get("itemId")))) {
                    return new ItemLookup(category, item);
                }
            }
        }
        return null;
    }

    private Map<String, Object> parsePayload(final String summaryJson) {
        if (summaryJson == null || summaryJson.isBlank()) {
            return new LinkedHashMap<>();
        }
        try {
            return objectMapper.readValue(
                    summaryJson, new TypeReference<LinkedHashMap<String, Object>>() {
                    });
        } catch (final Exception ex) {
            throw new IllegalStateException("Failed to parse stored summary payload", ex);
        }
    }

    private String toJsonSafe(final Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (final Exception ex) {
            throw new IllegalStateException("Failed to serialize call summary payload", ex);
        }
    }

    private record ItemLookup(String category, Map<String, Object> item) {
    }
}
