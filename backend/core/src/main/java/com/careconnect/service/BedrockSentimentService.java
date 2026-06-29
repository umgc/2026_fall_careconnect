package com.careconnect.service;

import com.careconnect.ai.bedrock.BedrockModelSupport;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import software.amazon.awssdk.core.SdkBytes;
import software.amazon.awssdk.services.bedrockruntime.BedrockRuntimeClient;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelRequest;
import software.amazon.awssdk.services.bedrockruntime.model.InvokeModelResponse;

/**
 * BedrockSentimentService — real-time sentiment analysis during video calls.
 *
 * <p>Three analysis modes:
 *
 * <p>TEXT — analyzes transcript text with local heuristics Input: plain text string
 *
 * <p>VOICE — analyzes voice activity metrics from Chime Input: average level, speech ratio,
 * variability
 *
 * <p>VIDEO — analyzes facial expressions and visual emotional cues Input: base64-encoded image
 * frame (JPEG/PNG) Uses: Nova Pro model (image-capable, already validated)
 *
 * <p>All three return a SentimentResult with: - score: 0.0 (very negative) to 1.0 (very positive) -
 * label: POSITIVE / NEUTRAL / NEGATIVE / DISTRESSED / ANXIOUS / CALM - notes: brief clinical
 * observation from the model - channel: TEXT / VOICE / VIDEO / COMBINED
 */
@Slf4j
@Service
public class BedrockSentimentService {

  private static final String CHANNEL_TEXT = "TEXT";
  private static final String CHANNEL_VOICE = "VOICE";
  private static final String CHANNEL_VIDEO = "VIDEO";
  private static final String CHANNEL_COMBINED = "COMBINED";
  private static final String DEFAULT_OVERALL_LABEL = "ANXIOUS";
  private static final double NEUTRAL_SCORE = 0.5;
  private static final double VOICE_WEIGHT = 0.50;
  private static final double VIDEO_WEIGHT = 0.50;
  private static final int DEFAULT_MAX_TOKENS = 200;
  private static final int SUMMARY_MAX_TOKENS = 1500;
  private static final int SUMMARY_LIST_LIMIT = 6;
  private static final int SUMMARY_HEADLINE_MAX_LEN = 80;
  private static final int SUMMARY_TEXT_MAX_LEN = 280;
  private static final int SUMMARY_NARRATIVE_MAX_LEN = 800;
  private static final int SUMMARY_ITEM_MAX_LEN = 140;
  private static final String DEFAULT_RISK_LEVEL = "LOW";
  private static final String DEFAULT_SOURCE_TURN_ID = "transcript";
  private static final double DEFAULT_ITEM_CONFIDENCE = 0.5;
  /** Score rounding multiplier — two decimal places. */
  private static final double ROUND_TWO_DECIMALS = 100.0;
  /** Score rounding multiplier — three decimal places. */
  private static final double ROUND_THREE_DECIMALS = 1000.0;
  /** Notes cleanup max character length. */
  private static final int NOTES_MAX_LEN = 120;
  /** Heuristic positive score step per matching keyword. */
  private static final double HEURISTIC_POS_STEP = 0.09;
  /** Heuristic negative score step per matching keyword. */
  private static final double HEURISTIC_NEG_STEP = 0.08;
  /** Heuristic severe distress score step per matching keyword. */
  private static final double HEURISTIC_SEVERE_STEP = 0.12;
  /** Floor score applied when positive dominates and no severe hits. */
  private static final double HEURISTIC_POS_FLOOR = 0.58;
  /** Ceiling score applied when negative dominates. */
  private static final double HEURISTIC_NEG_CEIL = 0.45;
  /** Amplification factor applied to move scores away from neutral. */
  private static final double HEURISTIC_AMPLIFY_FACTOR = 1.45;
  /** Score threshold above which the label is CALM. */
  private static final double SCORE_THRESHOLD_CALM = 0.60;
  /** Score threshold above which the label is ANXIOUS (below CALM). */
  private static final double SCORE_THRESHOLD_ANXIOUS = 0.35;
  /** Score threshold above which voice activity is VERY_HIGH. */
  private static final double VOICE_VERY_HIGH_THRESHOLD = 0.75;
  /** Score threshold above which voice activity is HIGH. */
  private static final double VOICE_HIGH_THRESHOLD = 0.55;
  /** Score threshold above which voice activity is MODERATE. */
  private static final double VOICE_MODERATE_THRESHOLD = 0.30;

  /**
   * Bedrock model ID resolved from application properties. Falls through:
   *   1. {@code aws.bedrock.sentiment.model-id} (per-service override)
   *   2. {@code careconnect.ai.model} (team-wide AI model setting)
   *   3. {@code amazon.nova-pro-v1:0} (final fallback)
   * Supports both Amazon Nova and Anthropic Claude families via
   * {@link BedrockModelSupport}.
   *
   * <p>The Java field initializer ({@code = "amazon.nova-pro-v1:0"}) is
   * required so the field is not null when this service is constructed
   * outside Spring (for example in unit tests that bypass DI). Spring's
   * {@code @Value} resolution runs after the constructor and overrides
   * this initializer in production.
   */
  @Value("${aws.bedrock.sentiment.model-id:${careconnect.ai.model:amazon.nova-pro-v1:0}}")
  private String bedrockModelId = "amazon.nova-pro-v1:0";

  /** Default temperature for Bedrock invocations. */
  private static final double DEFAULT_TEMPERATURE = 0.2;

  /** Default topP for Bedrock invocations. */
  private static final double DEFAULT_TOP_P = 0.9;

  /**
   * Nova family fallback model ID used by the image+text dispatch when the
   * configured {@link #bedrockModelId} resolves to a non-Nova model (for
   * example Anthropic Claude). The Nova-format payload built by
   * {@link #invokeNovaImageRequest} can only be processed by Nova models,
   * so image requests in Claude-default environments are routed here to
   * keep the video sentiment path working. Per-PR review with Kodi
   * (2026-06-28).
   */
  private static final String NOVA_PRO_FALLBACK_MODEL_ID = "amazon.nova-pro-v1:0";

  private final BedrockRuntimeClient bedrockRuntimeClient;
  private final ObjectMapper objectMapper;
  private final boolean awsEnabled;

  /** Creates the sentiment service with optional AWS Bedrock support. */
  @Autowired
  public BedrockSentimentService(
      @Autowired(required = false) final BedrockRuntimeClient bedrockRuntimeClient,
      final ObjectMapper objectMapper,
      @Value("${careconnect.aws.enabled:true}") final boolean awsEnabled) {
    this.bedrockRuntimeClient = bedrockRuntimeClient;
    this.objectMapper = objectMapper;
    this.awsEnabled = awsEnabled;
  }

  // ================================================================
  // TEXT SENTIMENT
  // Analyzes transcript text captured during the call
  // ================================================================

  /**
   * Analyzes the emotional tone of a text message. Called whenever a chat message is sent during a
   * call.
   */
  public final SentimentResult analyzeText(final String text, final String callId) {
    if (log.isDebugEnabled()) {
      log.debug("Analyzing text sentiment for callId: {}", callId);
    }
    final String input = text == null ? "" : text.trim();
    if (input.isBlank()) {
      return SentimentResult.neutral(CHANNEL_TEXT, callId, "Empty transcript");
    }

    if (!isBedrockAvailable()) {
      return analyzeTranscriptHeuristic(input, callId);
    }

    final String prompt =
        """
        You are a clinical transcript sentiment analyzer for a healthcare video call.
        Assess patient emotional state from this transcript text.

        Transcript: "$TRANSCRIPT$"

        Scoring guidance:
        - 0.00-0.24: severe distress / crisis language
        - 0.25-0.39: anxious / worsening / strong negative symptoms
        - 0.40-0.52: neutral / mixed / unclear sentiment
        - 0.53-0.64: calm / stable / mild positive recovery language
        - 0.65-1.00: clearly positive / improving / reassured

        Return ONLY JSON:
        {
          "score": <0.0-1.0>,
          "label": "<POSITIVE|NEUTRAL|NEGATIVE|DISTRESSED|ANXIOUS|CALM>",
          "notes": "<max 10 words>"
        }
        """
            .replace("$TRANSCRIPT$", input);

    try {
      final String responseBody = invokeBedrockModel(prompt, null, null);
      final SentimentResult parsed = parseSentimentResponse(responseBody, CHANNEL_TEXT, callId);
      if (parsed != null && !parsed.fallback()) {
        return parsed;
      }
      return analyzeTranscriptHeuristic(input, callId);
    } catch (Exception e) {
      if (log.isWarnEnabled()) {
        log.warn(
            "Bedrock text sentiment failed, using heuristic fallback for callId {}: {}",
            callId,
            e.getMessage());
      }
      return analyzeTranscriptHeuristic(input, callId);
    }
  }

  /**
   * Analyzes voice activity metrics captured from Amazon Chime.
   *
   * @param callId the active call session ID
   * @param averageLevel average audio level reported by Chime (0.0–1.0)
   * @param speechRatio ratio of speech frames to total frames (0.0–1.0)
   * @param variability audio level variability / jitter measure (0.0–1.0)
   * @return a {@link SentimentResult} for the VOICE channel
   */
  public final SentimentResult analyzeVoiceFromChimeMetrics(
      final String callId,
      final Double averageLevel,
      final Double speechRatio,
      final Double variability) {
    if (averageLevel == null || speechRatio == null || variability == null) {
      return SentimentResult.neutral(CHANNEL_VOICE, callId, "Insufficient Chime voice metrics");
    }

    final double level = clamp(averageLevel, 0.0, 1.0);
    final double speaking = clamp(speechRatio, 0.0, 1.0);
    final double jitter = clamp(variability, 0.0, 1.0);

    // Raw mode: plot direct Chime voice activity without heuristic filtering.
    // We use speechRatio as the voice score source-of-truth for trending.
    double score = speaking;

    score = clamp(score, 0.0, 1.0);
    final String label = voiceActivityLabel(score);
    final String notes =
        String.format(
            Locale.ROOT,
            "Raw Chime metrics level=%.2f speech=%.2f var=%.2f",
            level,
            speaking,
            jitter);

    return new SentimentResult(
        Math.round(score * 100.0) / 100.0,
        label,
        notes,
        CHANNEL_VOICE,
        callId,
        System.currentTimeMillis(),
        false);
  }

  // ================================================================
  // VIDEO SENTIMENT
  // Analyzes facial expressions and visual emotional cues from a frame
  // ================================================================

  /**
   * Analyzes facial expressions and visual emotional cues from a video frame.
   *
   * @param imageBase64 base64-encoded image (JPEG or PNG, single frame)
   * @param imageFormat "jpeg" or "png"
   * @param callId the active call session ID
   */
  public final SentimentResult analyzeVideoFrame(
      final String imageBase64,
      final String imageFormat,
      final String callId) {
    if (log.isDebugEnabled()) {
      log.debug("Analyzing video frame sentiment for callId: {}", callId);
    }

    if (!isBedrockAvailable()) {
      return SentimentResult.neutral(CHANNEL_VIDEO, callId, "Bedrock disabled in local mode");
    }

    final String prompt =
        """
You are a clinical facial expression analyzer for a healthcare platform.
Analyze this video frame for emotional and wellbeing cues.

Focus on:
- Facial expression (smile, frown, neutral, grimace, tense)
- Eye contact and engagement
- Visible signs of discomfort, pain, fatigue, or distress
- Overall emotional state

This is for clinical monitoring — be precise and objective.

Respond with ONLY a JSON object in this exact format, no other text:
{
  "score": <number between 0.0 and 1.0 where 0=very distressed, 0.5=neutral, 1.0=very positive>,
  "label": "<one of: POSITIVE, NEUTRAL, NEGATIVE, DISTRESSED, ANXIOUS, CALM>",
  "notes": "<one brief clinical observation about visible emotional state, max 10 words>"
}
        """;

    try {
      final String responseBody = invokeBedrockModel(prompt, imageBase64, imageFormat);
      return parseSentimentResponse(responseBody, CHANNEL_VIDEO, callId);
    } catch (Exception e) {
      if (log.isErrorEnabled()) {
        log.error("Video sentiment analysis failed for callId: {}", callId, e);
      }
      return SentimentResult.neutral(CHANNEL_VIDEO, callId, "Video analysis unavailable");
    }
  }

  // ================================================================
  // COMBINED SENTIMENT
  // Aggregates all three channels into a single overall score
  // Called periodically during a call to update the live graph
  // ================================================================

  /** Combines voice and video sentiment into an overall score. Weights: voice 50%, video 50% */
  public final Map<String, Object> buildCombinedSentiment(
      final SentimentResult textResult,
      final SentimentResult voiceResult,
      final SentimentResult videoResult,
      final String callId) {

    final double voiceWeight = VOICE_WEIGHT;
    final double videoWeight = VIDEO_WEIGHT;

    final SentimentResult effectiveText = textResult == null
        ? SentimentResult.neutral(CHANNEL_TEXT, callId, "Transcript channel disabled")
        : textResult;
    final SentimentResult effectiveVoice = voiceResult == null
        ? SentimentResult.neutral(CHANNEL_VOICE, callId, "No voice sample")
        : voiceResult;
    final SentimentResult effectiveVideo = videoResult == null
        ? SentimentResult.neutral(CHANNEL_VIDEO, callId, "No video sample")
        : videoResult;

    final boolean hasVoiceSample = !effectiveVoice.fallback();
    final boolean hasVideoSample = !effectiveVideo.fallback();

    final double activeWeightSum =
        (hasVoiceSample ? voiceWeight : 0.0) + (hasVideoSample ? videoWeight : 0.0);

    double effectiveVoiceWeight = 0.0;
    double effectiveVideoWeight = 0.0;
    if (activeWeightSum > 0.0) {
      effectiveVoiceWeight = hasVoiceSample ? voiceWeight / activeWeightSum : 0.0;
      effectiveVideoWeight = hasVideoSample ? videoWeight / activeWeightSum : 0.0;
    }

    final double textContribution = 0.0;
    final double voiceContribution = effectiveVoice.score() * effectiveVoiceWeight;
    final double videoContribution = effectiveVideo.score() * effectiveVideoWeight;

    // Missing/fallback channels are excluded from combined math.
    final double combined =
        activeWeightSum > 0.0
            ? textContribution + voiceContribution + videoContribution
            : NEUTRAL_SCORE;

    final String overallLabel = scoreToLabel(combined);

    final Map<String, Object> result = new HashMap<>();
    result.put("callId", callId);
    result.put("timestamp", System.currentTimeMillis());
    result.put(
        "overall",
        Map.of("score", Math.round(combined * ROUND_TWO_DECIMALS) / ROUND_TWO_DECIMALS,
            "label", overallLabel));
    result.put(
        "text",
        Map.of(
            "score", effectiveText.score(),
            "label", effectiveText.label(),
            "notes", effectiveText.notes()));
    result.put(
        "voice",
        Map.of(
            "score",
            effectiveVoice.score(),
            "label",
            effectiveVoice.label(),
            "notes",
            effectiveVoice.notes()));
    result.put(
        "video",
        Map.of(
            "score",
            effectiveVideo.score(),
            "label",
            effectiveVideo.label(),
            "notes",
            effectiveVideo.notes()));

    // Temporary debug fields to tune score calibration from real call data.
    result.put("dbgTs", round2(effectiveText.score()));
    result.put("dbgVs", round2(effectiveVoice.score()));
    result.put("dbgIs", round2(effectiveVideo.score()));
    result.put("dbgTw", round3(0.0));
    result.put("dbgVw", round3(effectiveVoiceWeight));
    result.put("dbgIw", round3(effectiveVideoWeight));
    result.put("dbgTc", round3(textContribution));
    result.put("dbgVc", round3(voiceContribution));
    result.put("dbgIc", round3(videoContribution));
    result.put("dbgCf", round2(activeWeightSum));

    return result;
  }

  /** Computes the final overall sentiment for a call from channel results. */
  public final SentimentResult analyzeFinalOverallSentiment(
      final String callId, final Map<String, SentimentResult> channelResults) {
    final SentimentResult voice = safeChannelResult(channelResults, CHANNEL_VOICE, callId);
    final SentimentResult video = safeChannelResult(channelResults, CHANNEL_VIDEO, callId);

    if (!isBedrockAvailable()) {
      return localFinalOverall(voice, video, callId);
    }

    final String prompt =
        """
        You are a clinical sentiment aggregator for a healthcare call summary.
        Use the channel scores and notes below to compute one final overall sentiment.

        VOICE: score=$VOICE_SCORE$, label=$VOICE_LABEL$, notes=$VOICE_NOTES$
        VIDEO: score=$VIDEO_SCORE$, label=$VIDEO_LABEL$, notes=$VIDEO_NOTES$

        Return ONLY JSON with keys score,label,notes.
        score must be 0.0 to 1.0 and represent the overall patient state.
        label must be one of CALM, ANXIOUS, DISTRESSED.
        notes must be concise (max 12 words).
        """
            .replace("$VOICE_SCORE$", String.valueOf(voice.score()))
            .replace("$VOICE_LABEL$", String.valueOf(voice.label()))
            .replace("$VOICE_NOTES$", safeNotes(voice.notes()))
            .replace("$VIDEO_SCORE$", String.valueOf(video.score()))
            .replace("$VIDEO_LABEL$", String.valueOf(video.label()))
            .replace("$VIDEO_NOTES$", safeNotes(video.notes()));

    try {
      final String responseBody = invokeBedrockModel(prompt, null, null);
      final SentimentResult parsed = parseSentimentResponse(responseBody, CHANNEL_COMBINED, callId);
      if (parsed == null || parsed.fallback()) {
        return localFinalOverall(voice, video, callId);
      }
      return new SentimentResult(
          parsed.score(),
          alignLabelWithScore(normalizeCombinedLabel(parsed.label()), parsed.score()),
          parsed.notes(),
          CHANNEL_COMBINED,
          callId,
          System.currentTimeMillis(),
          false);
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn(
            "Final overall Bedrock analysis failed for callId {}: {}", callId, ex.getMessage());
      }
      return localFinalOverall(voice, video, callId);
    }
  }

  /** Builds a structured transcript summary using available sentiment context. */
  public final Map<String, Object> summarizeTranscript(
      final String callId,
      final String transcript,
      final Map<String, SentimentResult> channelResults) {
    final String transcriptInput = transcript == null ? "" : transcript.trim();
    if (transcriptInput.isBlank()) {
      return localTranscriptSummary(Map.of());
    }

    final SentimentResult voice = safeChannelResult(channelResults, CHANNEL_VOICE, callId);
    final SentimentResult video = safeChannelResult(channelResults, CHANNEL_VIDEO, callId);
    final SentimentResult combined = safeChannelResult(channelResults, CHANNEL_COMBINED, callId);

    if (!isBedrockAvailable()) {
      return localTranscriptSummary(
          Map.of(
              "voiceLabel", voice.label(),
              "videoLabel", video.label(),
              "overallLabel", combined.label()));
    }

    final String prompt = buildCombinedSummaryPrompt(transcriptInput, voice, video, combined);

    try {
      final String responseBody = invokeBedrockModel(prompt, null, null, SUMMARY_MAX_TOKENS);
      final Map<String, Object> parsed = parseSummaryResponse(responseBody);
      if (parsed.isEmpty()) {
        return localTranscriptSummary(
            Map.of(
                "voiceLabel", voice.label(),
                "videoLabel", video.label(),
                "overallLabel", combined.label()));
      }
      return parsed;
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn("Bedrock transcript summary failed for callId {}: {}", callId, ex.getMessage());
      }
      return localTranscriptSummary(
          Map.of(
              "voiceLabel", voice.label(),
              "videoLabel", video.label(),
              "overallLabel", combined.label()));
    }
  }

  /**
   * Builds the prompt for the combined-schema summary. The schema preserves
   * the legacy flat fields (headline, overallAssessment, keyConcerns,
   * recommendedActions, followUpQuestions) for backward compatibility with
   * existing consumers, and adds the v2 SOAP + safety-engineered fields:
   * narrative, summaryConfidence, riskLevel, urgencyBanner, soap,
   * clinicalObservations, icdTags, and three typed item arrays
   * (actionItems, appointments, careInstructions). Each item carries a
   * confidence and a source citation; itemId and needsConfirmation are
   * assigned server-side after parsing so the model cannot bypass either.
   */
  private String buildCombinedSummaryPrompt(
      final String transcript,
      final SentimentResult voice,
      final SentimentResult video,
      final SentimentResult combined) {
    return """
        You are a HIPAA-safe clinical call summarizer for a caregiver dashboard.
        Read the call transcript and produce a structured summary that supports
        both clinical review (SOAP fields, risk level) and patient-friendly
        action tracking (typed action items, appointments, and care
        instructions, each with a confidence score and a citation back to the
        supporting transcript content).

        Call transcript:
        $TRANSCRIPT$

        Sentiment context:
        - voiceLabel: $VOICE_LABEL$, voiceScore: $VOICE_SCORE$
        - videoLabel: $VIDEO_LABEL$, videoScore: $VIDEO_SCORE$
        - overallLabel: $OVERALL_LABEL$, overallScore: $OVERALL_SCORE$

        Rules:
        - Output ONLY valid JSON matching the schema below; no commentary.
        - For every action item, appointment, and care instruction include a
          confidence score between 0.0 and 1.0 reflecting how clearly the
          transcript supports the extracted item.
        - For every action item, appointment, and care instruction include a
          sourceTurnId pointing to the supporting transcript content. When the
          transcript is not turn-segmented, use the value "transcript".
        - Do NOT include itemId or needsConfirmation fields on items; those
          are assigned server-side.
        - Do not fabricate detail that is not in the transcript. If a field is
          unclear, leave a string empty or an array empty rather than guessing.
        - Care-instruction type values must be one of: "medication",
          "procedure", or "instruction".
        - Risk level must be one of: "HIGH", "MODERATE", or "LOW".
        - urgencyBanner.show must be true only when an emergency action is
          warranted; otherwise false with an empty message and empty actions.

        Return ONLY valid JSON in this exact shape:
        {
          "headline": "short title, max 8 words",
          "overallAssessment": "1-2 concise clinical sentences",
          "narrative": "3-5 plain-language sentences recapping the call",
          "summaryConfidence": 0.0,
          "riskLevel": "LOW",
          "urgencyBanner": {
            "show": false,
            "message": "",
            "actions": []
          },
          "keyConcerns": ["concern phrase"],
          "recommendedActions": ["action phrase"],
          "followUpQuestions": ["follow-up question"],
          "soap": {
            "subjective": "patient-reported symptoms",
            "objective": ["observable fact"],
            "assessment": "clinical synthesis with risk rationale",
            "plan": {
              "emergency": [],
              "medications": [],
              "appointments": [],
              "monitoring": [],
              "safety": []
            }
          },
          "clinicalObservations": {
            "acuteRedFlags": [],
            "symptomCharacterization": [],
            "functionalStatus": [],
            "cognitiveBehavioral": [],
            "medicationRelated": [],
            "caregiverSignals": []
          },
          "icdTags": [],
          "actionItems": [
            {
              "text": "action description",
              "actor": "care_recipient",
              "dueHint": "natural-language due hint",
              "confidence": 0.0,
              "sourceTurnId": "transcript"
            }
          ],
          "appointments": [
            {
              "date": "YYYY-MM-DD",
              "time": "HH:mm",
              "with": "person or role",
              "purpose": "short purpose",
              "confidence": 0.0,
              "sourceTurnId": "transcript"
            }
          ],
          "careInstructions": [
            {
              "type": "medication",
              "text": "instruction text",
              "confidence": 0.0,
              "sourceTurnId": "transcript"
            }
          ]
        }
        """
        .replace("$TRANSCRIPT$", transcript)
        .replace("$VOICE_LABEL$", String.valueOf(voice.label()))
        .replace("$VOICE_SCORE$", String.valueOf(voice.score()))
        .replace("$VIDEO_LABEL$", String.valueOf(video.label()))
        .replace("$VIDEO_SCORE$", String.valueOf(video.score()))
        .replace("$OVERALL_LABEL$", String.valueOf(combined.label()))
        .replace("$OVERALL_SCORE$", String.valueOf(combined.score()));
  }

  // ================================================================
  // PRIVATE — AWS BEDROCK INVOCATION
  // ================================================================

  /**
   * Invokes the configured Bedrock model (Nova or Claude family) for text or
   * image+text analysis with the default token budget. Delegates to the
   * 4-arg overload, which handles per-family payload dispatch via
   * {@link BedrockModelSupport}.
   */
  private String invokeBedrockModel(
      final String prompt,
      final String imageBase64,
      final String imageFormat)
      throws Exception {
    return invokeBedrockModel(prompt, imageBase64, imageFormat, DEFAULT_MAX_TOKENS);
  }

  /**
   * Invokes the configured Bedrock model with an explicit token budget.
   * Routes the request through {@link BedrockModelSupport} which builds the
   * payload in the format expected by the resolved model family (Amazon
   * Nova vs. Anthropic Claude). Used by the summary pipeline, which needs
   * more output room than the per-sample sentiment classification calls.
   *
   * <p>Image+text requests use the manual Nova-format payload built by
   * {@link #invokeNovaImageRequest} because {@link BedrockModelSupport
   * #buildInvokePayload} is text-only. To keep the Nova-format payload
   * compatible with the endpoint it is sent to, image requests are routed
   * to the resolved model when it is a Nova family member, and to
   * {@link #NOVA_PRO_FALLBACK_MODEL_ID} otherwise (for example when the
   * configured {@code bedrockModelId} resolves to Claude). Text-only
   * requests follow the configured model with no fallback.
   */
  private String invokeBedrockModel(
      final String prompt,
      final String imageBase64,
      final String imageFormat,
      final int maxTokens)
      throws Exception {
    final String resolvedModelId = BedrockModelSupport.resolveModelId(null, bedrockModelId);
    final boolean hasImage = imageBase64 != null && imageFormat != null;
    final int promptChars = prompt == null ? 0 : prompt.length();

    // Production-debugging signal per Dominique's PR review: which model
    // family handled this invocation? Log only metadata (modelId, family,
    // hasImage, prompt length) -- never the prompt itself or response body,
    // which may contain transcript content or extracted clinical PHI.
    final String modelFamily =
        BedrockModelSupport.isNovaModel(resolvedModelId)
            ? "NOVA"
            : (BedrockModelSupport.isClaudeModel(resolvedModelId) ? "CLAUDE" : "OTHER");
    if (log.isInfoEnabled()) {
      log.info(
          "Bedrock invocation: modelId={}, family={}, hasImage={}, promptChars={}",
          resolvedModelId,
          modelFamily,
          hasImage,
          promptChars);
    }

    // Image requests use the Nova-format payload (since BedrockModelSupport
    // builds text-only payloads), so the target model must be a Nova family
    // member regardless of what the team-wide AI model is set to. If the
    // resolved model is non-Nova (e.g. Claude), force the image request
    // through the Nova fallback so video sentiment continues to work in
    // Claude-default environments.
    if (hasImage) {
      final String imageModelId =
          BedrockModelSupport.isNovaModel(resolvedModelId)
              ? resolvedModelId
              : NOVA_PRO_FALLBACK_MODEL_ID;
      if (!imageModelId.equals(resolvedModelId) && log.isDebugEnabled()) {
        log.debug(
            "Image request rerouted from non-Nova model {} to Nova fallback {} (Nova-format payload requires Nova family endpoint)",
            resolvedModelId,
            imageModelId);
      }
      return invokeNovaImageRequest(imageModelId, prompt, imageBase64, imageFormat, maxTokens);
    }

    final String payloadJson = BedrockModelSupport.buildInvokePayload(
        resolvedModelId,
        prompt,
        maxTokens,
        DEFAULT_TEMPERATURE,
        DEFAULT_TOP_P,
        objectMapper);

    return invokeModelRaw(resolvedModelId, payloadJson);
  }

  /**
   * Builds and sends a Nova-format image+text request to the given model.
   * Used by {@link #invokeBedrockModel} for image+text dispatch because
   * {@link BedrockModelSupport#buildInvokePayload} is text-only and cannot
   * produce the Nova image content block.
   *
   * <p>The caller is responsible for selecting a Nova family model ID; the
   * Nova-format request body cannot be processed by Claude or other
   * non-Nova endpoints. {@link #invokeBedrockModel} routes to
   * {@link #NOVA_PRO_FALLBACK_MODEL_ID} when the configured model is
   * non-Nova so this contract is preserved.
   */
  private String invokeNovaImageRequest(
      final String modelId,
      final String prompt,
      final String imageBase64,
      final String imageFormat,
      final int maxTokens)
      throws Exception {
    final Map<String, Object> userMessage = new HashMap<>();
    userMessage.put("role", "user");
    userMessage.put(
        "content",
        List.of(
            Map.of(
                "image", Map.of("format", imageFormat, "source", Map.of("bytes", imageBase64))),
            Map.of("text", prompt)));

    final Map<String, Object> requestBody = new HashMap<>();
    requestBody.put("messages", List.of(userMessage));
    requestBody.put("inferenceConfig", Map.of("maxTokens", maxTokens));

    return invokeModel(modelId, requestBody);
  }

  private SentimentResult safeChannelResult(
      final Map<String, SentimentResult> channelResults,
      final String channel,
      final String callId) {
    if (channelResults == null) {
      return SentimentResult.neutral(channel, callId, "No channel sample");
    }
    final SentimentResult result = channelResults.get(channel);
    if (result == null) {
      return SentimentResult.neutral(channel, callId, "No channel sample");
    }
    return result;
  }

  private SentimentResult localFinalOverall(
      final SentimentResult voice,
      final SentimentResult video,
      final String callId) {
    final double voiceWeight = voice.fallback() ? 0.0 : VOICE_WEIGHT;
    final double videoWeight = video.fallback() ? 0.0 : VIDEO_WEIGHT;
    final double weightSum = voiceWeight + videoWeight;

    double score =
        weightSum > 0.0
            ? (voice.score() * voiceWeight + video.score() * videoWeight) / weightSum
            : NEUTRAL_SCORE;
    score = clamp(score, 0.0, 1.0);
    return new SentimentResult(
        Math.round(score * ROUND_TWO_DECIMALS) / ROUND_TWO_DECIMALS,
        normalizeCombinedLabel(scoreToLabel(score)),
        "Final overall sentiment from end-of-call channels",
        CHANNEL_COMBINED,
        callId,
        System.currentTimeMillis(),
        false);
  }

  private String safeNotes(final String notes) {
    if (notes == null || notes.isBlank()) {
      return "none";
    }
    final String cleaned = notes.replaceAll("\\s+", " ").trim();
    return cleaned.length() > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  private double round2(final double value) {
    return Math.round(value * 100.0) / 100.0;
  }

  private double round3(final double value) {
    return Math.round(value * 1000.0) / 1000.0;
  }

  private String normalizeCombinedLabel(final String label) {
    final String normalized = label == null ? "" : label.trim().toUpperCase(Locale.ROOT);
    return switch (normalized) {
      case "DISTRESSED", "ANXIOUS", "CALM" -> normalized;
      case "NEGATIVE" -> "DISTRESSED";
      case "NEUTRAL" -> "ANXIOUS";
      case "POSITIVE" -> "CALM";
      default -> "ANXIOUS";
    };
  }

  private String alignLabelWithScore(final String label, final double score) {
    final String expected = scoreToLabel(score);
    if (label == null || label.isBlank()) {
      return expected;
    }
    final String normalized = normalizeCombinedLabel(label);
    return normalized.equals(expected) ? normalized : expected;
  }

  private SentimentResult analyzeTranscriptHeuristic(final String text, final String callId) {
    final String input = text == null ? "" : text.trim();
    if (input.isBlank()) {
      return SentimentResult.neutral(CHANNEL_TEXT, callId, "Empty transcript");
    }

    final String normalized = input.toLowerCase(Locale.ROOT);
    final List<String> positive =
        List.of(
            "better",
            "okay",
            "good",
            "calm",
            "fine",
            "improving",
            "stable",
            "relieved",
            "comfortable",
            "rested",
            "sleeping better",
            "manageable",
            "recovering",
            "great",
            "happy",
            "thankful",
            "grateful",
            "much better",
            "doing well",
            "feeling well");
    final List<String> negative =
        List.of(
            "pain",
            "hurt",
            "anxious",
            "worried",
            "panic",
            "dizzy",
            "nausea",
            "depressed",
            "tired",
            "can't",
            "cannot",
            "worse",
            "bad",
            "awful",
            "terrible",
            "shortness of breath",
            "breathless",
            "struggling",
            "crying",
            "afraid",
            "scared",
            "not sleeping",
            "exhausted");
    final List<String> severe =
        List.of(
            "severe pain",
            "chest pain",
            "can't breathe",
            "cannot breathe",
            "panic attack",
            "very dizzy",
            "vomiting",
            "faint",
            "hopeless",
            "suicidal");

    int pos = 0;
    int neg = 0;
    for (final String token : positive) {
      if (normalized.contains(token)) {
        pos += 1;
      }
    }
    for (final String token : negative) {
      if (normalized.contains(token)) {
        neg += 1;
      }
    }

    int severeHits = 0;
    for (final String token : severe) {
      if (normalized.contains(token)) {
        severeHits += 1;
      }
    }

    double score = 0.50 + (pos * 0.09) - (neg * 0.08) - (severeHits * 0.12);

    // Keep strong directional intent visible in the final score.
    if (severeHits == 0 && pos >= neg + 2) {
      score = Math.max(score, 0.58);
    }
    if (neg >= pos + 2) {
      score = Math.min(score, 0.45);
    }

    // Increase contrast so clearly positive/negative language moves off center.
    score = amplifyAwayFromNeutral(score, 1.45);

    score = clamp(score, 0.0, 1.0);

    final String label = scoreToLabel(score);
    final String notes =
        neg > pos
            ? "Distress-oriented terms detected"
            : pos > neg ? "Positive recovery terms detected" : "Neutral transcript tone";

    return new SentimentResult(
        Math.round(score * 100.0) / 100.0,
        label,
        notes,
        CHANNEL_TEXT,
        callId,
        System.currentTimeMillis(),
        false);
  }

  private double clamp(final double value, final double min, final double max) {
    return Math.max(min, Math.min(max, value));
  }

  private double amplifyAwayFromNeutral(final double score, final double factor) {
    final double centered = score - 0.5;
    return 0.5 + (centered * factor);
  }

  /** Low-level Bedrock invocation — same pattern as the POC we validated. */
  private String invokeModel(final String modelId, final Map<String, Object> requestBody)
      throws Exception {
    final String requestJson = objectMapper.writeValueAsString(requestBody);
    return invokeModelRaw(modelId, requestJson);
  }

  /**
   * Low-level Bedrock invocation that accepts a pre-serialized JSON payload.
   * Used in conjunction with {@link BedrockModelSupport#buildInvokePayload}
   * which already returns a JSON string in the format expected by the
   * resolved model family.
   */
  private String invokeModelRaw(final String modelId, final String requestJson)
      throws Exception {
    final InvokeModelRequest request =
        InvokeModelRequest.builder()
            .modelId(modelId)
            .contentType("application/json")
            .accept("application/json")
            .body(SdkBytes.fromUtf8String(requestJson))
            .build();

    final InvokeModelResponse response = bedrockRuntimeClient.invokeModel(request);
    return response.body().asUtf8String();
  }

  // ================================================================
  // PRIVATE — RESPONSE PARSING
  // ================================================================

  /** Parses the JSON response from Bedrock into a SentimentResult. */
  private SentimentResult parseSentimentResponse(
      final String responseBody, final String channel, final String callId) {
    try {
      final JsonNode root = objectMapper.readTree(responseBody);

      // Some models may return the sentiment object directly.
      if (root.has("score") && root.has("label")) {
        return sentimentNodeToResult(root, channel, callId);
      }

      final String contentText = extractModelContentText(root);

      if (contentText == null || contentText.isBlank()) {
        if (log.isWarnEnabled()) {
          log.warn("Empty content from Bedrock for channel: {}", channel);
        }
        return SentimentResult.neutral(channel, callId, "Empty response");
      }

      final String cleaned = stripCodeFences(contentText);
      JsonNode sentiment;
      try {
        sentiment = objectMapper.readTree(cleaned);
      } catch (Exception firstParseEx) {
        final String embeddedJson = extractSentimentJsonObject(cleaned);
        if (embeddedJson == null || embeddedJson.isBlank()) {
          throw firstParseEx;
        }
        sentiment = objectMapper.readTree(embeddedJson);
      }

      return sentimentNodeToResult(sentiment, channel, callId);

    } catch (Exception e) {
      if (log.isErrorEnabled()) {
        log.error(
            "Failed to parse Bedrock sentiment response for channel {}: {}",
            channel,
            e.getMessage());
      }
      return SentimentResult.neutral(channel, callId, "Parse error");
    }
  }

  private SentimentResult sentimentNodeToResult(
      final JsonNode sentiment, final String channel, final String callId) {
    double score = sentiment.path("score").asDouble(0.5);
    String label = sentiment.path("label").asText("NEUTRAL");
    final String notes = sentiment.path("notes").asText("");

    score = Math.max(0.0, Math.min(1.0, score));
    label = alignLabelWithScore(normalizeCombinedLabel(label), score);

    return new SentimentResult(
        score, label, notes, channel, callId, System.currentTimeMillis(), false);
  }

  private String extractModelContentText(final JsonNode root) {
    // Claude-style: content[].text (at the root). Try this first because
    // Kodi's Claude rollout (PR #88) made Claude the team-wide default.
    final JsonNode claudeContent = root.path("content");
    if (claudeContent.isArray() && !claudeContent.isEmpty()) {
      final String claudeText = extractTextFromContentNode(claudeContent);
      if (!claudeText.isBlank()) {
        return claudeText;
      }
    }

    // Nova-style: output.message.content[].text
    final JsonNode novaContent = root.path("output").path("message").path("content");
    String text = extractTextFromContentNode(novaContent);
    if (!text.isBlank()) {
      return text;
    }

    // OpenAI/Mistral-style: choices[0].message.content or choices[0].text
    final JsonNode firstChoice =
        root.path("choices").isArray() && root.path("choices").size() > 0
            ? root.path("choices").get(0)
            : null;
    if (firstChoice != null && !firstChoice.isMissingNode()) {
      text = extractTextFromContentNode(firstChoice.path("message").path("content"));
      if (!text.isBlank()) {
        return text;
      }
      text = firstChoice.path("text").asText("");
      if (!text.isBlank()) {
        return text;
      }
    }

    // Common fallback fields
    text = root.path("output_text").asText("");
    if (!text.isBlank()) {
      return text;
    }
    text = root.path("completion").asText("");
    if (!text.isBlank()) {
      return text;
    }

    return "";
  }

  private String extractTextFromContentNode(final JsonNode contentNode) {
    if (contentNode == null || contentNode.isMissingNode() || contentNode.isNull()) {
      return "";
    }

    if (contentNode.isTextual()) {
      return contentNode.asText("");
    }

    if (contentNode.isArray()) {
      final StringBuilder sb = new StringBuilder();
      for (final JsonNode item : contentNode) {
        if (item == null || item.isNull() || item.isMissingNode()) {
          continue;
        }
        if (item.isTextual()) {
          final String value = item.asText("");
          if (!value.isBlank()) {
            if (sb.length() > 0) {
              sb.append('\n');
            }
            sb.append(value);
          }
          continue;
        }

        String nestedText = item.path("text").asText("");
        if (nestedText.isBlank()) {
          nestedText = item.path("output_text").asText("");
        }
        if (!nestedText.isBlank()) {
          if (sb.length() > 0) {
            sb.append('\n');
          }
          sb.append(nestedText);
        }
      }
      return sb.toString().trim();
    }

    if (contentNode.isObject()) {
      String text = contentNode.path("text").asText("");
      if (!text.isBlank()) {
        return text;
      }
      text = contentNode.path("output_text").asText("");
      if (!text.isBlank()) {
        return text;
      }
    }

    return "";
  }

  private String stripCodeFences(final String text) {
    if (text == null) {
      return "";
    }
    return text.replaceAll("```(?:json)?", "").replace("```", "").trim();
  }

  private String extractFirstJsonObject(final String text) {
    if (text == null || text.isBlank()) {
      return "";
    }
    final int start = text.indexOf('{');
    final int end = text.lastIndexOf('}');
    if (start < 0 || end < 0 || end <= start) {
      return "";
    }
    return text.substring(start, end + 1);
  }

  private String extractSentimentJsonObject(final String text) {
    if (text == null || text.isBlank()) {
      return "";
    }

    final String scoreToken = "\"score\"";
    final int scoreIndex = text.indexOf(scoreToken);
    if (scoreIndex < 0) {
      return extractFirstJsonObject(text);
    }

    final int start = text.lastIndexOf('{', scoreIndex);
    if (start < 0) {
      return extractFirstJsonObject(text);
    }

    boolean inString = false;
    boolean escaping = false;
    int depth = 0;

    for (int i = start; i < text.length(); i++) {
      char c = text.charAt(i);

      if (escaping) {
        escaping = false;
        continue;
      }

      if (c == '\\') {
        escaping = true;
        continue;
      }

      if (c == '"') {
        inString = !inString;
        continue;
      }

      if (inString) {
        continue;
      }

      if (c == '{') {
        depth += 1;
      } else if (c == '}') {
        depth -= 1;
        if (depth == 0) {
          return text.substring(start, i + 1);
        }
      }
    }

    return extractFirstJsonObject(text);
  }

  boolean containsParseableSentimentJson(final String responseBody) {
    try {
      final JsonNode root = objectMapper.readTree(responseBody);
      if (root.has("score") && root.has("label")) {
        return true;
      }

      final String contentText = extractModelContentText(root);
      if (contentText == null || contentText.isBlank()) {
        return false;
      }

      final String cleaned = stripCodeFences(contentText);
      try {
        final JsonNode parsed = objectMapper.readTree(cleaned);
        return parsed.has("score") && parsed.has("label");
      } catch (Exception firstEx) {
        final String embeddedJson = extractSentimentJsonObject(cleaned);
        if (embeddedJson == null || embeddedJson.isBlank()) {
          return false;
        }
        final JsonNode parsed = objectMapper.readTree(embeddedJson);
        return parsed.has("score") && parsed.has("label");
      }
    } catch (Exception ignored) {
      return false;
    }
  }

  private Map<String, Object> parseSummaryResponse(final String responseBody) {
    try {
      final JsonNode root = objectMapper.readTree(responseBody);
      JsonNode summaryNode = root;
      if (!root.has("headline")) {
        final String contentText = extractModelContentText(root);
        if (contentText == null || contentText.isBlank()) {
          return Map.of();
        }
        final String cleaned = stripCodeFences(contentText);
        final String embeddedJson = extractFirstJsonObject(cleaned);
        if (embeddedJson == null || embeddedJson.isBlank()) {
          return Map.of();
        }
        summaryNode = objectMapper.readTree(embeddedJson);
      }

      final Map<String, Object> out = new LinkedHashMap<>();

      // Legacy flat fields preserved for backward compatibility with the
      // current PostCallTelemetrySummaryScreen consumer.
      out.put(
          "headline",
          safeSummaryText(
              summaryNode.path("headline").asText("Call Summary"),
              SUMMARY_HEADLINE_MAX_LEN));
      out.put(
          "overallAssessment",
          safeSummaryText(
              summaryNode.path("overallAssessment").asText("Clinical summary not available."),
              SUMMARY_TEXT_MAX_LEN));
      out.put("keyConcerns", safeStringList(summaryNode.path("keyConcerns")));
      out.put("recommendedActions", safeStringList(summaryNode.path("recommendedActions")));
      out.put("followUpQuestions", safeStringList(summaryNode.path("followUpQuestions")));

      // Combined-schema additions (v2 SOAP + safety-engineered fields).
      out.put(
          "narrative",
          safeSummaryText(
              summaryNode.path("narrative").asText(""),
              SUMMARY_NARRATIVE_MAX_LEN));
      out.put("summaryConfidence", extractConfidence(summaryNode.path("summaryConfidence")));
      out.put("riskLevel", extractRiskLevel(summaryNode.path("riskLevel")));
      out.put("urgencyBanner", extractNestedObject(summaryNode.path("urgencyBanner")));
      out.put("soap", extractNestedObject(summaryNode.path("soap")));
      out.put("clinicalObservations", extractNestedObject(summaryNode.path("clinicalObservations")));
      out.put("icdTags", safeStringList(summaryNode.path("icdTags")));

      // Typed extraction items. itemId and needsConfirmation are assigned
      // server-side so the model cannot bypass the confirmation gate
      // (FR-SUM-4, REQ-SC-5).
      out.put("actionItems", extractTypedItems(summaryNode.path("actionItems")));
      out.put("appointments", extractTypedItems(summaryNode.path("appointments")));
      out.put("careInstructions", extractTypedItems(summaryNode.path("careInstructions")));

      return out;
    } catch (Exception ex) {
      if (log.isWarnEnabled()) {
        log.warn("parseSummaryResponse failed: {}", ex.getMessage());
      }
      return Map.of();
    }
  }

  /**
   * Extracts a list of typed extraction items (action items, appointments,
   * or care instructions). Server-generates {@code itemId} via
   * {@code UUID.randomUUID()} and forces {@code needsConfirmation} to true
   * on every item. Falls back to safe defaults when the model omits or
   * malforms {@code confidence} or {@code sourceTurnId}.
   */
  private List<Map<String, Object>> extractTypedItems(final JsonNode arrayNode) {
    if (arrayNode == null || !arrayNode.isArray()) {
      return List.of();
    }
    final ArrayList<Map<String, Object>> out = new ArrayList<>();
    for (final JsonNode item : arrayNode) {
      if (item == null || !item.isObject()) {
        continue;
      }
      final Map<String, Object> typed = new LinkedHashMap<>();
      typed.put("itemId", UUID.randomUUID().toString());
      final Iterator<String> fieldNames = item.fieldNames();
      while (fieldNames.hasNext()) {
        final String name = fieldNames.next();
        if ("itemId".equals(name) || "needsConfirmation".equals(name)) {
          continue;
        }
        if ("confidence".equals(name)) {
          typed.put("confidence", extractConfidence(item.path("confidence")));
        } else if ("sourceTurnId".equals(name)) {
          final String src = item.path("sourceTurnId").asText("");
          typed.put("sourceTurnId", src.isBlank() ? DEFAULT_SOURCE_TURN_ID : src);
        } else {
          final JsonNode value = item.path(name);
          if (value.isTextual()) {
            typed.put(name, safeSummaryText(value.asText(""), SUMMARY_ITEM_MAX_LEN));
          } else if (value.isArray() || value.isObject()) {
            typed.put(name, objectMapper.convertValue(value, Object.class));
          } else {
            typed.put(name, objectMapper.convertValue(value, Object.class));
          }
        }
      }
      // Force the safety fields whether or not the model produced them.
      typed.putIfAbsent("confidence", DEFAULT_ITEM_CONFIDENCE);
      typed.putIfAbsent("sourceTurnId", DEFAULT_SOURCE_TURN_ID);
      typed.put("needsConfirmation", Boolean.TRUE);
      out.add(typed);
      if (out.size() >= SUMMARY_LIST_LIMIT) {
        break;
      }
    }
    return out;
  }

  /**
   * Extracts a nested JSON object as a raw Map. Returns an empty map when the
   * node is missing or not an object. Used for {@code urgencyBanner},
   * {@code soap}, and {@code clinicalObservations}.
   */
  private Map<String, Object> extractNestedObject(final JsonNode node) {
    if (node == null || node.isMissingNode() || !node.isObject()) {
      return Map.of();
    }
    @SuppressWarnings("unchecked")
    final Map<String, Object> result = objectMapper.convertValue(node, Map.class);
    return result == null ? Map.of() : result;
  }

  /**
   * Extracts a confidence value, clamped to the range 0.0–1.0. Returns the
   * default item confidence when the node is missing or unparseable.
   */
  private double extractConfidence(final JsonNode node) {
    if (node == null || node.isMissingNode() || node.isNull()) {
      return DEFAULT_ITEM_CONFIDENCE;
    }
    final double value = node.asDouble(DEFAULT_ITEM_CONFIDENCE);
    return clamp(value, 0.0, 1.0);
  }

  /**
   * Extracts the SOAP risk level, normalizing to one of HIGH, MODERATE, or
   * LOW. Unknown values fall back to LOW so the urgency banner cannot trip
   * on bad model output.
   */
  private String extractRiskLevel(final JsonNode node) {
    if (node == null || !node.isTextual()) {
      return DEFAULT_RISK_LEVEL;
    }
    final String value = node.asText("").trim().toUpperCase(Locale.ROOT);
    return switch (value) {
      case "HIGH", "MODERATE", "LOW" -> value;
      default -> DEFAULT_RISK_LEVEL;
    };
  }

  /**
   * Produces a minimum-viable empty-state summary for the combined schema
   * when Bedrock is unavailable or returns unusable output. Populates the
   * legacy flat fields with safe defaults and leaves all combined-schema
   * fields empty so downstream consumers do not crash on missing keys.
   */
  private Map<String, Object> localTranscriptSummary(final Map<String, Object> context) {
    final String overallLabel =
        context.get("overallLabel") == null
            ? DEFAULT_OVERALL_LABEL
            : String.valueOf(context.get("overallLabel"));

    final Map<String, Object> out = new LinkedHashMap<>();
    out.put("headline", "Call Summary");
    out.put(
        "overallAssessment",
        "Automated Bedrock summary unavailable. Review transcript timeline directly.");
    out.put("keyConcerns", List.of("Overall sentiment: " + overallLabel));
    out.put("recommendedActions", List.of("Review full transcript and sentiment timeline."));
    out.put("followUpQuestions", List.of("Any symptom changes since this call?"));

    out.put("narrative", "");
    out.put("summaryConfidence", 0.0);
    out.put("riskLevel", DEFAULT_RISK_LEVEL);
    out.put(
        "urgencyBanner",
        Map.of("show", Boolean.FALSE, "message", "", "actions", List.of()));
    out.put(
        "soap",
        Map.of(
            "subjective", "",
            "objective", List.of(),
            "assessment", "",
            "plan",
                Map.of(
                    "emergency", List.of(),
                    "medications", List.of(),
                    "appointments", List.of(),
                    "monitoring", List.of(),
                    "safety", List.of())));
    out.put(
        "clinicalObservations",
        Map.of(
            "acuteRedFlags", List.of(),
            "symptomCharacterization", List.of(),
            "functionalStatus", List.of(),
            "cognitiveBehavioral", List.of(),
            "medicationRelated", List.of(),
            "caregiverSignals", List.of()));
    out.put("icdTags", List.of());
    out.put("actionItems", List.of());
    out.put("appointments", List.of());
    out.put("careInstructions", List.of());
    return out;
  }

  private List<String> safeStringList(final JsonNode node) {
    if (node == null || !node.isArray()) {
      return List.of();
    }

    final ArrayList<String> out = new ArrayList<>();
    for (final JsonNode item : node) {
      final String text = safeSummaryText(item.asText(""), SUMMARY_ITEM_MAX_LEN);
      if (!text.isBlank()) {
        out.add(text);
      }
      if (out.size() >= SUMMARY_LIST_LIMIT) {
        break;
      }
    }
    return out;
  }

  private String safeSummaryText(final String text, final int maxLen) {
    if (text == null) {
      return "";
    }
    final String cleaned = text.replaceAll("\\s+", " ").trim();
    if (cleaned.length() <= maxLen) {
      return cleaned;
    }
    return cleaned.substring(0, maxLen);
  }

  private String scoreToLabel(final double score) {
    if (score >= 0.60) {
      return "CALM";
    }
    if (score >= 0.35) {
      return "ANXIOUS";
    }
    return "DISTRESSED";
  }

  private String voiceActivityLabel(final double score) {
    if (score >= 0.75) {
      return "VERY_HIGH_ACTIVITY";
    }
    if (score >= 0.55) {
      return "HIGH_ACTIVITY";
    }
    if (score >= 0.30) {
      return "MODERATE_ACTIVITY";
    }
    return "LOW_ACTIVITY";
  }

  private boolean isBedrockAvailable() {
    return awsEnabled && bedrockRuntimeClient != null;
  }

  // ================================================================
  // RESULT RECORD
  // Immutable data object returned by all analysis methods
  // ================================================================

  /** Result of a sentiment analysis operation for one channel or combined output. */
  public record SentimentResult(
      double score, // 0.0 - 1.0
      String label, // DISTRESSED / ANXIOUS / CALM
      String notes, // brief clinical observation
      String channel, // TEXT / VOICE / VIDEO
      String callId,
      long timestamp,
      boolean fallback) {
    /** Factory method for when analysis is unavailable. */
    public static SentimentResult neutral(
        final String channel, final String callId, final String reason) {
      return new SentimentResult(
          NEUTRAL_SCORE,
          DEFAULT_OVERALL_LABEL,
          reason,
          channel,
          callId,
          System.currentTimeMillis(),
          true);
    }
  }
}
