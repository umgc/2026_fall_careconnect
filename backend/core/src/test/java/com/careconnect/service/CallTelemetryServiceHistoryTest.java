package com.careconnect.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.repository.CallTelemetryEventRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;

/**
 * Covers patient call-history matching from telemetry metadata, payload sanitization edge keys,
 * serialization failure fallback and the missing-repository guard of {@link CallTelemetryService}.
 */
@DisplayName("CallTelemetryService history and sanitization")
class CallTelemetryServiceHistoryTest {

    private static CallTelemetryEvent event(final String callId, final Long actor, final String metadata) {
        final CallTelemetryEvent event = new CallTelemetryEvent();
        event.setCallId(callId);
        event.setActorUserId(actor);
        event.setMetadataJson(metadata);
        return event;
    }

    @Test
    @DisplayName("patient history matches actor, context id lists and single context ids")
    void findCallHistoryForPatient_matchesMetadata() {
        final CallTelemetryEventRepository repo = mock(CallTelemetryEventRepository.class);
        final CallTelemetryService service = new CallTelemetryService(repo, new ObjectMapper());
        when(repo.findAll())
                .thenReturn(
                        List.of(
                                event("c1", 7L, null),
                                event("c2", 2L, "{\"contextPatientUserIds\":[3,\"7\"],\"\":1}"),
                                event("c3", 2L, "{\"contextPatientUserId\":\"7\"}"),
                                event("c4", 2L, "{\"contextPatientUserId\":\"abc\"}"),
                                event("c5", 2L, "not json"),
                                event("c6", 2L, "[1,2]"),
                                event(" ", 7L, null)));

        final CallTelemetryService.PatientCallHistoryMatch match = service.findCallHistoryForPatient(7L);

        assertThat(match.callIds()).containsExactlyInAnyOrder("c1", "c2", "c3");
        assertThat(match.events()).hasSize(4);
    }

    @Test
    @DisplayName("payload sanitization skips blank keys and keeps null sensitive values")
    void recordCallEvent_sanitizesEdgeKeys() {
        final CallTelemetryEventRepository repo = mock(CallTelemetryEventRepository.class);
        final CallTelemetryService service = new CallTelemetryService(repo, new ObjectMapper());
        final Map<String, String> payload = new HashMap<>();
        payload.put(" ", "x");
        payload.put("userName", null);

        service.recordSentimentEvent("c1", "SENTIMENT_TEXT", "TEXT", 1L, null, "LIVE", null,
                new HashMap<>(payload), "SUCCESS", null);

        final ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
        verify(repo).save(captor.capture());
        assertThat(captor.getValue().getPayloadJson()).contains("\"userName\":null").doesNotContain("\" \"");
    }

    @Test
    @DisplayName("serialization failures fall back to an empty JSON object; a missing repository skips saving")
    void serializationFailureAndMissingRepository() throws Exception {
        final ObjectMapper failing = mock(ObjectMapper.class);
        when(failing.writeValueAsString(any())).thenThrow(new JsonProcessingException("boom") { });
        final CallTelemetryEventRepository repo = mock(CallTelemetryEventRepository.class);

        new CallTelemetryService(repo, failing)
                .recordCallEvent("c1", "CALL_JOIN", 1L, null, "SUCCESS", Map.of("a", 1), null);
        final ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
        verify(repo).save(captor.capture());
        assertThat(captor.getValue().getMetadataJson()).isEqualTo("{}");

        new CallTelemetryService(null, new ObjectMapper())
                .recordCallEvent("c1", "CALL_JOIN", 1L, null, null, null, null);
    }

    @Test
    @DisplayName("sentiment history summarizes calls with distressed labels and ignores undated events")
    void sentimentHistory_distressedAndUndated() {
        final CallTelemetryEventRepository repo = mock(CallTelemetryEventRepository.class);
        final CallTelemetryService service = new CallTelemetryService(repo, new ObjectMapper());
        final LocalDateTime start = LocalDateTime.of(2026, 10, 1, 10, 0);
        final CallTelemetryEvent undated = event("u1", 1L, null);
        undated.setEventType("CALL_JOIN");
        final CallTelemetryEvent join = event("c1", 1L, null);
        join.setEventType("CALL_JOIN");
        join.setOccurredAt(start);
        final CallTelemetryEvent combined = event("c1", 1L, null);
        combined.setEventType("SENTIMENT_COMBINED");
        combined.setChannel("COMBINED");
        combined.setSentimentScore(0.1);
        combined.setSentimentLabel("NEGATIVE");
        combined.setOccurredAt(start.plusSeconds(5));
        final CallTelemetryEvent finalEvent = event("c1", 1L, null);
        finalEvent.setEventType("SENTIMENT_FINAL");
        finalEvent.setChannel("TEXT");
        finalEvent.setSentimentScore(0.1);
        finalEvent.setSentimentLabel("DISTRESSED");
        finalEvent.setOccurredAt(start.plusSeconds(60));
        when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                .thenReturn(List.of(undated, join, combined, finalEvent));

        final List<Map<String, Object>> history = service.getSentimentHistoryForUser(1L);

        assertThat(history).hasSize(1);
        assertThat(history.get(0)).containsEntry("overallLabel", "DISTRESSED").containsEntry("negativeTimePct", 1.0);
    }
}
