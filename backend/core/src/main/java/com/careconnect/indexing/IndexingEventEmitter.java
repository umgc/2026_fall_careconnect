package com.careconnect.indexing;

import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
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
 * back together with the source-record persistence (transcript
 * segments, summary rows). This service does not open its own
 * transaction; it participates in whatever transaction the caller
 * has open.
 *
 * <h2>Envelope shape</h2>
 * <pre>
 * {
 *   "eventType": "TRANSCRIPT_INDEXED" | "SUMMARY_CREATED" | ...,
 *   "eventId": "uuid",
 *   "occurredAt": "2026-07-03T22:57:00Z",
 *   "schemaVersion": 1,
 *   "payload": { ... event-specific body from the caller ... }
 * }
 * </pre>
 * The {@code eventId} is generated fresh per emit; consumers use it
 * for idempotent de-duplication.
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
     * segment batch is persisted. Called from within the caller's
     * transaction so the emit and the segment inserts commit together.
     *
     * @param payload TRANSCRIPT_INDEXED payload body (WBS 3.11.1)
     * @return the persisted outbox row (mostly useful for tests /
     *         logging)
     */
    public IndexingOutboxRow emitTranscriptIndexed(final TranscriptIndexedPayload payload) {
        return emit("TRANSCRIPT_INDEXED", payload);
    }

    /**
     * General-purpose emit hook. Package-private so type-specific
     * public wrappers (like {@link #emitTranscriptIndexed}) enforce
     * the correct payload type at compile time. SUMMARY_CREATED will
     * add its own public wrapper when 3.11.5 lands.
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
                LocalDateTime.now(ZoneOffset.UTC)
                        .format(DateTimeFormatter.ISO_OFFSET_DATE_TIME
                                .withZone(ZoneOffset.UTC)));
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