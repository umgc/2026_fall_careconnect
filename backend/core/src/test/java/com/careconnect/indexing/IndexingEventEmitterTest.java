package com.careconnect.indexing;

import com.careconnect.model.indexing.IndexingOutboxRow;
import com.careconnect.repository.indexing.IndexingOutboxRepository;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for {@link IndexingEventEmitter}. All external
 * collaborators are mocked; verifies envelope shape, correlation
 * fields, and the outbox row that gets written.
 */
class IndexingEventEmitterTest {

    private IndexingOutboxRepository outboxRepository;
    private ObjectMapper objectMapper;
    private IndexingEventEmitter emitter;

    @BeforeEach
    void setUp() {
        outboxRepository = mock(IndexingOutboxRepository.class);
        objectMapper = new ObjectMapper();
        // Repo returns whatever it is asked to save so tests can
        // inspect the row that would be persisted.
        when(outboxRepository.save(any(IndexingOutboxRow.class)))
                .thenAnswer(inv -> inv.getArgument(0));
        emitter = new IndexingEventEmitter(outboxRepository, objectMapper);
    }

    @Test
    void emitTranscriptIndexed_writesRowWithCorrectEventType() {
        final TranscriptIndexedPayload payload = new TranscriptIndexedPayload(
                "call-42", 100L, 87, "POST_CALL_TRANSCRIBE");

        emitter.emitTranscriptIndexed(payload);

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());
        assertThat(captor.getValue().getEventType()).isEqualTo("TRANSCRIPT_INDEXED");
    }

    @Test
    void emitTranscriptIndexed_envelope_hasAllRequiredFields() throws Exception {
        final TranscriptIndexedPayload payload = new TranscriptIndexedPayload(
                "call-42", 100L, 87, "POST_CALL_TRANSCRIBE");

        emitter.emitTranscriptIndexed(payload);

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());

        final JsonNode envelope = objectMapper.readTree(captor.getValue().getPayloadJson());
        assertThat(envelope.get("eventType").asText()).isEqualTo("TRANSCRIPT_INDEXED");
        assertThat(envelope.get("eventId").asText()).isNotBlank();
        assertThat(envelope.get("occurredAt").asText()).isNotBlank();
        assertThat(envelope.get("schemaVersion").asInt()).isEqualTo(1);
        assertThat(envelope.get("payload")).isNotNull();
    }

    @Test
    void emitTranscriptIndexed_payload_carriesAllPassedFields() throws Exception {
        final TranscriptIndexedPayload payload = new TranscriptIndexedPayload(
                "call-42", 100L, 87, "POST_CALL_TRANSCRIBE");

        emitter.emitTranscriptIndexed(payload);

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());

        final JsonNode payloadNode = objectMapper.readTree(captor.getValue().getPayloadJson())
                .get("payload");
        assertThat(payloadNode.get("callId").asText()).isEqualTo("call-42");
        assertThat(payloadNode.get("patientId").asLong()).isEqualTo(100L);
        assertThat(payloadNode.get("segmentCount").asInt()).isEqualTo(87);
        assertThat(payloadNode.get("source").asText()).isEqualTo("POST_CALL_TRANSCRIBE");
    }

    @Test
    void emitTranscriptIndexed_tolerates_nullPatientId() throws Exception {
        // patient_id may be null until Ravi's telemetry-JOIN lands or
        // callers wire it explicitly.
        final TranscriptIndexedPayload payload = new TranscriptIndexedPayload(
                "call-42", null, 87, "POST_CALL_TRANSCRIBE");

        emitter.emitTranscriptIndexed(payload);

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository).save(captor.capture());

        final JsonNode payloadNode = objectMapper.readTree(captor.getValue().getPayloadJson())
                .get("payload");
        assertThat(payloadNode.get("patientId").isNull()).isTrue();
    }

    @Test
    void twoConsecutiveEmits_haveDistinctEventIds() throws Exception {
        final TranscriptIndexedPayload payload = new TranscriptIndexedPayload(
                "call-42", 100L, 87, "POST_CALL_TRANSCRIBE");

        emitter.emitTranscriptIndexed(payload);
        emitter.emitTranscriptIndexed(payload);

        final ArgumentCaptor<IndexingOutboxRow> captor =
                ArgumentCaptor.forClass(IndexingOutboxRow.class);
        verify(outboxRepository, org.mockito.Mockito.times(2)).save(captor.capture());

        final String firstEventId = objectMapper.readTree(captor.getAllValues().get(0).getPayloadJson())
                .get("eventId").asText();
        final String secondEventId = objectMapper.readTree(captor.getAllValues().get(1).getPayloadJson())
                .get("eventId").asText();
        assertThat(firstEventId).isNotEqualTo(secondEventId);
    }
}