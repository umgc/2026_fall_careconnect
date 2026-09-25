package com.careconnect.service.ai.audit;

import com.careconnect.dto.ai.AiCitation;
import com.careconnect.model.ai.audit.AiAskAuditDeliverySupplement;
import com.careconnect.model.ai.audit.AiAskAuditEvent;
import com.careconnect.model.ai.audit.AiAskAuditRecord;
import com.careconnect.repository.ai.audit.AiAskAuditDeliverySupplementRepository;
import com.careconnect.repository.ai.audit.AiAskAuditEventRepository;
import com.careconnect.repository.ai.audit.AiAskAuditRecordRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * FR-AI-10 Ask AI audit ledger. Fail-soft: persistence errors are logged and never
 * abort the Ask AI or HITL request path. Hash-only PHI policy for query/answer text.
 */
@Service
public class AiAskAuditService {

    public static final String REQUEST_STARTED = "REQUEST_STARTED";
    public static final String SCOPE_GRANTED = "SCOPE_GRANTED";
    public static final String SCOPE_DENIED = "SCOPE_DENIED";
    public static final String RETRIEVAL_COMPLETED = "RETRIEVAL_COMPLETED";
    public static final String NO_RECORDS = "NO_RECORDS";
    public static final String LLM_COMPLETED = "LLM_COMPLETED";
    public static final String VALIDATION_COMPLETED = "VALIDATION_COMPLETED";
    public static final String TIER_ASSIGNED = "TIER_ASSIGNED";
    public static final String CITATIONS_ASSEMBLED = "CITATIONS_ASSEMBLED";
    public static final String DELIVERED = "DELIVERED";
    public static final String HELD = "HELD";
    public static final String HITL_RELEASED = "HITL_RELEASED";
    public static final String HITL_REJECTED = "HITL_REJECTED";
    public static final String HITL_EXPIRED = "HITL_EXPIRED";
    public static final String ERROR = "ERROR";
    public static final String GOVERNANCE_BLOCKED = "GOVERNANCE_BLOCKED";
    private static final Logger log = LoggerFactory.getLogger(AiAskAuditService.class);
    private final AiAskAuditRecordRepository recordRepository;
    private final AiAskAuditEventRepository eventRepository;
    private final AiAskAuditDeliverySupplementRepository deliveryRepository;
    private final ObjectMapper objectMapper;

    public AiAskAuditService(
            final AiAskAuditRecordRepository recordRepository,
            final AiAskAuditEventRepository eventRepository,
            final AiAskAuditDeliverySupplementRepository deliveryRepository,
            final ObjectMapper objectMapper) {
        this.recordRepository = recordRepository;
        this.eventRepository = eventRepository;
        this.deliveryRepository = deliveryRepository;
        this.objectMapper = objectMapper;
    }

    static String terminalEventType(final FinalizeCommand command) {
        if (command == null || command.deliveryStatus() == null) {
            return ERROR;
        }
        return switch (command.deliveryStatus()) {
            case "HELD" -> HELD;
            case "NO_RECORDS" -> NO_RECORDS;
            case "DELIVERED" -> DELIVERED;
            default -> command.errorCode() != null ? ERROR : DELIVERED;
        };
    }

    /**
     * FR-AI-10 audit-safe citation shape: keep ids/types, hash excerpt, never store raw text.
     */
    static List<Map<String, Object>> auditSafeCitations(final Object citations, final Long patientId) {
        if (!(citations instanceof List<?> list) || list.isEmpty()) {
            return List.of();
        }
        final List<Map<String, Object>> safe = new ArrayList<>(list.size());
        for (final Object item : list) {
            if (item instanceof AiCitation citation) {
                safe.add(redactCitation(citation, patientId));
            } else if (item instanceof Map<?, ?> map) {
                safe.add(redactCitationMap(map, patientId));
            }
        }
        return List.copyOf(safe);
    }

    private static Map<String, Object> redactCitation(final AiCitation citation, final Long patientId) {
        final Map<String, Object> map = new LinkedHashMap<>();
        map.put("citationId", citation.citationId());
        map.put("recordType", citation.recordType() == null ? null : citation.recordType().name());
        map.put("sourceKind", citation.sourceKind());
        map.put("sourceRecordId", citation.sourceRecordId());
        map.put("chunkId", citation.chunkId() == null ? null : citation.chunkId().toString());
        map.put("title", citation.title());
        map.put("occurredAt", citation.occurredAt() == null ? null : citation.occurredAt().toString());
        map.put("deepLink", citation.deepLink());
        map.put("confidence", citation.confidence());
        map.put("excerptHash", hashText(citation.excerpt(), patientId));
        map.put("excerptLength", citation.excerpt() == null ? 0 : citation.excerpt().length());
        return map;
    }

    private static Map<String, Object> redactCitationMap(final Map<?, ?> raw, final Long patientId) {
        final Map<String, Object> map = new LinkedHashMap<>();
        copyIfPresent(raw, map, "citationId");
        copyIfPresent(raw, map, "recordType");
        copyIfPresent(raw, map, "sourceKind");
        copyIfPresent(raw, map, "sourceRecordId");
        copyIfPresent(raw, map, "chunkId");
        copyIfPresent(raw, map, "title");
        copyIfPresent(raw, map, "occurredAt");
        copyIfPresent(raw, map, "deepLink");
        copyIfPresent(raw, map, "confidence");
        final Object excerpt = raw.get("excerpt");
        final String excerptText = excerpt == null ? null : String.valueOf(excerpt);
        if (raw.get("excerptHash") != null && excerpt == null) {
            map.put("excerptHash", raw.get("excerptHash"));
            map.put("excerptLength", raw.get("excerptLength") == null ? 0 : raw.get("excerptLength"));
        } else {
            map.put("excerptHash", hashText(excerptText, patientId));
            map.put("excerptLength", excerptText == null ? 0 : excerptText.length());
        }
        return map;
    }

    private static void copyIfPresent(
            final Map<?, ?> raw, final Map<String, Object> target, final String key) {
        if (raw.containsKey(key) && raw.get(key) != null) {
            target.put(key, raw.get(key));
        }
    }

    static String hashText(final String text, final Long patientId) {
        final String material = (text == null ? "" : text) + "|" + (patientId == null ? "0" : patientId);
        try {
            final MessageDigest digest = MessageDigest.getInstance("SHA-256");
            final byte[] hashed = digest.digest(material.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hashed);
        } catch (final NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 unavailable", ex);
        }
    }

    private static String nullToEmpty(final String value) {
        return value == null ? "" : value;
    }

    /**
     * Allocates correlation ids and appends {@code REQUEST_STARTED}. The immutable
     * completion record is written later via {@link #finalizeRecord}.
     */
    public AuditSession startRequest(final StartRequestCommand command) {
        final UUID auditId = command.auditId() != null ? command.auditId() : UUID.randomUUID();
        final UUID requestId = command.requestId() != null ? command.requestId() : UUID.randomUUID();
        final AtomicInteger sequence = new AtomicInteger(0);
        final AuditSession session = new AuditSession(
                auditId,
                requestId,
                command.sessionId(),
                command.patientId(),
                command.callerUserId(),
                command.callerRole(),
                command.inputModality() == null ? "TEXT" : command.inputModality(),
                command.locale() == null ? "en-US" : command.locale(),
                hashText(command.queryText(), command.patientId()),
                command.queryText() == null ? 0 : command.queryText().length(),
                command.clientRequestId(),
                sequence);
        appendEvent(session, REQUEST_STARTED, command.callerUserId(), Map.of(
                "requestId", requestId.toString(),
                "inputModality", session.inputModality(),
                "clientRequestId", nullToEmpty(command.clientRequestId())));
        return session;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void appendEvent(
            final AuditSession session,
            final String eventType,
            final Long actorUserId,
            final Map<String, ?> payload) {
        if (session == null || eventType == null || eventType.isBlank()) {
            return;
        }
        try {
            persistEvent(
                    session.auditId(),
                    session.sequence().incrementAndGet(),
                    eventType,
                    actorUserId,
                    payload);
        } catch (final Exception ex) {
            log.warn("Ask AI audit event {} failed for auditId={}: {}",
                    eventType, session.auditId(), ex.getMessage());
        }
    }

    /**
     * Appends an event for an existing audit chain (HITL release/reject/expire) using DB
     * sequence continuation. Retries on unique-sequence races.
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void appendStandaloneEvent(
            final UUID auditId,
            final String eventType,
            final Long actorUserId,
            final Map<String, ?> payload) {
        if (auditId == null || eventType == null || eventType.isBlank()) {
            return;
        }
        for (int attempt = 0; attempt < 3; attempt++) {
            try {
                final int next = eventRepository.findMaxSequence(auditId) + 1;
                persistEvent(auditId, next, eventType, actorUserId, payload);
                return;
            } catch (final DataIntegrityViolationException ex) {
                if (attempt == 2) {
                    log.warn("Ask AI standalone audit event {} failed for auditId={} after retries: {}",
                            eventType, auditId, ex.getMessage());
                }
            } catch (final Exception ex) {
                log.warn("Ask AI standalone audit event {} failed for auditId={}: {}",
                        eventType, auditId, ex.getMessage());
                return;
            }
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void finalizeRecord(final AuditSession session, final FinalizeCommand command) {
        if (session == null || command == null) {
            return;
        }
        try {
            if (recordRepository.existsById(session.auditId())) {
                return;
            }
            final AiAskAuditRecord record = AiAskAuditRecord.builder()
                    .auditId(session.auditId())
                    .requestId(session.requestId())
                    .sessionId(session.sessionId())
                    .clientRequestId(session.clientRequestId())
                    .patientId(session.patientId())
                    .callerUserId(session.callerUserId())
                    .callerRole(nullToEmpty(session.callerRole()))
                    .inputModality(session.inputModality())
                    .locale(session.locale())
                    .queryTextHash(session.queryTextHash())
                    .queryLength(session.queryLength())
                    .deliveryStatus(command.deliveryStatus())
                    .tier(command.tier())
                    .held(command.held())
                    .heldItemId(command.heldItemId())
                    .errorCode(command.errorCode())
                    .answerTextHash(command.answerText() == null
                            ? null
                            : hashText(command.answerText(), session.patientId()))
                    .answerLength(command.answerText() == null ? null : command.answerText().length())
                    .citationsJson(writeJson(auditSafeCitations(command.citations(), session.patientId())))
                    .escalationJson(writeJson(command.escalation() == null ? Map.of() : command.escalation()))
                    .triggerCodesJson(writeJson(
                            command.triggerCodes() == null ? List.of() : command.triggerCodes()))
                    .validationFindingsJson(command.validationFindingsJson())
                    .retrievalMetaJson(writeJson(
                            command.retrievalMeta() == null ? Map.of() : command.retrievalMeta()))
                    .scopeJson(writeJson(command.scope() == null ? Map.of() : command.scope()))
                    .modelProvider(command.modelProvider())
                    .modelId(command.modelId())
                    .totalLatencyMs(command.totalLatencyMs())
                    .createdAt(Instant.now())
                    .build();
            recordRepository.save(record);

            final String terminalEvent = terminalEventType(command);
            appendEvent(session, terminalEvent, session.callerUserId(), Map.of(
                    "deliveryStatus", command.deliveryStatus(),
                    "tier", command.tier(),
                    "heldItemId", command.heldItemId() == null ? "" : command.heldItemId().toString(),
                    "errorCode", nullToEmpty(command.errorCode())));
        } catch (final Exception ex) {
            log.warn("Ask AI audit finalize failed for auditId={}: {}",
                    session.auditId(), ex.getMessage());
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void recordHitlDeliverySupplement(
            final UUID auditId,
            final String deliveryStatus,
            final String finalAnswer,
            final Long patientId,
            final Object citations,
            final Long reviewerUserId) {
        if (auditId == null) {
            return;
        }
        try {
            deliveryRepository.save(AiAskAuditDeliverySupplement.builder()
                    .id(UUID.randomUUID())
                    .auditId(auditId)
                    .deliveryStatus(deliveryStatus)
                    .finalAnswerHash(finalAnswer == null ? null : hashText(finalAnswer, patientId))
                    .citationsJson(writeJson(auditSafeCitations(citations, patientId)))
                    .reviewerUserId(reviewerUserId)
                    .reviewedAt(Instant.now())
                    .createdAt(Instant.now())
                    .build());
        } catch (final Exception ex) {
            log.warn("Ask AI delivery supplement failed for auditId={}: {}",
                    auditId, ex.getMessage());
        }
    }

    private void persistEvent(
            final UUID auditId,
            final int sequence,
            final String eventType,
            final Long actorUserId,
            final Map<String, ?> payload) {
        eventRepository.save(AiAskAuditEvent.builder()
                .id(UUID.randomUUID())
                .auditId(auditId)
                .eventType(eventType)
                .eventSequence(sequence)
                .actorUserId(actorUserId)
                .payloadJson(writeJson(payload == null ? Map.of() : payload))
                .createdAt(Instant.now())
                .build());
    }

    private String writeJson(final Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (final JsonProcessingException ex) {
            return "{}";
        }
    }

    public record AuditSession(
            UUID auditId,
            UUID requestId,
            UUID sessionId,
            Long patientId,
            Long callerUserId,
            String callerRole,
            String inputModality,
            String locale,
            String queryTextHash,
            int queryLength,
            String clientRequestId,
            AtomicInteger sequence) {
    }

    public record StartRequestCommand(
            UUID auditId,
            UUID requestId,
            UUID sessionId,
            Long patientId,
            Long callerUserId,
            String callerRole,
            String inputModality,
            String locale,
            String queryText,
            String clientRequestId) {
    }

    public record FinalizeCommand(
            String deliveryStatus,
            int tier,
            boolean held,
            UUID heldItemId,
            String errorCode,
            String answerText,
            Object citations,
            Object escalation,
            List<String> triggerCodes,
            String validationFindingsJson,
            Map<String, Object> retrievalMeta,
            Map<String, Object> scope,
            String modelProvider,
            String modelId,
            Integer totalLatencyMs) {

        public static FinalizeCommand delivered(
                final String answerText,
                final Object citations,
                final Object escalation,
                final List<String> triggerCodes,
                final Map<String, Object> retrievalMeta,
                final Map<String, Object> scope,
                final String modelId,
                final int totalLatencyMs) {
            return new FinalizeCommand(
                    "DELIVERED",
                    1,
                    false,
                    null,
                    null,
                    answerText,
                    citations,
                    escalation,
                    triggerCodes,
                    null,
                    retrievalMeta,
                    scope,
                    "bedrock",
                    modelId,
                    totalLatencyMs);
        }

        public static FinalizeCommand held(
                final UUID heldItemId,
                final String draftAnswer,
                final Object citations,
                final List<String> triggerCodes,
                final String validationFindingsJson,
                final Map<String, Object> retrievalMeta,
                final Map<String, Object> scope,
                final String modelId,
                final int totalLatencyMs) {
            return new FinalizeCommand(
                    "HELD",
                    2,
                    true,
                    heldItemId,
                    null,
                    draftAnswer,
                    citations,
                    Map.of("level", 2, "reason", "hitl_hold"),
                    triggerCodes,
                    validationFindingsJson,
                    retrievalMeta,
                    scope,
                    "bedrock",
                    modelId,
                    totalLatencyMs);
        }

        public static FinalizeCommand noRecords(
                final Map<String, Object> retrievalMeta,
                final Map<String, Object> scope,
                final int totalLatencyMs) {
            return new FinalizeCommand(
                    "NO_RECORDS",
                    1,
                    false,
                    null,
                    null,
                    null,
                    List.of(),
                    Map.of(),
                    List.of(),
                    null,
                    retrievalMeta,
                    scope,
                    null,
                    null,
                    totalLatencyMs);
        }

        public static FinalizeCommand error(
                final String errorCode,
                final Map<String, Object> scope,
                final int totalLatencyMs) {
            return new FinalizeCommand(
                    "WITHHELD",
                    0,
                    false,
                    null,
                    errorCode,
                    null,
                    List.of(),
                    Map.of(),
                    List.of(),
                    null,
                    Map.of(),
                    scope == null ? Map.of() : scope,
                    null,
                    null,
                    totalLatencyMs);
        }
    }
}
