package com.careconnect.indexing;

import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Serializes indexing events into the standard envelope defined by
 * Ravichandra Vasireddy's 2026-07-03 Transcript Ingest and
 * SUMMARY_CREATED Indexing Contract, and writes them to the
 * {@code indexing_outbox} table.
 *
 * <h2>Transactional contract</h2>
 * <p>Emitters MUST call this service from inside their own
 * {@code @Transactional} method so the outbox row commits or rolls
 * back together with the source-record persistence. This service does
 * not open its own transaction.
 *
 * <h2>Envelope shape</h2>
 * <pre>
 * {
 *   "eventType": "TRANSCRIPT_INDEXED" | "SUMMARY_CREATED" | ...,
 *   "eventId": "uuid",
 *   "occurredAt": "2026-07-04T02:57:00Z",
 *   "schemaVersion": 1,
 *   "payload": { ... event-specific body from the caller ... }
 * }
 * </pre>
 */
@Service
public class IndexingEventEmitter {

    private static final Logger log = LoggerFactory.getLogger(IndexingEventEmitter.class);

    /** Schema version for the outer envelope. Bump when the shape breaks. */
    static final int SCHEMA_VERSION = 1;

    private final IndexingOutboxRepository outboxRepository;
    private final ObjectMapper objectMapper;

    public IndexingEventEmitter(
            final IndexingOutboxRepository outboxRepository,
            final ObjectMapper objectMapper) {
        this.outboxRepository = outboxRepository;
        this.objectMapper = objectMapper;
    }

    /**
     * Emit a {@code TRANSCRIPT_INDEXED} event after a transcript
     * segment batch is persisted (WBS 3.11.1).
     *
     * @param payload TRANSCRIPT_INDEXED payload body
     * @return the persisted outbox row
     */
    public IndexingOutboxRow emitTranscriptIndexed(final TranscriptIndexedPayload payload) {
        return emit("TRANSCRIPT_INDEXED", payload);
    }

    /**
     * Emit a {@code SUMMARY_CREATED} event after a call or visit
     * summary is persisted with {@code status == SUCCESS} (WBS 3.11.5).
     * Callers guard on status before invoking; per Ravi's contract
     * NO_TRANSCRIPT and ERROR summaries are not indexed.
     *
     * @param payload SUMMARY_CREATED payload body
     * @return the persisted outbox row
     */
    public IndexingOutboxRow emitSummaryCreated(final SummaryCreatedPayload payload) {
        return emit("SUMMARY_CREATED", payload);
    }

    /**
     * General-purpose emit hook. Package-private so type-specific
     * public wrappers enforce the correct payload type at compile time.
     *
     * @param eventType event type discriminator string
     * @param payload   event-specific payload; serialized with the
     *                  default ObjectMapper
     * @return the persisted outbox row
     */
    IndexingOutboxRow emit(final String eventType, final Object payload) {
        final String envelopeJson = serializeEnvelope(eventType, payload);
        final IndexingOutboxRow row = IndexingOutboxRow.builder()
                .eventType(eventType)
                .payloadJson(envelopeJson)
                .createdAt(LocalDateTime.now())
                .attemptCount(0)
                .build();
        final IndexingOutboxRow saved = outboxRepository.save(row);
        log.info("indexing event queued: type={} eventId=(in payload) outboxId={}",
                eventType, saved.getId());
        return saved;
    }

    private String serializeEnvelope(final String eventType, final Object payload) {
        final Map<String, Object> envelope = new LinkedHashMap<>();
        envelope.put("eventType", eventType);
        envelope.put("eventId", UUID.randomUUID().toString());
        envelope.put("occurredAt",
                OffsetDateTime.now(ZoneOffset.UTC)
                        .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME));
        envelope.put("schemaVersion", SCHEMA_VERSION);
        envelope.put("payload", payload);
        try {
            return objectMapper.writeValueAsString(envelope);
        } catch (final JsonProcessingException e) {
            throw new IllegalStateException(
                    "failed to serialize indexing event envelope for type " + eventType, e);
        }
    }
}