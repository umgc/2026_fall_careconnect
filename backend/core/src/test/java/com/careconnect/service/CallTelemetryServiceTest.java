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

import java.time.LocalDateTime;
import java.util.Collections;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Unit tests for CallTelemetryService.
 * <p>
 * Uses a real ObjectMapper so JSON serialization actually runs,
 * allowing us to verify sanitization behavior via the saved payloadJson.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("CallTelemetryService Tests")
class CallTelemetryServiceTest {

    private static final String CALL_ID = "call-1";
    @Mock
    private CallTelemetryEventRepository callTelemetryEventRepository;
    private CallTelemetryService callTelemetryService;

    @BeforeEach
    void setUp() {
        // Use a real ObjectMapper so toJsonSafe actually serializes
        callTelemetryService = new CallTelemetryService(callTelemetryEventRepository, new ObjectMapper());
    }

    // ────────────────────────────────────────────────────────────────────────
    // Helper: build a SentimentResult for testing
    // ────────────────────────────────────────────────────────────────────────

    private SentimentResult buildSentimentResult(double score, String label) {
        return new SentimentResult(score, label, "Test notes", "TEXT", CALL_ID, 123456L, false);
    }

    // ════════════════════════════════════════════════════════════════════════
    //  recordCallEvent tests
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("recordCallEvent Tests")
    class RecordCallEventTests {

        @Test
        @DisplayName("recordCallEvent saves a CallTelemetryEvent to the repository")
        void recordCallEvent_savesToRepository() {
            Map<String, Object> metadata = Map.of("meetingActive", true);

            callTelemetryService.recordCallEvent(
                    CALL_ID, "CALL_JOIN", 1L, null, "SUCCESS", metadata, null);

            verify(callTelemetryEventRepository).save(any(CallTelemetryEvent.class));
        }

        @Test
        @DisplayName("recordCallEvent saves event with correct callId, eventType, actorUserId, status")
        void recordCallEvent_savesCorrectFields() {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            Map<String, Object> metadata = Map.of("meetingActive", true);

            callTelemetryService.recordCallEvent(
                    CALL_ID, "CALL_JOIN", 1L, null, "SUCCESS", metadata, null);

            verify(callTelemetryEventRepository).save(captor.capture());
            CallTelemetryEvent saved = captor.getValue();

            assertThat(saved.getCallId()).isEqualTo(CALL_ID);
            assertThat(saved.getEventType()).isEqualTo("CALL_JOIN");
            assertThat(saved.getActorUserId()).isEqualTo(1L);
            assertThat(saved.getStatus()).isEqualTo("SUCCESS");
            assertThat(saved.getOccurredAt()).isNotNull();
        }

        @Test
        @DisplayName("recordCallEvent with null metadata does not throw")
        void recordCallEvent_nullMetadata_doesNotThrow() {
            assertThatCode(() ->
                    callTelemetryService.recordCallEvent(
                            CALL_ID, "CALL_JOIN", 1L, null, "SUCCESS", null, null)
            ).doesNotThrowAnyException();

            verify(callTelemetryEventRepository).save(any(CallTelemetryEvent.class));
        }

        @Test
        @DisplayName("recordCallEvent with null callId does not throw, saves with null callId")
        void recordCallEvent_nullCallId_doesNotThrow() {
            assertThatCode(() ->
                    callTelemetryService.recordCallEvent(
                            null, "CALL_JOIN", 1L, null, "SUCCESS", Map.of(), null)
            ).doesNotThrowAnyException();

            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            verify(callTelemetryEventRepository).save(captor.capture());
            // trim of null returns null
            assertThat(captor.getValue().getCallId()).isNull();
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  recordSentimentEvent tests
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("recordSentimentEvent Tests")
    class RecordSentimentEventTests {

        @Test
        @DisplayName("recordSentimentEvent saves event and sets sentimentScore from SentimentResult")
        void recordSentimentEvent_setsSentimentScore() {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            SentimentResult result = buildSentimentResult(0.75, "POSITIVE");
            Map<String, Object> payload = Map.of("captureMode", "realtime");

            callTelemetryService.recordSentimentEvent(
                    CALL_ID, "SENTIMENT_TEXT", "TEXT", 1L, null,
                    "realtime", result, payload, "SUCCESS", null);

            verify(callTelemetryEventRepository).save(captor.capture());
            CallTelemetryEvent saved = captor.getValue();

            assertThat(saved.getSentimentScore()).isEqualTo(0.75);
            assertThat(saved.getSentimentLabel()).isEqualTo("POSITIVE");
            assertThat(saved.getChannel()).isEqualTo("TEXT");
            assertThat(saved.getCaptureMode()).isEqualTo("realtime");
        }

        @Test
        @DisplayName("recordSentimentEvent with null SentimentResult does not set sentimentScore")
        void recordSentimentEvent_nullResult_doesNotSetScore() {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            Map<String, Object> payload = Map.of("captureMode", "realtime");

            callTelemetryService.recordSentimentEvent(
                    CALL_ID, "SENTIMENT_TEXT", "TEXT", 1L, null,
                    "realtime", null, payload, "ERROR", "Forbidden");

            verify(callTelemetryEventRepository).save(captor.capture());
            assertThat(captor.getValue().getSentimentScore()).isNull();
            assertThat(captor.getValue().getStatus()).isEqualTo("ERROR");
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  Sanitization tests (via payloadJson on recordSentimentEvent)
    //
    //  sanitizePayload is private; we verify indirectly by capturing the
    //  saved event's payloadJson and asserting presence/absence of keys.
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("Payload Sanitization Tests")
    class SanitizationTests {

        /**
         * Calls recordSentimentEvent with the given payload and returns the
         * payloadJson from the saved entity.
         */
        private String capturePayloadJson(Map<String, Object> payload) {
            ArgumentCaptor<CallTelemetryEvent> captor = ArgumentCaptor.forClass(CallTelemetryEvent.class);
            callTelemetryService.recordSentimentEvent(
                    CALL_ID, "SENTIMENT_TEXT", "TEXT", 1L, null,
                    null, null, payload, "SUCCESS", null);
            verify(callTelemetryEventRepository).save(captor.capture());
            return captor.getValue().getPayloadJson();
        }

        @Test
        @DisplayName("Sanitization: 'token' is redacted but 'captureMode' is preserved in payloadJson")
        void sanitize_tokenRedacted_captureModePreserved() {
            Map<String, Object> payload = Map.of(
                    "token", "abc123",
                    "captureMode", "realtime"
            );

            String json = capturePayloadJson(payload);

            assertThat(json).isNotNull();
            assertThat(json).doesNotContain("\"abc123\"");
            assertThat(json).contains("captureMode");
            assertThat(json).contains("realtime");
        }

        @Test
        @DisplayName("Sanitization: 'imageBase64' is redacted in payloadJson")
        void sanitize_imageBase64Redacted() {
            Map<String, Object> payload = Map.of(
                    "imageBase64", "verylargeimagedatahere==",
                    "imageFormat", "jpeg"
            );

            String json = capturePayloadJson(payload);

            assertThat(json).isNotNull();
            assertThat(json).doesNotContain("verylargeimagedatahere==");
            // imageBase64 key is present but value is [REDACTED:...]
            assertThat(json).contains("imageBase64");
            assertThat(json).contains("REDACTED");
        }

        @Test
        @DisplayName("Sanitization: 'text' is redacted but 'textLength' is preserved in payloadJson")
        void sanitize_textRedacted_textLengthPreserved() {
            Map<String, Object> payload = Map.of(
                    "text", "patient said something sensitive",
                    "textLength", 50
            );

            String json = capturePayloadJson(payload);

            assertThat(json).isNotNull();
            assertThat(json).doesNotContain("patient said something sensitive");
            assertThat(json).contains("textLength");
            // 50 as a number should appear in the JSON
            assertThat(json).contains("50");
        }

        @Test
        @DisplayName("Sanitization: 'name' and 'email' are redacted but 'captureMode' is preserved")
        void sanitize_nameAndEmailRedacted_captureModePreserved() {
            Map<String, Object> payload = Map.of(
                    "name", "John Doe",
                    "email", "john@example.com",
                    "captureMode", "balanced"
            );

            String json = capturePayloadJson(payload);

            assertThat(json).isNotNull();
            assertThat(json).doesNotContain("John Doe");
            assertThat(json).doesNotContain("john@example.com");
            assertThat(json).contains("captureMode");
            assertThat(json).contains("balanced");
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  getLatestSentimentByChannel tests
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getLatestSentimentByChannel Tests")
    class GetLatestSentimentByChannelTests {

        @Test
        @DisplayName("Returns latest event per channel across TEXT, VOICE, VIDEO channels")
        void getLatestSentimentByChannel_returnsOneEntryPerChannel() {
            CallTelemetryEvent textEvent = buildSentimentEvent("TEXT", 0.75, LocalDateTime.now());
            CallTelemetryEvent voiceEvent = buildSentimentEvent("VOICE", 0.6, LocalDateTime.now().minusSeconds(5));
            CallTelemetryEvent videoEvent = buildSentimentEvent("VIDEO", 0.5, LocalDateTime.now().minusSeconds(10));

            when(callTelemetryEventRepository.findByCallIdOrderByOccurredAtDesc(CALL_ID))
                    .thenReturn(List.of(textEvent, voiceEvent, videoEvent));

            Map<String, CallTelemetryEvent> result =
                    callTelemetryService.getLatestSentimentByChannel(CALL_ID);

            assertThat(result).hasSize(3);
            assertThat(result).containsKeys("TEXT", "VOICE", "VIDEO");
        }

        @Test
        @DisplayName("Returns only the latest TEXT event when two TEXT events exist")
        void getLatestSentimentByChannel_returnsOnlyLatestPerChannel() {
            CallTelemetryEvent textLatest = buildSentimentEvent("TEXT", 0.9, LocalDateTime.now());
            CallTelemetryEvent textOlder = buildSentimentEvent("TEXT", 0.5, LocalDateTime.now().minusMinutes(1));

            // Repository returns desc order (latest first)
            when(callTelemetryEventRepository.findByCallIdOrderByOccurredAtDesc(CALL_ID))
                    .thenReturn(List.of(textLatest, textOlder));

            Map<String, CallTelemetryEvent> result =
                    callTelemetryService.getLatestSentimentByChannel(CALL_ID);

            assertThat(result).hasSize(1);
            assertThat(result.get("TEXT").getSentimentScore()).isEqualTo(0.9);
        }

        @Test
        @DisplayName("Returns empty map when no sentiment events exist for the call")
        void getLatestSentimentByChannel_noEvents_returnsEmptyMap() {
            when(callTelemetryEventRepository.findByCallIdOrderByOccurredAtDesc(CALL_ID))
                    .thenReturn(Collections.emptyList());

            Map<String, CallTelemetryEvent> result =
                    callTelemetryService.getLatestSentimentByChannel(CALL_ID);

            assertThat(result).isEmpty();
        }

        private CallTelemetryEvent buildSentimentEvent(String channel, double score, LocalDateTime occurredAt) {
            CallTelemetryEvent event = new CallTelemetryEvent();
            event.setCallId(CALL_ID);
            event.setChannel(channel);
            event.setSentimentScore(score);
            event.setSentimentLabel("CALM");
            event.setEventType("SENTIMENT_" + channel);
            event.setOccurredAt(occurredAt);
            return event;
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  getTelemetryForUser tests
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("getTelemetryForUser Tests")
    class GetTelemetryForUserTests {

        @Test
        @DisplayName("getTelemetryForUser calls findTop500ByActorUserIdOrTargetUserIdOrderByOccurredAtDesc")
        void getTelemetryForUser_callsCorrectRepositoryMethod() {
            Long userId = 42L;
            when(callTelemetryEventRepository
                    .findTop500ByActorUserIdOrTargetUserIdOrderByOccurredAtDesc(userId, userId))
                    .thenReturn(Collections.emptyList());

            List<CallTelemetryEvent> result = callTelemetryService.getTelemetryForUser(userId);

            assertThat(result).isNotNull();
            verify(callTelemetryEventRepository)
                    .findTop500ByActorUserIdOrTargetUserIdOrderByOccurredAtDesc(userId, userId);
        }
    }

    // ════════════════════════════════════════════════════════════════════════
    //  deleteTelemetryForCall tests
    // ════════════════════════════════════════════════════════════════════════

    @Nested
    @DisplayName("deleteTelemetryForCall Tests")
    class DeleteTelemetryForCallTests {

        @Test
        @DisplayName("deleteTelemetryForCall calls deleteByCallId on the repository")
        void deleteTelemetryForCall_callsDeleteByCallId() {
            when(callTelemetryEventRepository.deleteByCallId(CALL_ID)).thenReturn(5L);

            long deleted = callTelemetryService.deleteTelemetryForCall(CALL_ID);

            assertThat(deleted).isEqualTo(5L);
            verify(callTelemetryEventRepository).deleteByCallId(CALL_ID);
        }

        @Test
        @DisplayName("deleteTelemetryForCall with null callId returns 0 and does not call repository")
        void deleteTelemetryForCall_nullCallId_returnsZero() {
            long deleted = callTelemetryService.deleteTelemetryForCall(null);

            assertThat(deleted).isEqualTo(0L);
        }
    }
}
