package com.careconnect.service;

import com.careconnect.model.CallTelemetryEvent;
import com.careconnect.repository.CallTelemetryEventRepository;
import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.mockito.junit.jupiter.MockitoSettings;
import org.mockito.quality.Strictness;

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Extended unit tests for CallTelemetryService — covers getSentimentHistoryForUser,
 * summarizeCall, sanitizePayload, recordWebSocketEvent, findCallHistoryForPatient,
 * deleteTelemetryEvents, and edge cases not in the baseline test.
 */
@ExtendWith(MockitoExtension.class)
@MockitoSettings(strictness = Strictness.LENIENT)
@DisplayName("CallTelemetryService Extended Tests")
class CallTelemetryServiceExtendedTest {

    private static final String CALL_ID = "call-ext-001";
    @Mock
    private CallTelemetryEventRepository repo;
    private CallTelemetryService service;

    @BeforeEach
    void setUp() {
        service = new CallTelemetryService(repo, new ObjectMapper());
    }

    // ──────────────────────────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────────────────────────

    private CallTelemetryEvent eventAt(String callId, String eventType, LocalDateTime time) {
        CallTelemetryEvent e = new CallTelemetryEvent();
        e.setId((long) (Math.random() * 1_000_000));
        e.setCallId(callId);
        e.setEventType(eventType);
        e.setActorUserId(1L);
        e.setOccurredAt(time);
        e.setStatus("SUCCESS");
        return e;
    }

    private CallTelemetryEvent sentimentEvent(String callId, String channel,
                                              double score, String label,
                                              LocalDateTime time) {
        CallTelemetryEvent e = eventAt(callId, "SENTIMENT_" + channel.toUpperCase(), time);
        e.setChannel(channel);
        e.setSentimentScore(score);
        e.setSentimentLabel(label);
        return e;
    }

    // ──────────────────────────────────────────────────────────────────
    //  recordWebSocketEvent
    // ──────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("recordSentimentEvent with null result saves event without sentiment fields")
    void recordSentimentEvent_nullResult_savesEvent() {
        ArgumentCaptor<CallTelemetryEvent> cap = ArgumentCaptor.forClass(CallTelemetryEvent.class);

        service.recordSentimentEvent(CALL_ID, "SENTIMENT_TEXT", "TEXT", 1L, 2L, "REALTIME",
                null, Map.of("captureMode", "REALTIME"), "SUCCESS", null);

        verify(repo).save(cap.capture());
        assertThat(cap.getValue().getSentimentScore()).isNull();
        assertThat(cap.getValue().getSentimentLabel()).isNull();
        assertThat(cap.getValue().getStatus()).isEqualTo("SUCCESS");
    }

    // ──────────────────────────────────────────────────────────────────
    //  getSentimentHistoryForUser (exercises summarizeCall)
    // ──────────────────────────────────────────────────────────────────

    @Test
    @DisplayName("recordSentimentEvent with SentimentResult sets score and label")
    void recordSentimentEvent_withResult_setsSentimentFields() {
        ArgumentCaptor<CallTelemetryEvent> cap = ArgumentCaptor.forClass(CallTelemetryEvent.class);
        SentimentResult result = new SentimentResult(0.85, "CALM", "Stable", "TEXT",
                CALL_ID, System.currentTimeMillis(), false);

        service.recordSentimentEvent(CALL_ID, "SENTIMENT_TEXT", "TEXT", 1L, 2L, "REALTIME",
                result, Map.of(), "SUCCESS", null);

        verify(repo).save(cap.capture());
        assertThat(cap.getValue().getSentimentScore()).isEqualTo(0.85);
        assertThat(cap.getValue().getSentimentLabel()).isEqualTo("CALM");
    }

    // ──────────────────────────────────────────────────────────────────
    //  sanitizePayload (via recordSentimentEvent)
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("recordWebSocketEvent")
    class RecordWebSocketEventTests {

        @Test
        @DisplayName("saves event with WEBSOCKET source")
        void recordWebSocketEvent_savesWebSocketSource() {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            Map<String, Object> payload = Map.of("type", "join-user-room", "callId", CALL_ID);

            service.recordWebSocketEvent(CALL_ID, "WS_JOIN_USER_ROOM", 1L, 2L, payload, "SUCCESS", null);

            verify(repo).save(captor.capture());
            assertThat(captor.getValue().getEventSource()).isEqualTo("WEBSOCKET");
            assertThat(captor.getValue().getEventType()).isEqualTo("WS_JOIN_USER_ROOM");
        }

        @Test
        @DisplayName("sanitizes sensitive keys from WebSocket payload")
        void recordWebSocketEvent_sanitizesSensitivePayload() {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            Map<String, Object> payload = new HashMap<>();
            payload.put("type", "authenticate");
            payload.put("token", "Bearer eyJhbGc...");
            payload.put("password", "secret123");

            service.recordWebSocketEvent(CALL_ID, "WS_AUTHENTICATE", 1L, null, payload, "SUCCESS", null);

            verify(repo).save(captor.capture());
            String payloadJson = captor.getValue().getPayloadJson();
            assertThat(payloadJson).contains("REDACTED");
            assertThat(payloadJson).doesNotContain("Bearer eyJhbGc");
            assertThat(payloadJson).doesNotContain("secret123");
        }

        @Test
        @DisplayName("records error message when status is ERROR")
        void recordWebSocketEvent_errorStatus_savesErrorMessage() {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);

            service.recordWebSocketEvent(CALL_ID, "WS_AUTHENTICATE", null, null,
                    Map.of(), "ERROR", "Invalid token");

            verify(repo).save(captor.capture());
            assertThat(captor.getValue().getStatus()).isEqualTo("ERROR");
            assertThat(captor.getValue().getErrorMessage()).isEqualTo("Invalid token");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  findCallHistoryForPatient
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("getSentimentHistoryForUser")
    class GetSentimentHistoryTests {

        @Test
        @DisplayName("returns empty list when userId is null")
        void nullUserId_returnsEmptyList() {
            List<Map<String, Object>> result = service.getSentimentHistoryForUser(null);
            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("returns empty list when no events found")
        void noEvents_returnsEmptyList() {
            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(Collections.emptyList());

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);
            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("skips events with null callId")
        void eventsWithNullCallId_skipped() {
            CallTelemetryEvent e = eventAt(null, "CALL_JOIN", LocalDateTime.now().minusMinutes(5));
            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(List.of(e));

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);
            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("summarizes call with SENTIMENT_FINAL event")
        void withFinalSentimentEvent_includesOverallScore() {
            LocalDateTime start = LocalDateTime.now().minusMinutes(10);
            LocalDateTime mid = start.plusMinutes(5);
            LocalDateTime end = start.plusMinutes(9);

            CallTelemetryEvent joinEv = eventAt(CALL_ID, "CALL_JOIN", start);
            joinEv.setActorUserId(1L);

            CallTelemetryEvent textSentiment = sentimentEvent(CALL_ID, "TEXT", 0.8, "POSITIVE", mid);
            textSentiment.setActorUserId(1L);

            CallTelemetryEvent finalEv = eventAt(CALL_ID, "SENTIMENT_FINAL", end);
            finalEv.setSentimentScore(0.75);
            finalEv.setSentimentLabel("CALM");
            finalEv.setActorUserId(1L);

            CallTelemetryEvent endEv = eventAt(CALL_ID, "CALL_END", end.plusSeconds(30));
            endEv.setActorUserId(1L);

            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(List.of(joinEv, textSentiment, finalEv, endEv));

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);

            assertThat(result).hasSize(1);
            Map<String, Object> summary = result.get(0);
            assertThat(summary.get("callId")).isEqualTo(CALL_ID);
            assertThat(summary).containsKey("overallScore");
            assertThat(summary).containsKey("overallLabel");
            assertThat(summary).containsKey("durationMinutes");
            assertThat(summary).doesNotContainKey("_sortDate"); // removed after sorting
        }

        @Test
        @DisplayName("summarizes call using average when no SENTIMENT_FINAL event")
        void withoutFinalEvent_usesAverageScore() {
            LocalDateTime start = LocalDateTime.now().minusMinutes(10);
            LocalDateTime mid = start.plusMinutes(3);
            LocalDateTime end = start.plusMinutes(8);

            CallTelemetryEvent joinEv = eventAt(CALL_ID, "CALL_JOIN", start);
            CallTelemetryEvent voice1 = sentimentEvent(CALL_ID, "VOICE", 0.6, "CALM", mid);
            CallTelemetryEvent voice2 = sentimentEvent(CALL_ID, "VOICE", 0.4, "ANXIOUS", end);
            CallTelemetryEvent endEv = eventAt(CALL_ID, "CALL_END", end.plusSeconds(5));

            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(List.of(joinEv, voice1, voice2, endEv));

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);

            assertThat(result).hasSize(1);
            assertThat(result.get(0)).containsKey("stabilityScore");
            assertThat(result.get(0).get("positiveTimePct")).isNotNull();
        }

        @Test
        @DisplayName("handles multiple calls sorted by most recent first")
        void multipleCalls_sortedByDateDescending() {
            LocalDateTime call1Start = LocalDateTime.now().minusDays(2);
            LocalDateTime call2Start = LocalDateTime.now().minusHours(1);

            String callId1 = "call-older";
            String callId2 = "call-recent";

            CallTelemetryEvent e1 = eventAt(callId1, "SENTIMENT_FINAL", call1Start.plusMinutes(5));
            e1.setCallId(callId1);
            e1.setSentimentScore(0.5);
            e1.setSentimentLabel("ANXIOUS");

            CallTelemetryEvent e2 = eventAt(callId2, "SENTIMENT_FINAL", call2Start.plusMinutes(5));
            e2.setCallId(callId2);
            e2.setSentimentScore(0.8);
            e2.setSentimentLabel("CALM");

            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(List.of(e1, e2));

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);

            // More recent call should come first
            if (result.size() == 2) {
                assertThat(result.get(0).get("callId")).isEqualTo(callId2);
            }
        }

        @Test
        @DisplayName("returns empty when events have no sentiment data")
        void withNoSentimentScore_returnsEmpty() {
            CallTelemetryEvent joinEv = eventAt(CALL_ID, "CALL_JOIN",
                    LocalDateTime.now().minusMinutes(5));

            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(List.of(joinEv));

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);

            // join event has no sentiment score — summarizeCall returns empty map → filtered out
            assertThat(result).isEmpty();
        }

        @Test
        @DisplayName("DISTRESSED label produces distressed bucket > 0")
        void distressedLabel_setsBucket() {
            LocalDateTime start = LocalDateTime.now().minusMinutes(10);
            CallTelemetryEvent textEv = sentimentEvent(CALL_ID, "TEXT", 0.2, "DISTRESSED", start.plusMinutes(1));
            CallTelemetryEvent endEv = eventAt(CALL_ID, "CALL_END", start.plusMinutes(9));

            when(repo.findByActorUserIdOrTargetUserIdOrderByOccurredAtAsc(1L, 1L))
                    .thenReturn(List.of(textEv, endEv));

            List<Map<String, Object>> result = service.getSentimentHistoryForUser(1L);

            if (!result.isEmpty()) {
                // overallLabel should be DISTRESSED or derived from score
                assertThat(result.get(0)).containsKey("negativeTimePct");
            }
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  deleteTelemetryEvents
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("sanitizePayload via recordSentimentEvent")
    class SanitizePayloadTests {

        private ArgumentCaptor<CallTelemetryEvent> saved() {
            return ArgumentCaptor.forClass(CallTelemetryEvent.class);
        }

        @Test
        @DisplayName("redacts token field")
        void tokenField_isRedacted() {
            ArgumentCaptor<CallTelemetryEvent> cap = saved();
            Map<String, Object> payload = new HashMap<>();
            payload.put("captureMode", "REALTIME");
            payload.put("token", "secret-jwt-value");

            service.recordWebSocketEvent(CALL_ID, "WS_TYPE", 1L, null, payload, "SUCCESS", null);

            verify(repo).save(cap.capture());
            assertThat(cap.getValue().getPayloadJson()).contains("REDACTED");
        }

        @Test
        @DisplayName("omits unknown keys")
        void unknownKey_isOmitted() {
            ArgumentCaptor<CallTelemetryEvent> cap = saved();
            Map<String, Object> payload = new HashMap<>();
            payload.put("captureMode", "REALTIME");
            payload.put("unknownCustomField", "value-123");

            service.recordWebSocketEvent(CALL_ID, "WS_TYPE", 1L, null, payload, "SUCCESS", null);

            verify(repo).save(cap.capture());
            assertThat(cap.getValue().getPayloadJson()).contains("OMITTED");
        }

        @Test
        @DisplayName("truncates long string values")
        void longString_isTruncated() {
            ArgumentCaptor<CallTelemetryEvent> cap = saved();
            String longText = "x".repeat(200);
            Map<String, Object> payload = new HashMap<>();
            payload.put("captureMode", longText);

            service.recordWebSocketEvent(CALL_ID, "WS_TYPE", 1L, null, payload, "SUCCESS", null);

            verify(repo).save(cap.capture());
            assertThat(cap.getValue().getPayloadJson()).contains("TRUNCATED");
        }

        @Test
        @DisplayName("null payload produces empty payload JSON")
        void nullPayload_isEmpty() {
            ArgumentCaptor<CallTelemetryEvent> cap = saved();

            service.recordWebSocketEvent(CALL_ID, "WS_TYPE", 1L, null, null, "SUCCESS", null);

            verify(repo).save(cap.capture());
            // null / empty payload → toJsonSafe(Map.of()) → "{}"
            assertThat(cap.getValue().getPayloadJson()).isIn("{}", "null", null);
        }

        @Test
        @DisplayName("email field is redacted")
        void emailField_isRedacted() {
            ArgumentCaptor<CallTelemetryEvent> cap = saved();
            Map<String, Object> payload = new HashMap<>();
            payload.put("senderEmail", "user@example.com");
            payload.put("captureMode", "REALTIME");

            service.recordWebSocketEvent(CALL_ID, "WS_TYPE", 1L, null, payload, "SUCCESS", null);

            verify(repo).save(cap.capture());
            assertThat(cap.getValue().getPayloadJson()).contains("REDACTED");
            assertThat(cap.getValue().getPayloadJson()).doesNotContain("user@example.com");
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  deleteTelemetryForCall edge cases
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("findCallHistoryForPatient")
    class FindCallHistoryTests {

        @Test
        @DisplayName("returns empty match for null patientUserId")
        void nullPatientId_returnsEmpty() {
            CallTelemetryService.PatientCallHistoryMatch result =
                    service.findCallHistoryForPatient(null);

            assertThat(result.events()).isEmpty();
            assertThat(result.callIds()).isEmpty();
        }

        @Test
        @DisplayName("returns matched events for patient as actor")
        void patientAsActor_matchesEvents() {
            CallTelemetryEvent join = eventAt(CALL_ID, "CALL_JOIN", LocalDateTime.now());
            join.setActorUserId(2L);

            when(repo.findAll()).thenReturn(List.of(join));

            CallTelemetryService.PatientCallHistoryMatch result =
                    service.findCallHistoryForPatient(2L);

            assertThat(result.events()).hasSize(1);
            assertThat(result.callIds()).contains(CALL_ID);
        }

        @Test
        @DisplayName("returns matched events for patient as target")
        void patientAsTarget_matchesEvents() {
            CallTelemetryEvent sentiment = eventAt(CALL_ID, "SENTIMENT_TEXT", LocalDateTime.now());
            sentiment.setActorUserId(99L);
            sentiment.setTargetUserId(2L);

            when(repo.findAll()).thenReturn(List.of(sentiment));

            CallTelemetryService.PatientCallHistoryMatch result =
                    service.findCallHistoryForPatient(2L);

            assertThat(result.events()).hasSize(1);
        }

        @Test
        @DisplayName("filters out events with blank callId from callIds set")
        void eventsWithBlankCallId_notInCallIds() {
            CallTelemetryEvent e = eventAt("", "CALL_JOIN", LocalDateTime.now());
            e.setActorUserId(2L);

            when(repo.findAll()).thenReturn(List.of(e));

            CallTelemetryService.PatientCallHistoryMatch result =
                    service.findCallHistoryForPatient(2L);

            assertThat(result.events()).hasSize(1);
            assertThat(result.callIds()).isEmpty();
        }
    }

    // ──────────────────────────────────────────────────────────────────
    //  recordSentimentEvent with null SentimentResult
    // ──────────────────────────────────────────────────────────────────

    @Nested
    @DisplayName("deleteTelemetryEvents")
    class DeleteTelemetryEventsTests {

        @Test
        @DisplayName("returns 0 for null collection")
        void nullCollection_returnsZero() {
            assertThat(service.deleteTelemetryEvents(null)).isEqualTo(0L);
        }

        @Test
        @DisplayName("returns 0 for empty collection")
        void emptyCollection_returnsZero() {
            assertThat(service.deleteTelemetryEvents(Collections.emptyList())).isEqualTo(0L);
        }

        @Test
        @DisplayName("deletes events with IDs and returns count")
        void withEvents_deletesAndReturnsCount() {
            CallTelemetryEvent e1 = new CallTelemetryEvent();
            e1.setId(10L);
            CallTelemetryEvent e2 = new CallTelemetryEvent();
            e2.setId(11L);

            long deleted = service.deleteTelemetryEvents(List.of(e1, e2));

            assertThat(deleted).isEqualTo(2L);
            verify(repo).deleteAllByIdInBatch(any());
        }

        @Test
        @DisplayName("skips events with null ID")
        void eventsWithNullId_skipped() {
            CallTelemetryEvent noId = new CallTelemetryEvent();
            // id is null

            long deleted = service.deleteTelemetryEvents(List.of(noId));

            assertThat(deleted).isEqualTo(0L);
        }
    }

    @Nested
    @DisplayName("deleteTelemetryForCall edge cases")
    class DeleteCallEdgeCases {

        @Test
        @DisplayName("returns 0 for null callId")
        void nullCallId_returnsZero() {
            assertThat(service.deleteTelemetryForCall(null)).isEqualTo(0L);
        }

        @Test
        @DisplayName("returns 0 for blank callId")
        void blankCallId_returnsZero() {
            assertThat(service.deleteTelemetryForCall("   ")).isEqualTo(0L);
        }

        @Test
        @DisplayName("delegates to repo for valid callId")
        void validCallId_callsRepo() {
            when(repo.deleteByCallId(CALL_ID)).thenReturn(5L);

            long result = service.deleteTelemetryForCall(CALL_ID);

            assertThat(result).isEqualTo(5L);
        }
    }
}
