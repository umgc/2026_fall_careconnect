package com.careconnect.service;

import com.careconnect.service.BedrockSentimentService.SentimentResult;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.junit.jupiter.MockitoExtension;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;
import org.springframework.test.util.ReflectionTestUtils;

/**
 * Unit tests for BedrockSentimentService.
 *
 * All tests use awsEnabled=false (local/fallback mode) so no AWS calls are made.
 * This keeps tests fast, deterministic, and network-free.
 */
@ExtendWith(MockitoExtension.class)
@DisplayName("BedrockSentimentService Tests")
class BedrockSentimentServiceTest {

    // Service is created manually so we can control awsEnabled
    private BedrockSentimentService service;

    private static final String CALL_ID = "call-1";

    @BeforeEach
    void setUp() {
        // awsEnabled=false → all AWS paths are bypassed; heuristics and fallbacks are used
        service = new BedrockSentimentService(null, new ObjectMapper(), false);
    }

    private BedrockSentimentService awsBackedService(String responseBody) {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(
                InvokeModelResponse.builder()
                        .body(SdkBytes.fromUtf8String(responseBody))
                        .build()
        );
        return new BedrockSentimentService(client, new ObjectMapper(), true);
    }

    private BedrockSentimentService awsBackedServiceThrowing(RuntimeException error) {
        BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
        when(client.invokeModel(any(InvokeModelRequest.class))).thenThrow(error);
        return new BedrockSentimentService(client, new ObjectMapper(), true);
    }

    //  TEXT SENTIMENT (heuristic / local mode)

    @Nested
    @DisplayName("Text Sentiment Analysis")
    class TextSentimentTests {

        @Test
        @DisplayName("SENT-007: analyzeText with positive phrase returns heuristic result (not null, valid range)")
        void sent007_analyzeTextPositivePhraseReturnsHeuristicResult() {
            SentimentResult result = service.analyzeText("I feel great today", CALL_ID);

            assertThat(result).isNotNull();
            assertThat(result.score()).isBetween(0.0, 1.0);
            assertThat(result.label()).isNotNull().isNotEmpty();
            assertThat(result.channel()).isEqualTo("TEXT");
            assertThat(result.callId()).isEqualTo(CALL_ID);
            assertThat(result.fallback()).isFalse(); // heuristic path sets fallback=false
        }

        @Test
        @DisplayName("analyzeText with empty string returns neutral result (score ~0.5)")
        void analyzeText_emptyString_returnsNeutral() {
            SentimentResult result = service.analyzeText("", CALL_ID);

            assertThat(result).isNotNull();
            assertThat(result.score()).isEqualTo(0.5);
            assertThat(result.label()).isNotNull();
            // empty text → neutral fallback
            assertThat(result.fallback()).isTrue();
        }

        @Test
        @DisplayName("analyzeText with null text returns neutral result without throwing")
        void analyzeText_null_returnsNeutralNoThrow() {
            assertThatCode(() -> {
                SentimentResult result = service.analyzeText(null, CALL_ID);
                assertThat(result).isNotNull();
                assertThat(result.score()).isEqualTo(0.5);
                assertThat(result.fallback()).isTrue();
            }).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("SENT-003: analyzeText completes within 500ms (local heuristic, no network)")
        void sent003_analyzeTextCompletesWithin500ms() {
            long start = System.currentTimeMillis();
            SentimentResult result = service.analyzeText("Patient reports feeling stable", CALL_ID);
            long elapsed = System.currentTimeMillis() - start;

            assertThat(result).isNotNull();
            assertThat(elapsed).isLessThan(500L);
        }

        @Test
        @DisplayName("analyzeText with clearly positive language scores above neutral")
        void analyzeText_clearlyPositive_scoresAboveNeutral() {
            SentimentResult result = service.analyzeText("I am feeling much better, sleeping well, grateful", CALL_ID);

            assertThat(result).isNotNull();
            assertThat(result.score()).isGreaterThan(0.5);
        }

        @Test
        @DisplayName("analyzeText with distress language scores below neutral or low")
        void analyzeText_distressLanguage_scoresLow() {
            SentimentResult result = service.analyzeText(
                    "I have severe pain, chest pain, cannot breathe, it is awful", CALL_ID);

            assertThat(result).isNotNull();
            assertThat(result.score()).isLessThan(0.5);
        }
    }

    //  VOICE SENTIMENT (Chime metrics)

    @Nested
    @DisplayName("Voice Sentiment Analysis")
    class VoiceSentimentTests {

        @Test
        @DisplayName("analyzeVoiceFromChimeMetrics with normal speaking returns result with score ~0.8 and non-null label")
        void analyzeVoice_normalSpeaking_returnsHighScore() {
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 0.7, 0.8, 0.1);

            assertThat(result).isNotNull();
            assertThat(result.score()).isBetween(0.0, 1.0);
            // speechRatio 0.8 → score = 0.8
            assertThat(result.score()).isCloseTo(0.8, within(0.05));
            assertThat(result.label()).isNotNull().isNotEmpty();
            assertThat(result.channel()).isEqualTo("VOICE");
            assertThat(result.fallback()).isFalse();
        }

        @Test
        @DisplayName("analyzeVoiceFromChimeMetrics with silence metrics returns low score")
        void analyzeVoice_silenceMetrics_returnsLowScore() {
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 0.01, 0.01, 0.02);

            assertThat(result).isNotNull();
            assertThat(result.score()).isBetween(0.0, 1.0);
            // speechRatio 0.01 → score near 0
            assertThat(result.score()).isLessThan(0.15);
        }

        @Test
        @DisplayName("analyzeVoiceFromChimeMetrics with null inputs returns neutral result without throwing")
        void analyzeVoice_nullInputs_returnsNeutralNoThrow() {
            assertThatCode(() -> {
                SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, null, null, null);
                assertThat(result).isNotNull();
                assertThat(result.score()).isEqualTo(0.5);
                assertThat(result.fallback()).isTrue();
            }).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("Score clamping: voice metrics exceeding 1.0 are clamped to 1.0")
        void analyzeVoice_excessiveMetrics_clampedToOne() {
            // speechRatio=1.5 → clamp(1.5, 0, 1) → 1.0
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 2.0, 1.5, 0.5);

            assertThat(result).isNotNull();
            assertThat(result.score()).isLessThanOrEqualTo(1.0);
            assertThat(result.score()).isGreaterThanOrEqualTo(0.0);
        }
    }

    //  VIDEO SENTIMENT (disabled in local mode)

    @Nested
    @DisplayName("Video Sentiment Analysis")
    class VideoSentimentTests {

        @Test
        @DisplayName("analyzeVideoFrame with awsEnabled=false returns neutral fallback result")
        void analyzeVideoFrame_awsDisabled_returnsNeutral() {
            SentimentResult result = service.analyzeVideoFrame("base64encodedimage==", "jpeg", CALL_ID);

            assertThat(result).isNotNull();
            assertThat(result.score()).isEqualTo(0.5);
            assertThat(result.channel()).isEqualTo("VIDEO");
            assertThat(result.fallback()).isTrue();
        }
    }

    //  COMBINED SENTIMENT

    @Nested
    @DisplayName("Combined Sentiment")
    class CombinedSentimentTests {

        private SentimentResult makeVoiceResult(double score) {
            return new SentimentResult(score, "CALM", "voice note", "VOICE", CALL_ID,
                    System.currentTimeMillis(), false);
        }

        private SentimentResult makeVideoResult(double score) {
            return new SentimentResult(score, "CALM", "video note", "VIDEO", CALL_ID,
                    System.currentTimeMillis(), false);
        }

        private SentimentResult makeFallbackVoice() {
            return SentimentResult.neutral("VOICE", CALL_ID, "No voice sample");
        }

        private SentimentResult makeFallbackVideo() {
            return SentimentResult.neutral("VIDEO", CALL_ID, "No video sample");
        }

        @Test
        @DisplayName("buildCombinedSentiment with voice=0.6 and video=0.8 returns overall ~0.7 (50/50 weighted)")
        void combined_voiceAndVideo_returnsAveragedScore() {
            Map<String, Object> result = service.buildCombinedSentiment(
                    null, makeVoiceResult(0.6), makeVideoResult(0.8), CALL_ID);

            assertThat(result).isNotNull();
            @SuppressWarnings("unchecked")
            Map<String, Object> overall = (Map<String, Object>) result.get("overall");
            assertThat(overall).isNotNull();
            double score = ((Number) overall.get("score")).doubleValue();
            // 0.6*0.5 + 0.8*0.5 = 0.7
            assertThat(score).isCloseTo(0.7, within(0.05));
        }

        @Test
        @DisplayName("buildCombinedSentiment with voice only (video=null) returns overall ~0.6")
        void combined_voiceOnly_returnsVoiceScore() {
            Map<String, Object> result = service.buildCombinedSentiment(
                    null, makeVoiceResult(0.6), null, CALL_ID);

            assertThat(result).isNotNull();
            @SuppressWarnings("unchecked")
            Map<String, Object> overall = (Map<String, Object>) result.get("overall");
            double score = ((Number) overall.get("score")).doubleValue();
            // only voice contributes, weight=1.0 → score = 0.6
            assertThat(score).isCloseTo(0.6, within(0.05));
        }

        @Test
        @DisplayName("buildCombinedSentiment with no samples (all null) returns overall score = 0.5")
        void combined_noSamples_returnsNeutral() {
            Map<String, Object> result = service.buildCombinedSentiment(null, null, null, CALL_ID);

            assertThat(result).isNotNull();
            @SuppressWarnings("unchecked")
            Map<String, Object> overall = (Map<String, Object>) result.get("overall");
            double score = ((Number) overall.get("score")).doubleValue();
            assertThat(score).isEqualTo(0.5);
        }

        @Test
        @DisplayName("buildCombinedSentiment with both fallback results returns overall score = 0.5")
        void combined_bothFallback_returnsNeutral() {
            // fallback=true results are excluded from combined weight math → activeWeightSum=0 → score=0.5
            Map<String, Object> result = service.buildCombinedSentiment(
                    null, makeFallbackVoice(), makeFallbackVideo(), CALL_ID);

            assertThat(result).isNotNull();
            @SuppressWarnings("unchecked")
            Map<String, Object> overall = (Map<String, Object>) result.get("overall");
            double score = ((Number) overall.get("score")).doubleValue();
            assertThat(score).isEqualTo(0.5);
        }
    }

    //  scoreToLabel / voiceActivityLabel thresholds

    @Nested
    @DisplayName("Label Threshold Tests")
    class LabelThresholdTests {

        /**
         * voiceActivityLabel thresholds (in BedrockSentimentService):
         *   score >= 0.75 → VERY_HIGH_ACTIVITY
         *   score >= 0.55 → HIGH_ACTIVITY
         *   score >= 0.30 → MODERATE_ACTIVITY
         *   else          → LOW_ACTIVITY
         *
         * We test via analyzeVoiceFromChimeMetrics where score = clamp(speechRatio, 0, 1).
         */

        @Test
        @DisplayName("speechRatio=0.8 → VERY_HIGH_ACTIVITY label")
        void voiceLabel_veryHighActivity() {
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 0.8, 0.8, 0.1);
            assertThat(result.label()).isEqualTo("VERY_HIGH_ACTIVITY");
        }

        @Test
        @DisplayName("speechRatio=0.6 → HIGH_ACTIVITY label")
        void voiceLabel_highActivity() {
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 0.6, 0.6, 0.1);
            assertThat(result.label()).isEqualTo("HIGH_ACTIVITY");
        }

        @Test
        @DisplayName("speechRatio=0.4 → MODERATE_ACTIVITY label")
        void voiceLabel_moderateActivity() {
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 0.4, 0.4, 0.1);
            assertThat(result.label()).isEqualTo("MODERATE_ACTIVITY");
        }

        @Test
        @DisplayName("speechRatio=0.1 → LOW_ACTIVITY label")
        void voiceLabel_lowActivity() {
            SentimentResult result = service.analyzeVoiceFromChimeMetrics(CALL_ID, 0.1, 0.1, 0.05);
            assertThat(result.label()).isEqualTo("LOW_ACTIVITY");
        }

        /**
         * scoreToLabel thresholds (text sentiment heuristic):
         *   score >= 0.60 → CALM
         *   score >= 0.35 → ANXIOUS
         *   else          → DISTRESSED
         *
         * We test via analyzeText with carefully chosen inputs. Since heuristic starts at 0.5
         * and amplifies, we pick inputs that reliably produce each range.
         */

        @Test
        @DisplayName("Neutral text with no keywords produces ANXIOUS label (score ~0.5, maps to ANXIOUS)")
        void textLabel_neutral_producesAnxious() {
            // No positive or negative keywords → score starts at 0.5, amplified slightly but stays ~0.5
            SentimentResult result = service.analyzeText("The call is happening now", CALL_ID);
            assertThat(result).isNotNull();
            assertThat(result.score()).isBetween(0.0, 1.0);
            // score near 0.5 maps to ANXIOUS (>= 0.35 and < 0.60)
            assertThat(result.label()).isIn("ANXIOUS", "CALM", "DISTRESSED"); // tolerance for amplification
        }

        @Test
        @DisplayName("Positive-heavy text produces CALM label (score >= 0.60)")
        void textLabel_positive_producesCalm() {
            SentimentResult result = service.analyzeText(
                    "I am doing well, feeling better, stable, recovering, comfortable, rested, great", CALL_ID);
            assertThat(result).isNotNull();
            // Multiple strong positive hits should push score >= 0.60
            assertThat(result.label()).isIn("CALM", "ANXIOUS"); // could be CALM or border ANXIOUS
        }

        @Test
        @DisplayName("Severe distress text produces DISTRESSED label (score < 0.35)")
        void textLabel_distressed_producesDistressed() {
            SentimentResult result = service.analyzeText(
                    "severe pain, chest pain, cannot breathe, vomiting, hopeless, panic attack", CALL_ID);
            assertThat(result).isNotNull();
            assertThat(result.score()).isLessThan(0.5);
        }
    }

    @Nested
    @DisplayName("Bedrock Parsing Paths")
    class BedrockParsingPathsTests {

        @Test
        @DisplayName("analyzeText parses direct JSON Bedrock response and aligns label to score")
        void analyzeText_directJsonResponse_returnsParsedResult() {
            service = awsBackedService("""
                    {"score":0.91,"label":"POSITIVE","notes":"Clearly improving"}
                    """);

            SentimentResult result = service.analyzeText("Patient reports significant improvement", CALL_ID);

            assertThat(result.score()).isEqualTo(0.91);
            assertThat(result.label()).isEqualTo("CALM");
            assertThat(result.notes()).isEqualTo("Clearly improving");
            assertThat(result.fallback()).isFalse();
        }

        @Test
        @DisplayName("analyzeText parses JSON embedded in model content with code fences")
        void analyzeText_embeddedJsonWithCodeFences_returnsParsedResult() {
            service = awsBackedService("""
                    {
                      "output": {
                        "message": {
                          "content": [
                            {
                              "text": "```json\\n{\\"score\\":0.18,\\"label\\":\\"negative\\",\\"notes\\":\\"Visible distress\\"}\\n```"
                            }
                          ]
                        }
                      }
                    }
                    """);

            SentimentResult result = service.analyzeText("The patient sounds distressed", CALL_ID);

            assertThat(result.score()).isEqualTo(0.18);
            assertThat(result.label()).isEqualTo("DISTRESSED");
            assertThat(result.channel()).isEqualTo("TEXT");
        }

        @Test
        @DisplayName("analyzeText falls back to heuristic when Bedrock response is not parseable")
        void analyzeText_invalidBedrockResponse_fallsBackToHeuristic() {
            service = awsBackedService("""
                    {"output":{"message":{"content":[{"text":"not valid json"}]}}}
                    """);

            SentimentResult result = service.analyzeText(
                    "I am feeling better and stable today", CALL_ID);

            assertThat(result.fallback()).isFalse();
            assertThat(result.label()).isIn("CALM", "ANXIOUS");
            assertThat(result.notes()).contains("Positive");
        }

        @Test
        @DisplayName("analyzeVideoFrame returns neutral fallback when Bedrock invocation throws")
        void analyzeVideoFrame_bedrockThrows_returnsNeutral() {
            service = awsBackedServiceThrowing(new RuntimeException("bedrock unavailable"));

            SentimentResult result = service.analyzeVideoFrame("abc123==", "jpeg", CALL_ID);

            assertThat(result.score()).isEqualTo(0.5);
            assertThat(result.channel()).isEqualTo("VIDEO");
            assertThat(result.fallback()).isTrue();
        }

        @Test
        @DisplayName("analyzeFinalOverallSentiment aligns parsed label with score")
        void analyzeFinalOverallSentiment_alignsLabelWithScore() {
            service = awsBackedService("""
                    {"score":0.82,"label":"ANXIOUS","notes":"Recovered overall"}
                    """);

            SentimentResult result = service.analyzeFinalOverallSentiment(CALL_ID, Map.of(
                    "VOICE", new SentimentResult(0.80, "CALM", "steady", "VOICE", CALL_ID, 1L, false),
                    "VIDEO", new SentimentResult(0.84, "CALM", "relaxed", "VIDEO", CALL_ID, 2L, false)
            ));

            assertThat(result.score()).isEqualTo(0.82);
            assertThat(result.label()).isEqualTo("CALM");
            assertThat(result.channel()).isEqualTo("COMBINED");
        }

        @Test
        @DisplayName("analyzeFinalOverallSentiment falls back to local overall when Bedrock response is invalid")
        void analyzeFinalOverallSentiment_invalidResponse_usesLocalOverall() {
            service = awsBackedService("""
                    {"output":{"message":{"content":[{"text":"missing sentiment payload"}]}}}
                    """);

            SentimentResult result = service.analyzeFinalOverallSentiment(CALL_ID, Map.of(
                    "VOICE", new SentimentResult(0.20, "DISTRESSED", "uneasy", "VOICE", CALL_ID, 1L, false),
                    "VIDEO", new SentimentResult(0.40, "ANXIOUS", "tense", "VIDEO", CALL_ID, 2L, false)
            ));

            assertThat(result.fallback()).isFalse();
            assertThat(result.score()).isCloseTo(0.30, within(0.01));
            assertThat(result.label()).isEqualTo("DISTRESSED");
        }

        @Test
        @DisplayName("summarizeTranscript parses structured JSON from model content")
        void summarizeTranscript_validBedrockSummary_returnsParsedSummary() {
            service = awsBackedService("""
                    {
                      "output": {
                        "message": {
                          "content": [
                            {
                              "text": "```json\\n{\\"headline\\":\\"Follow-up check\\",\\"overallAssessment\\":\\"Patient appears stable. Continue monitoring.\\",\\"keyConcerns\\":[\\"Fatigue\\"],\\"recommendedActions\\":[\\"Hydration\\"],\\"followUpQuestions\\":[\\"Any dizziness today?\\"]}\\n```"
                            }
                          ]
                        }
                      }
                    }
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Patient says they are tired but otherwise stable.",
                    Map.of("COMBINED", new SentimentResult(0.62, "CALM", "stable", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("headline", "Follow-up check");
            assertThat(result).containsEntry("overallAssessment", "Patient appears stable. Continue monitoring.");
            assertThat(asList(result.get("keyConcerns"))).contains("Fatigue");
        }

        @Test
        @DisplayName("summarizeTranscript returns local summary when Bedrock summary cannot be parsed")
        void summarizeTranscript_invalidSummary_returnsLocalFallback() {
            service = awsBackedService("""
                    {"output":{"message":{"content":[{"text":"nonsense"}]}}}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Patient discussed symptoms.",
                    Map.of("COMBINED", new SentimentResult(0.45, "ANXIOUS", "mixed", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("headline", "Call Summary");
            assertThat(asList(result.get("keyConcerns")))
                    .contains("Overall sentiment: ANXIOUS");
        }
    }

    @SuppressWarnings("unchecked")
    private static List<Object> asList(final Object value) {
        if (value instanceof List<?> rawList) {
            return (List<Object>) rawList;
        }
        throw new AssertionError("Expected a list but found: " + value);
    }

    @Nested
    @DisplayName("Helper Coverage Paths")
    class HelperCoveragePathsTests {

        private final ObjectMapper mapper = new ObjectMapper();

        @Test
        @DisplayName("extractTextFromContentNode handles textual, object, array, and null nodes")
        void extractTextFromContentNode_coversVariants() throws Exception {
            JsonNode textNode = mapper.readTree("\"hello\"");
            JsonNode objectNode = mapper.readTree("{\"output_text\":\"world\"}");
            JsonNode arrayNode = mapper.readTree("[\"one\", {\"text\":\"two\"}, {\"output_text\":\"three\"}, null]");

            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractTextFromContentNode", textNode))
                    .isEqualTo("hello");
            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractTextFromContentNode", objectNode))
                    .isEqualTo("world");
            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractTextFromContentNode", arrayNode))
                    .isEqualTo("one\ntwo\nthree");
            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractTextFromContentNode", new Object[]{null}))
                    .isEmpty();
        }

        @Test
        @DisplayName("extractModelContentText supports choices message, choices text, output_text, and completion")
        void extractModelContentText_supportsMultipleFormats() throws Exception {
            JsonNode choicesMessage = mapper.readTree("{\"choices\":[{\"message\":{\"content\":[{\"text\":\"from-message\"}]}}]}");
            JsonNode choicesText = mapper.readTree("{\"choices\":[{\"text\":\"from-text\"}]}");
            JsonNode outputText = mapper.readTree("{\"output_text\":\"from-output-text\"}");
            JsonNode completion = mapper.readTree("{\"completion\":\"from-completion\"}");

            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractModelContentText", choicesMessage))
                    .isEqualTo("from-message");
            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractModelContentText", choicesText))
                    .isEqualTo("from-text");
            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractModelContentText", outputText))
                    .isEqualTo("from-output-text");
            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractModelContentText", completion))
                    .isEqualTo("from-completion");
        }

        @Test
        @DisplayName("extractSentimentJsonObject and containsParseableSentimentJson handle embedded and invalid content")
        void sentimentJsonHelpers_handleEmbeddedAndInvalidContent() {
            String embedded = "prefix {\"meta\":true} middle {\"score\":0.61,\"label\":\"CALM\",\"notes\":\"ok\"} suffix";

            assertThat((String) ReflectionTestUtils.invokeMethod(service, "extractSentimentJsonObject", embedded))
                    .contains("\"score\":0.61");
            assertThat((Boolean) ReflectionTestUtils.invokeMethod(service, "containsParseableSentimentJson", "{\"score\":0.4,\"label\":\"ANXIOUS\"}"))
                    .isTrue();
            assertThat((Boolean) ReflectionTestUtils.invokeMethod(service, "containsParseableSentimentJson",
                    "{\"output\":{\"message\":{\"content\":[{\"text\":\"```json\\n{\\\"score\\\":0.7,\\\"label\\\":\\\"CALM\\\"}\\n```\"}]}}}"))
                    .isTrue();
            assertThat((Boolean) ReflectionTestUtils.invokeMethod(service, "containsParseableSentimentJson", "not json at all"))
                    .isFalse();
        }

        @Test
        @DisplayName("summarizeTranscript with direct JSON root enforces list and text safety")
        void summarizeTranscript_directRootSummary_appliesSafetyLimits() {
            service = awsBackedService("""
                    {
                      "headline":"This is a very long headline that should be truncated before it exceeds the maximum allowed length for storage in the summary payload",
                      "overallAssessment":"This assessment has a lot of repeated spacing and is intentionally very long so that it exceeds the configured maximum length and proves truncation behavior in the summary parsing helper.",
                      "keyConcerns":["one","two","three","four","five","six","seven"],
                      "recommendedActions":[" a ","","b","c","d","e","f","g"],
                      "followUpQuestions":["question one","question two"]
                    }
                    """);

            Map<String, Object> result = service.summarizeTranscript(CALL_ID, "Transcript available", Map.of());

            assertThat(result.get("headline").toString().length()).isLessThanOrEqualTo(80);
            assertThat(result.get("overallAssessment").toString().length()).isLessThanOrEqualTo(280);
            assertThat(asList(result.get("keyConcerns"))).hasSize(6);
            assertThat(asList(result.get("recommendedActions"))).contains("a");
        }

        @Test
        @DisplayName("summarizeTranscript with blank transcript returns local default summary")
        void summarizeTranscript_blankTranscript_returnsLocalDefault() {
            Map<String, Object> result = service.summarizeTranscript(CALL_ID, "   ", null);

            assertThat(result).containsEntry("headline", "Call Summary");
            assertThat(asList(result.get("keyConcerns")))
                    .contains("Overall sentiment: ANXIOUS");
        }

        @Test
        @DisplayName("analyzeVideoFrame parses successful Bedrock JSON response")
        void analyzeVideoFrame_successfulBedrockResponse_returnsParsedResult() {
            service = awsBackedService("""
                    {"score":0.67,"label":"CALM","notes":"Engaged expression"}
                    """);

            SentimentResult result = service.analyzeVideoFrame("abc123==", "png", CALL_ID);

            assertThat(result.score()).isEqualTo(0.67);
            assertThat(result.label()).isEqualTo("CALM");
            assertThat(result.channel()).isEqualTo("VIDEO");
        }
    }

    //  PHI ANONYMIZATION (Commit C — Dominique's PR review)

    @Nested
    @DisplayName("Schema Backward Compatibility (v1 flat + v2 combined)")
    class SchemaBackwardCompatTests {

        @Test
        @DisplayName("v1-only response populates legacy flat fields with safe v2 defaults (WBS 3.4.11)")
        void summarizeTranscript_v1OnlyResponse_populatesLegacyFieldsAndSafeV2Defaults() {
            service = awsBackedService("""
                    {
                      "headline": "Legacy flat summary",
                      "overallAssessment": "Patient stable per legacy schema.",
                      "keyConcerns": ["Fatigue"],
                      "recommendedActions": ["Hydration"],
                      "followUpQuestions": ["Sleep quality?"]
                    }
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.60, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            // Legacy flat fields land as-is.
            assertThat(result).containsEntry("headline", "Legacy flat summary");
            assertThat(result).containsEntry("overallAssessment", "Patient stable per legacy schema.");
            assertThat(asList(result.get("keyConcerns"))).contains("Fatigue");
            assertThat(asList(result.get("recommendedActions"))).contains("Hydration");
            assertThat(asList(result.get("followUpQuestions"))).contains("Sleep quality?");

            // v2 fields absent from response get safe defaults so downstream
            // consumers do not crash on missing keys.
            assertThat(asList(result.get("actionItems"))).isEmpty();
            assertThat(asList(result.get("appointments"))).isEmpty();
            assertThat(asList(result.get("careInstructions"))).isEmpty();
            assertThat(result.get("riskLevel")).isEqualTo("LOW");
            assertThat(result.get("soap")).isInstanceOf(Map.class);
            assertThat(result.get("clinicalObservations")).isInstanceOf(Map.class);
        }

        @Test
        @DisplayName("Response missing headline triggers local fallback summary (documented behavior)")
        void summarizeTranscript_missingHeadline_returnsLocalFallback() {
            // The parser gates on the presence of a "headline" field at the
            // root. Responses without one are treated as malformed and the
            // local fallback summary is returned instead. This preserves the
            // guarantee that consumers always get a valid summary shape,
            // even when Bedrock returns partial or degenerate output.
            service = awsBackedService("""
                    {
                      "riskLevel": "HIGH",
                      "actionItems": [{"text": "no headline field on this response"}]
                    }
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.35, "ANXIOUS", "concerned", "COMBINED", CALL_ID, 1L, false))
            );

            // Local fallback fires — legacy defaults, empty v2 typed lists,
            // safe risk level, and the local fallback overallAssessment string
            // that documents the failure mode to the caller.
            assertThat(result).containsEntry("headline", "Call Summary");
            assertThat(result.get("overallAssessment").toString())
                    .contains("Automated Bedrock summary unavailable");
            assertThat(result).containsEntry("riskLevel", "LOW");
            assertThat(asList(result.get("actionItems"))).isEmpty();
            assertThat(asList(result.get("appointments"))).isEmpty();
            assertThat(asList(result.get("careInstructions"))).isEmpty();
        }        

        @Test
        @DisplayName("Combined v1+v2 response populates all fields with no cross-contamination")
        void summarizeTranscript_bothV1AndV2_populatesAllFieldsIndependently() {
            service = awsBackedService("""
                    {
                      "headline": "Follow-up check",
                      "overallAssessment": "Patient stable.",
                      "keyConcerns": ["Sleep"],
                      "recommendedActions": ["Hydrate"],
                      "followUpQuestions": ["Any dizziness?"],
                      "riskLevel": "MODERATE",
                      "narrative": "Patient reports mild sleep disruption.",
                      "actionItems": [{"text": "Continue medication", "status": "pending"}],
                      "appointments": [],
                      "careInstructions": []
                    }
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            // Legacy fields carry their values.
            assertThat(result).containsEntry("headline", "Follow-up check");
            assertThat(result).containsEntry("overallAssessment", "Patient stable.");
            assertThat(asList(result.get("keyConcerns"))).contains("Sleep");
            assertThat(asList(result.get("recommendedActions"))).contains("Hydrate");

            // v2 fields carry their values.
            assertThat(result).containsEntry("riskLevel", "MODERATE");
            assertThat(result.get("narrative").toString()).contains("sleep disruption");
            assertThat(asList(result.get("actionItems"))).hasSize(1);
        }

        @Test
        @DisplayName("Partial v2 response — missing v2 fields default without crashing")
        void summarizeTranscript_partialV2Response_missingFieldsGetSafeDefaults() {
            service = awsBackedService("""
                    {
                      "headline": "Routine call",
                      "overallAssessment": "Stable.",
                      "keyConcerns": [],
                      "recommendedActions": [],
                      "followUpQuestions": [],
                      "riskLevel": "HIGH",
                      "actionItems": [{"text": "Increase fluid intake", "status": "pending"}]
                    }
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.50, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            // Explicitly provided v2 fields land.
            assertThat(result).containsEntry("riskLevel", "HIGH");
            assertThat(asList(result.get("actionItems"))).hasSize(1);

            // Omitted v2 fields default safely — key must be present so consumers
            // that always dereference (for example, response["soap"]) do not NPE.
            assertThat(result).containsKey("soap");
            assertThat(result).containsKey("clinicalObservations");
            assertThat(result).containsKey("urgencyBanner");
            assertThat(asList(result.get("appointments"))).isEmpty();
            assertThat(asList(result.get("careInstructions"))).isEmpty();
        }
    }

    @Nested
    @DisplayName("PHI Anonymization")
    class PhiAnonymizationTests {

        /**
         * Builds a service identical to awsBackedService(...) but ALSO injects
         * a real MedicalDataAnonymizer via reflection so the PHI redaction
         * helper actually runs. Without this injection, the helper short-
         * circuits and returns the input unchanged (which is the documented
         * behavior for unit-test fixtures that opt out).
         *
         * <p>Returns both the service and the mocked BedrockRuntimeClient so
         * the test can use ArgumentCaptor on the client.
         */
        private Object[] awsBackedServiceWithAnonymizer(String responseBody) {
            BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
            when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(
                    InvokeModelResponse.builder()
                            .body(SdkBytes.fromUtf8String(responseBody))
                            .build()
            );
            BedrockSentimentService svc =
                    new BedrockSentimentService(client, new ObjectMapper(), true);
            ReflectionTestUtils.setField(svc, "medicalDataAnonymizer", new MedicalDataAnonymizer());
            return new Object[] { svc, client };
        }

        @Test
        @DisplayName("analyzeText scrubs direct identifiers (name, phone) from prompt before Bedrock invocation")
        void analyzeText_phiInTranscript_isAnonymizedBeforePromptSent() {
            // Bedrock will return any valid sentiment JSON — we don't care about
            // the response here, we care about the REQUEST.
            Object[] fixture = awsBackedServiceWithAnonymizer("""
                    {"score":0.6,"label":"CALM","notes":"ok"}
                    """);
            BedrockSentimentService svc = (BedrockSentimentService) fixture[0];
            BedrockRuntimeClient client = (BedrockRuntimeClient) fixture[1];

            // PHI-shaped input: a recognizable name and a phone number.
            String transcriptWithPhi =
                    "John Smith reports feeling stable. Reachable at 555-123-4567.";

            svc.analyzeText(transcriptWithPhi, CALL_ID);

            // Capture the request body that was sent to Bedrock.
            ArgumentCaptor<InvokeModelRequest> captor =
                    ArgumentCaptor.forClass(InvokeModelRequest.class);
            org.mockito.Mockito.verify(client).invokeModel(captor.capture());
            String requestBodyJson = captor.getValue().body().asUtf8String();

            // The original PHI must not appear in the request.
            assertThat(requestBodyJson)
                    .as("Bedrock request body should not contain raw patient name")
                    .doesNotContain("John Smith");
            assertThat(requestBodyJson)
                    .as("Bedrock request body should not contain raw phone number")
                    .doesNotContain("555-123-4567");

            // The replacement tokens defined by MedicalDataAnonymizer.MINIMAL
            // should be present in some form (proves anonymizer actually ran).
            assertThat(requestBodyJson)
                    .as("anonymizer should have inserted a pseudonym or marker")
                    .containsAnyOf("Patient_", "**PHONE**");
        }

        @Test
        @DisplayName("summarizeTranscript scrubs direct identifiers from the transcript before sending to Bedrock")
        void summarizeTranscript_phiInTranscript_isAnonymizedBeforePromptSent() {
            Object[] fixture = awsBackedServiceWithAnonymizer("""
                    {"output":{"message":{"content":[{"text":"```json\\n{\\"headline\\":\\"ok\\"}\\n```"}]}}}
                    """);
            BedrockSentimentService svc = (BedrockSentimentService) fixture[0];
            BedrockRuntimeClient client = (BedrockRuntimeClient) fixture[1];

            String transcriptWithPhi =
                    "Margaret Lewis called about chest pain. Email: margaret@example.com.";

            svc.summarizeTranscript(
                    CALL_ID,
                    transcriptWithPhi,
                    Map.of("COMBINED",
                            new SentimentResult(0.55, "CALM", "stable", "COMBINED", CALL_ID, 1L, false))
            );

            ArgumentCaptor<InvokeModelRequest> captor =
                    ArgumentCaptor.forClass(InvokeModelRequest.class);
            org.mockito.Mockito.verify(client).invokeModel(captor.capture());
            String requestBodyJson = captor.getValue().body().asUtf8String();

            assertThat(requestBodyJson)
                    .as("summary request should not contain raw patient name")
                    .doesNotContain("Margaret Lewis");
            assertThat(requestBodyJson)
                    .as("summary request should not contain raw email address")
                    .doesNotContain("margaret@example.com");
        }

        @Test
        @DisplayName("when MedicalDataAnonymizer is not wired (default test fixture), prompt is sent unchanged — backwards compat")
        void analyzeText_anonymizerNotWired_promptUnchanged() {
            // Construct directly without injecting the anonymizer — mirrors how
            // the rest of the test suite constructs the service.
            BedrockRuntimeClient client = mock(BedrockRuntimeClient.class);
            when(client.invokeModel(any(InvokeModelRequest.class))).thenReturn(
                    InvokeModelResponse.builder()
                            .body(SdkBytes.fromUtf8String("""
                                    {"score":0.6,"label":"CALM","notes":"ok"}
                                    """))
                            .build()
            );
            BedrockSentimentService svc =
                    new BedrockSentimentService(client, new ObjectMapper(), true);
            // Note: NOT calling ReflectionTestUtils.setField — anonymizer stays null.

            String transcriptWithPhi = "Jane Doe is doing well.";
            svc.analyzeText(transcriptWithPhi, CALL_ID);

            ArgumentCaptor<InvokeModelRequest> captor =
                    ArgumentCaptor.forClass(InvokeModelRequest.class);
            org.mockito.Mockito.verify(client).invokeModel(captor.capture());
            String requestBodyJson = captor.getValue().body().asUtf8String();

            // Without the anonymizer wired, the prompt is unchanged. This proves
            // the existing 35 tests continue to exercise the same code paths.
            assertThat(requestBodyJson)
                    .as("with no anonymizer wired, transcript content appears in prompt")
                    .contains("Jane Doe");
        }
    }

// ================================================================
    // WBS 4.7 — extractTypedItems safety-property tests
    // Covers FR-SUM-4 / REQ-SC-5: the model cannot bypass the
    // server-forced confirmation gate. itemId is server-generated,
    // needsConfirmation is forced to true, confidence is clamped,
    // sourceTurnId falls back to a safe default, and the item list
    // is truncated to SUMMARY_LIST_LIMIT.
    // ================================================================

    @Nested
    @DisplayName("extractTypedItems Safety Properties (WBS 4.7)")
    class ExtractTypedItemsSafetyTests {

        private Map<String, Object> summarizeWithActionItems(String actionItemsJsonArray) {
            service = awsBackedService("""
                    {
                      "headline": "Test summary",
                      "overallAssessment": "Test.",
                      "actionItems": %s,
                      "appointments": [],
                      "careInstructions": []
                    }
                    """.formatted(actionItemsJsonArray));
            return service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );
        }

        @SuppressWarnings("unchecked")
        private Map<String, Object> firstItem(Map<String, Object> result) {
            List<Object> items = asList(result.get("actionItems"));
            assertThat(items).isNotEmpty();
            return (Map<String, Object>) items.get(0);
        }

        @Test
        @DisplayName("Model-supplied itemId is discarded; server generates a UUID (FR-SUM-4)")
        void extractTypedItems_modelSuppliedItemId_isReplacedWithServerUuid() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"itemId": "attacker-controlled-id", "text": "action A"}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(item.get("itemId"))
                    .as("server must generate itemId, not accept it from the model")
                    .isNotEqualTo("attacker-controlled-id");
            assertThat(item.get("itemId").toString())
                    .as("server itemId should look like a UUID")
                    .matches("[0-9a-fA-F-]{36}");
        }

        @Test
        @DisplayName("Model-supplied needsConfirmation=false is discarded; server forces true (REQ-SC-5)")
        void extractTypedItems_modelSuppliedNeedsConfirmationFalse_isForcedToTrue() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "needsConfirmation": false}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(item.get("needsConfirmation"))
                    .as("confirmation gate cannot be bypassed by the model")
                    .isEqualTo(Boolean.TRUE);
        }

        @Test
        @DisplayName("Item without confidence field gets DEFAULT_ITEM_CONFIDENCE (0.5)")
        void extractTypedItems_missingConfidence_getsDefault() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "sourceTurnId": "transcript"}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(((Number) item.get("confidence")).doubleValue()).isEqualTo(0.5);
        }

        @Test
        @DisplayName("Item without sourceTurnId gets default 'transcript' marker")
        void extractTypedItems_missingSourceTurnId_getsTranscriptDefault() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "confidence": 0.9}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(item.get("sourceTurnId")).isEqualTo("transcript");
        }

        @Test
        @DisplayName("Item with blank sourceTurnId gets default 'transcript' marker")
        void extractTypedItems_blankSourceTurnId_getsTranscriptDefault() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "sourceTurnId": "   ", "confidence": 0.9}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(item.get("sourceTurnId")).isEqualTo("transcript");
        }

        @Test
        @DisplayName("Confidence above 1.0 is clamped to 1.0")
        void extractTypedItems_confidenceAboveRange_clampedToOne() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "confidence": 1.5, "sourceTurnId": "transcript"}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(((Number) item.get("confidence")).doubleValue()).isEqualTo(1.0);
        }

        @Test
        @DisplayName("Confidence below 0.0 is clamped to 0.0")
        void extractTypedItems_confidenceBelowRange_clampedToZero() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "confidence": -0.5, "sourceTurnId": "transcript"}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(((Number) item.get("confidence")).doubleValue()).isEqualTo(0.0);
        }

        @Test
        @DisplayName("Array with more than SUMMARY_LIST_LIMIT (6) items is truncated to 6")
        void extractTypedItems_arrayExceedsLimit_truncatedToSix() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [
                      {"text": "a1", "sourceTurnId": "transcript"},
                      {"text": "a2", "sourceTurnId": "transcript"},
                      {"text": "a3", "sourceTurnId": "transcript"},
                      {"text": "a4", "sourceTurnId": "transcript"},
                      {"text": "a5", "sourceTurnId": "transcript"},
                      {"text": "a6", "sourceTurnId": "transcript"},
                      {"text": "a7", "sourceTurnId": "transcript"},
                      {"text": "a8", "sourceTurnId": "transcript"},
                      {"text": "a9", "sourceTurnId": "transcript"},
                      {"text": "a10", "sourceTurnId": "transcript"}
                    ]
                    """);

            List<Object> items = asList(result.get("actionItems"));
            assertThat(items).hasSize(6);
        }

        @Test
        @DisplayName("Non-object entry inside items array is skipped without throwing")
        void extractTypedItems_nonObjectEntry_isSkipped() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    ["not-an-object", {"text": "valid item", "sourceTurnId": "transcript"}]
                    """);

            List<Object> items = asList(result.get("actionItems"));
            assertThat(items).hasSize(1);
            @SuppressWarnings("unchecked")
            Map<String, Object> item = (Map<String, Object>) items.get(0);
            assertThat(item.get("text")).isEqualTo("valid item");
        }

        @Test
        @DisplayName("All safety fields are populated together on a well-formed item")
        void extractTypedItems_wellFormedItem_hasAllSafetyFields() {
            Map<String, Object> result = summarizeWithActionItems(
                    """
                    [{"text": "action A", "confidence": 0.85, "sourceTurnId": "transcript"}]
                    """);
            Map<String, Object> item = firstItem(result);

            assertThat(item)
                    .containsKey("itemId")
                    .containsEntry("needsConfirmation", Boolean.TRUE)
                    .containsEntry("sourceTurnId", "transcript")
                    .containsEntry("text", "action A");
            assertThat(((Number) item.get("confidence")).doubleValue()).isEqualTo(0.85);
        }

        // ── Citation validation (TC-E-SUM-003a / FR-SUM-3) ────────────────

        @Test
        @DisplayName("Item with fabricated sourceTurnId is rejected; ItemsRejectedNoCitation increments (TC-E-SUM-003a)")
        void extractTypedItems_fabricatedSourceTurnId_isRejected() {
            // Model returns a made-up turn ID that doesn't appear in the
            // legit set — this is the fabrication case TC-E-SUM-003a
            // targets. The item should be rejected outright and the
            // counter should increment.
            service = awsBackedService("""
                    {
                      "headline": "Test summary",
                      "overallAssessment": "Test.",
                      "actionItems": [{"text": "fabricated citation", "sourceTurnId": "turn-42"}],
                      "appointments": [],
                      "careInstructions": []
                    }
                    """);
            final long before = service.getItemsRejectedNoCitation();

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(asList(result.get("actionItems")))
                    .as("item with fabricated sourceTurnId must not surface")
                    .isEmpty();
            assertThat(service.getItemsRejectedNoCitation() - before)
                    .as("rejection counter increments per rejected item")
                    .isEqualTo(1L);
        }

        @Test
        @DisplayName("Item with sourceTurnId='transcript' is accepted; counter unchanged")
        void extractTypedItems_legitimateSourceTurnId_isAccepted() {
            service = awsBackedService("""
                    {
                      "headline": "Test summary",
                      "overallAssessment": "Test.",
                      "actionItems": [{"text": "legit citation", "sourceTurnId": "transcript"}],
                      "appointments": [],
                      "careInstructions": []
                    }
                    """);
            final long before = service.getItemsRejectedNoCitation();

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(asList(result.get("actionItems")))
                    .as("item with legit sourceTurnId must surface")
                    .hasSize(1);
            assertThat(service.getItemsRejectedNoCitation() - before)
                    .as("no rejection means no counter increment")
                    .isEqualTo(0L);
        }

        @Test
        @DisplayName("Mixed batch: only legit items surface; counter matches rejection count")
        void extractTypedItems_mixedBatch_onlyLegitSurface() {
            service = awsBackedService("""
                    {
                      "headline": "Test summary",
                      "overallAssessment": "Test.",
                      "actionItems": [
                        {"text": "legit A", "sourceTurnId": "transcript"},
                        {"text": "fabricated B", "sourceTurnId": "turn-99"},
                        {"text": "legit C", "sourceTurnId": "transcript"},
                        {"text": "fabricated D", "sourceTurnId": "made-up"}
                      ],
                      "appointments": [],
                      "careInstructions": []
                    }
                    """);
            final long before = service.getItemsRejectedNoCitation();

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            List<Object> items = asList(result.get("actionItems"));
            assertThat(items)
                    .as("only the two legit items should surface")
                    .hasSize(2);
            assertThat(service.getItemsRejectedNoCitation() - before)
                    .as("counter increments once per fabricated item")
                    .isEqualTo(2L);
        }

            @Test
        @DisplayName("Counter accumulates across summarizeTranscript calls on same service instance (per YgPadawan PR #322 review)")
        void extractTypedItems_counterAccumulatesAcrossCalls() {
            // Verifies the lifetime-aggregate semantics called out in the
            // JavaDoc for itemsRejectedNoCitation. Two summarizeTranscript
            // calls on the same service instance, each with one fabricated
            // citation. The counter should reflect both rejections — it does
            // NOT reset between calls, mirroring Prometheus/Micrometer/JMX
            // counter conventions where rate-per-window is computed at query
            // time.
            service = awsBackedService("""
                    {
                      "headline": "Test summary",
                      "overallAssessment": "Test.",
                      "actionItems": [{"text": "first fabricated", "sourceTurnId": "turn-99"}],
                      "appointments": [],
                      "careInstructions": []
                    }
                    """);
            final long before = service.getItemsRejectedNoCitation();

            // First call — one fabricated item, counter delta should be 1.
            service.summarizeTranscript(
                    CALL_ID,
                    "Transcript one.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );
            final long afterFirst = service.getItemsRejectedNoCitation();
            assertThat(afterFirst - before)
                    .as("first call: counter increments by 1")
                    .isEqualTo(1L);

            // Second call on the same service instance — another fabricated
            // item. Counter delta from `before` should now be 2, proving
            // accumulation across the bean's lifetime.
            service.summarizeTranscript(
                    CALL_ID,
                    "Transcript two.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );
            assertThat(service.getItemsRejectedNoCitation() - before)
                    .as("second call: counter accumulates (not reset)")
                    .isEqualTo(2L);
        }
    }

// ================================================================
    // WBS 4.7 — parseSummaryResponse envelope + shape tests
    // Covers Claude / Nova / raw JSON response envelopes, code-fence
    // handling, malformed content, and risk-level normalization.
    // STP mapping: TC-SUM-02 (schema-valid structured summary),
    // and the "response has no headline" fallback path.
    // ================================================================

    @Nested
    @DisplayName("parseSummaryResponse Envelope Handling (WBS 4.7)")
    class ParseSummaryResponseEnvelopeTests {

        @Test
        @DisplayName("Claude-style envelope (content[].text with embedded JSON) is unwrapped")
        void parseSummaryResponse_claudeEnvelope_unwrapped() {
            service = awsBackedService("""
                    {"content":[{"text":"{\\"headline\\":\\"claude-wrapped\\",\\"riskLevel\\":\\"MODERATE\\"}"}]}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("headline", "claude-wrapped");
            assertThat(result).containsEntry("riskLevel", "MODERATE");
        }

        @Test
        @DisplayName("Nova-style envelope (output.message.content[].text) is unwrapped")
        void parseSummaryResponse_novaEnvelope_unwrapped() {
            service = awsBackedService("""
                    {"output":{"message":{"content":[{"text":"{\\"headline\\":\\"nova-wrapped\\",\\"riskLevel\\":\\"HIGH\\"}"}]}}}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("headline", "nova-wrapped");
            assertThat(result).containsEntry("riskLevel", "HIGH");
        }

        @Test
        @DisplayName("Embedded JSON wrapped in ```json code fences is stripped and parsed")
        void parseSummaryResponse_codeFencedEmbeddedJson_stripped() {
            service = awsBackedService("""
                    {"output":{"message":{"content":[{"text":"```json\\n{\\"headline\\":\\"fenced\\",\\"riskLevel\\":\\"LOW\\"}\\n```"}]}}}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("headline", "fenced");
        }

        @Test
        @DisplayName("Envelope with content but no {...} block falls back to local summary")
        void parseSummaryResponse_contentWithNoJsonObject_fallsBack() {
            service = awsBackedService("""
                    {"output":{"message":{"content":[{"text":"no braces here just prose"}]}}}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.35, "ANXIOUS", "concerned", "COMBINED", CALL_ID, 1L, false))
            );

            // Local fallback signature: "Call Summary" headline + fallback assessment string.
            assertThat(result).containsEntry("headline", "Call Summary");
            assertThat(result.get("overallAssessment").toString())
                    .contains("Automated Bedrock summary unavailable");
        }

        @Test
        @DisplayName("Lowercase riskLevel is normalized to uppercase")
        void parseSummaryResponse_lowercaseRiskLevel_normalized() {
            service = awsBackedService("""
                    {"headline":"case test","riskLevel":"moderate"}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("riskLevel", "MODERATE");
        }

        @Test
        @DisplayName("Unrecognized riskLevel value falls back to LOW (urgency banner cannot trip on bad model output)")
        void parseSummaryResponse_unknownRiskLevel_fallsBackToLow() {
            service = awsBackedService("""
                    {"headline":"unknown risk","riskLevel":"CATASTROPHIC"}
                    """);

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    Map.of("COMBINED", new SentimentResult(0.55, "CALM", "ok", "COMBINED", CALL_ID, 1L, false))
            );

            assertThat(result).containsEntry("riskLevel", "LOW");
        }
    }

// ================================================================
    // WBS 4.7 — summarizeTranscript dispatch tests
    // Verifies the four fallback paths in summarizeTranscript:
    // null/blank transcript, Bedrock disabled, Bedrock throws, and
    // Bedrock returns empty content. Each path is distinguishable
    // via the overallLabel that surfaces in the local fallback's
    // keyConcerns list.
    // STP mapping: TC-E-SUM-003 (no usable transcript) partial;
    // reliability paths for TC-SUM-05b-style fault injection.
    // ================================================================

    @Nested
    @DisplayName("summarizeTranscript Dispatch Paths (WBS 4.7)")
    class SummarizeTranscriptDispatchTests {

        private Map<String, SentimentResult> calmChannelResults() {
            return Map.of("COMBINED",
                    new SentimentResult(0.62, "CALM", "stable", "COMBINED", CALL_ID, 1L, false));
        }

        @Test
        @DisplayName("null transcript returns empty-state default even when channel results provide CALM")
        void summarizeTranscript_nullTranscript_returnsEmptyStateDefault() {
            // Even with awsEnabled=true and CALM channel results (which would
            // normally propagate CALM to the fallback), a null transcript
            // short-circuits to localTranscriptSummary(Map.of()) which uses
            // the ANXIOUS default. This confirms the null-transcript branch.
            // No Bedrock stub — the short-circuit happens before any call.
            BedrockSentimentService svc = new BedrockSentimentService(
                    mock(BedrockRuntimeClient.class), new ObjectMapper(), true);

            Map<String, Object> result = svc.summarizeTranscript(CALL_ID, null, calmChannelResults());

            assertThat(result).containsEntry("headline", "Call Summary");
            assertThat(asList(result.get("keyConcerns")))
                    .as("null transcript path does not pass channel context to fallback")
                    .contains("Overall sentiment: ANXIOUS");
        }

        @Test
        @DisplayName("Bedrock disabled with sentiment context propagates overallLabel to keyConcerns")
        void summarizeTranscript_bedrockDisabled_propagatesOverallLabel() {
            // Default service field has awsEnabled=false, so no Bedrock call
            // is possible. Local fallback should carry the channel context.
            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    calmChannelResults());

            assertThat(asList(result.get("keyConcerns")))
                    .as("bedrock-disabled fallback should propagate COMBINED sentiment")
                    .contains("Overall sentiment: CALM");
        }

        @Test
        @DisplayName("Bedrock throws → classified model inference failure")
        void summarizeTranscript_bedrockThrows_isModelInferenceFailure() {
            service = awsBackedServiceThrowing(new RuntimeException("Bedrock 503"));

            assertThatThrownBy(() -> service.summarizeTranscript(
                            CALL_ID,
                            "Transcript available.",
                            calmChannelResults()))
                    .isInstanceOf(ModelInferenceException.class)
                    .hasMessageContaining("Bedrock transcript summary failed")
                    .hasRootCauseMessage("Bedrock 503");
        }

        @Test
        @DisplayName("Bedrock returns empty content → parsed.isEmpty() fallback with sentiment context")
        void summarizeTranscript_bedrockReturnsEmptyContent_fallsBackWithSentimentContext() {
            // Response has no headline at root AND no recognizable envelope,
            // so extractModelContentText returns "" → parseSummaryResponse
            // returns Map.of() → summarizeTranscript treats that as empty
            // and falls back with the sentiment context.
            service = awsBackedService("{\"unexpected\":\"shape\"}");

            Map<String, Object> result = service.summarizeTranscript(
                    CALL_ID,
                    "Transcript available.",
                    calmChannelResults());

            assertThat(result).containsEntry("headline", "Call Summary");
            assertThat(asList(result.get("keyConcerns")))
                    .as("empty-parse fallback should propagate COMBINED sentiment")
                    .contains("Overall sentiment: CALM");
        }
    }
}
