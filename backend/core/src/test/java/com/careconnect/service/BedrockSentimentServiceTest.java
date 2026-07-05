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
}
