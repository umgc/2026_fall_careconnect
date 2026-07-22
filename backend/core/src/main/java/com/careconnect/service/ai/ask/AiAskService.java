package com.careconnect.service.ai.ask;

import com.careconnect.dto.ai.AiAnswerBlock;
import com.careconnect.dto.ai.AiAskRequest;
import com.careconnect.dto.ai.AiAskResponse;
import com.careconnect.dto.ai.AiCitation;
import com.careconnect.dto.ai.AiConfirmationHint;
import com.careconnect.dto.ai.AiDisclaimer;
import com.careconnect.dto.ai.AiErrorBlock;
import com.careconnect.dto.ai.AiEscalation;
import com.careconnect.dto.ai.AiModelMeta;
import com.careconnect.dto.ai.AiRetrievalMeta;
import com.careconnect.dto.ai.DeliveryStatus;
import com.careconnect.dto.ai.InputModality;
import com.careconnect.model.User;
import com.careconnect.model.ai.hitl.AiHeldItem;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.AskAiSafetyCopy;
import com.careconnect.service.ai.hitl.HitlService;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.HybridRetrievalResult;
import com.careconnect.service.ai.retrieval.HybridRetrievalService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.service.ai.safety.SafetyDecision;
import com.careconnect.service.ai.safety.SafetyInput;
import com.careconnect.service.ai.safety.SafetyOutcome;
import com.careconnect.service.ai.safety.SafetyPipeline;
import com.careconnect.service.security.InputSanitizationService;
import com.careconnect.service.security.LangChainGovernanceService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.ArrayList;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

/**
 * Task 5.3 — Ask AI gateway orchestrator.
 *
 * <p>JWT caller → sanitize/govern → {@link RetrievalScopeService} →
 * {@link HybridRetrievalService} → min-necessary prompt → grounded Bedrock → citations →
 * {@link SafetyPipeline} (Tier-1 deliver or Tier-2 HITL hold).
 *
 * <p>TODO(Task 6.x): persist Ask AI audit rows (requestId/auditId, scope, retrieval meta,
 * delivery status) via the Ask AI audit pipeline. Until then {@code auditId} is a
 * pre-allocated correlation id only — it does not dereference a stored record.
 */
@Service
public class AiAskService {

    private static final Logger log = LoggerFactory.getLogger(AiAskService.class);

    private static final String NO_RECORDS_EN =
            "No matching records were found for this question. "
                    + "CareConnect Ask AI only answers from your stored health records "
                    + "and cannot provide general medical advice.";
    private static final int CITATION_CONTEXT_CODE_POINTS = 80;

    private final RetrievalScopeService retrievalScopeService;
    private final HybridRetrievalService hybridRetrievalService;
    private final GroundedAskLlmService groundedAskLlmService;
    private final CitationAssembler citationAssembler;
    private final InputSanitizationService inputSanitizationService;
    private final LangChainGovernanceService governanceService;
    private final SafetyPipeline safetyPipeline;
    private final HitlService hitlService;
    private final boolean hitlEnabled;

    public AiAskService(
            final RetrievalScopeService retrievalScopeService,
            final HybridRetrievalService hybridRetrievalService,
            final GroundedAskLlmService groundedAskLlmService,
            final CitationAssembler citationAssembler,
            final InputSanitizationService inputSanitizationService,
            final LangChainGovernanceService governanceService,
            final SafetyPipeline safetyPipeline,
            final HitlService hitlService,
            @Value("${careconnect.ai.hitl.enabled:true}") final boolean hitlEnabled) {
        this.retrievalScopeService = retrievalScopeService;
        this.hybridRetrievalService = hybridRetrievalService;
        this.groundedAskLlmService = groundedAskLlmService;
        this.citationAssembler = citationAssembler;
        this.inputSanitizationService = inputSanitizationService;
        this.governanceService = governanceService;
        this.safetyPipeline = safetyPipeline;
        this.hitlService = hitlService;
        this.hitlEnabled = hitlEnabled;
    }

    /**
     * Produces a records-grounded answer or fails closed before delivery.
     *
     * @throws ForbiddenScopeException when the caller cannot retrieve the requested patient's records
     * @throws UnauthorizedException when no authenticated caller is available
     * @throws AskAiUnavailableException when grounded inference is unavailable
     * @throws AskAiGroundingException when model citations do not validate against retrieved records
     */
    public AiAskResponse ask(final User caller, final AiAskRequest request)
            throws ForbiddenScopeException, UnauthorizedException {
        if (caller == null || caller.getId() == null) {
            throw new UnauthorizedException("Authenticated user required");
        }
        if (request == null || request.patientId() == null) {
            throw new AskAiRejectedException(
                    "INVALID_REQUEST", "patientId is required", 400);
        }

        final UUID requestId = UUID.randomUUID();
        // Correlation id only until Task 6.x persists audit rows.
        final UUID auditId = UUID.randomUUID();
        final UUID sessionId = request.sessionId() != null ? request.sessionId() : UUID.randomUUID();
        final String locale = normalizeLocale(request.locale());
        final String conversationKey = request.conversationId() == null
                ? requestId.toString()
                : request.conversationId().toString();
        final String normalizedInput = AskAiTextPolicy.normalize(request.query());

        final LangChainGovernanceService.GovernanceResult governance =
                governanceService.validateRequest(caller.getId(), conversationKey, normalizedInput);
        if (!governance.isAllowed()) {
            final boolean rateLimited = "RATE_LIMIT".equals(governance.getAction());
            throw new AskAiRejectedException(
                    requestId,
                    auditId,
                    sessionId,
                    rateLimited ? "RATE_LIMITED" : "INVALID_REQUEST",
                    governance.getReason(),
                    rateLimited ? 429 : 400);
        }

        final InputSanitizationService.SanitizationResult sanitization =
                inputSanitizationService.sanitizeUserInput(
                        normalizedInput, caller.getId(), conversationKey);
        if (sanitization.isBlocked()) {
            throw new AskAiRejectedException(
                    requestId,
                    auditId,
                    sessionId,
                    "SAFETY_VALIDATION_FAILED",
                    "Query blocked by input safety checks",
                    422);
        }
        final String sanitizedQuery =
                AskAiTextPolicy.normalize(sanitization.getSanitizedContent()).trim();
        if (sanitizedQuery == null || sanitizedQuery.isBlank()) {
            throw new AskAiRejectedException(
                    requestId,
                    auditId,
                    sessionId,
                    "INVALID_REQUEST", "query must not be blank", 400);
        }

        final Set<RetrievalRecordType> requestedTypes = toTypeSet(request.sourceTypes());
        final RetrievalScope scope;
        try {
            scope = retrievalScopeService.resolveRetrievalScope(
                    caller, request.patientId(), requestedTypes);
        } catch (final ForbiddenScopeException ex) {
            throw ex.withCorrelation(
                    requestId,
                    ex.getAuditId() == null ? auditId : ex.getAuditId(),
                    sessionId);
        }

        final long retrievalStarted = System.nanoTime();
        final HybridRetrievalResult retrieval;
        try {
            retrieval = hybridRetrievalService.search(
                    scope, request.patientId(), sanitizedQuery);
        } catch (final RuntimeException ex) {
            throw new AskAiUnavailableException(
                    requestId,
                    auditId,
                    sessionId,
                    "RETRIEVAL_UNAVAILABLE",
                    "Record retrieval is temporarily unavailable",
                    ex);
        }
        final long retrievalLatencyMs = (System.nanoTime() - retrievalStarted) / 1_000_000L;

        if (retrieval == null || retrieval.isEmpty()) {
            log.debug("Ask AI NO_RECORDS requestId={}", requestId);
            return noRecordsResponse(
                    requestId, auditId, sessionId, locale, retrieval, retrievalLatencyMs);
        }

        final RetrievalContextAssembler.GroundedContext context =
                RetrievalContextAssembler.assemble(sanitizedQuery, retrieval.chunks());
        if (context.usedChunks().isEmpty()) {
            return noRecordsResponse(
                    requestId, auditId, sessionId, locale, retrieval, retrievalLatencyMs);
        }

        final long inferenceStarted = System.nanoTime();
        final Optional<GroundedAskLlmService.GroundedLlmResult> llmOpt;
        try {
            llmOpt = groundedAskLlmService.generate(
                    context.systemPrompt(), context.userPrompt());
        } catch (final GroundedOutputValidationException ex) {
            throw groundingFailure(
                    requestId,
                    auditId,
                    sessionId,
                    "Generated answer did not satisfy the grounded response contract");
        } catch (final GroundedProviderException ex) {
            final boolean configuration =
                    ex.getKind() == GroundedProviderException.Kind.CONFIGURATION;
            throw new AskAiUnavailableException(
                    requestId,
                    auditId,
                    sessionId,
                    configuration
                            ? "MODEL_CONFIGURATION_UNAVAILABLE"
                            : "MODEL_PROVIDER_UNAVAILABLE",
                    configuration
                            ? "Grounded answer generation is not configured"
                            : "Grounded answer generation is temporarily unavailable",
                    ex);
        }
        final long inferenceLatencyMs = (System.nanoTime() - inferenceStarted) / 1_000_000L;

        if (llmOpt.isEmpty()) {
            throw new AskAiUnavailableException(
                    requestId,
                    auditId,
                    sessionId,
                    "MODEL_PROVIDER_UNAVAILABLE",
                    "Grounded answer generation is temporarily unavailable",
                    null);
        }

        final GroundedAskLlmService.GroundedLlmResult llm = llmOpt.get();
        final String draftAnswer = llm.claims().stream()
                .map(GroundedAskLlmService.GroundedClaim::text)
                .filter(text -> text != null && !text.isBlank())
                .reduce((left, right) -> left + " " + right)
                .orElse("");

        final Map<String, List<String>> verifiedEvidenceByRef = new LinkedHashMap<>();
        for (final GroundedAskLlmService.GroundedClaim claim : llm.claims()) {
            final CitationAssembler.CitationResult claimCitations =
                    citationAssembler.assemble(
                            claim.citationRefs(), context.citationRefMap());
            if (claim.text() == null
                    || claim.text().isBlank()
                    || !hasExtractiveEvidence(
                            claim,
                            sanitizedQuery,
                            context.promptExcerptMap(),
                            context.citationRefMap())
                    || !claimCitations.grounded()) {
                return holdOrGroundingFailure(
                        caller,
                        request,
                        requestId,
                        auditId,
                        sessionId,
                        locale,
                        sanitizedQuery,
                        draftAnswer,
                        List.of(),
                        List.of("UNSUPPORTED_CLAIM"),
                        "Generated answer contains an unsupported factual claim",
                        retrieval,
                        context,
                        retrievalLatencyMs,
                        inferenceLatencyMs,
                        llm.modelId());
            }
            final String ref = claim.citationRefs().get(0);
            verifiedEvidenceByRef.computeIfAbsent(ref, ignored -> new ArrayList<>())
                    .add(surroundingCitationContext(
                            context.promptExcerptMap().get(ref).text(),
                            claim.evidenceByRef().get(ref)));
        }
        final CitationAssembler.CitationResult citationResult =
                citationAssembler.assembleWithEvidence(
                        llm.citationRefs(),
                        context.citationRefMap(),
                        verifiedEvidenceByRef);
        if (!citationResult.grounded()) {
            log.warn(
                    "Ask AI ungrounded citations requestId={} invalidRefCount={}",
                    requestId,
                    citationResult.invalidRefs().size());
            return holdOrGroundingFailure(
                    caller,
                    request,
                    requestId,
                    auditId,
                    sessionId,
                    locale,
                    sanitizedQuery,
                    draftAnswer,
                    citationResult.citations(),
                    List.of("UNSUPPORTED_CLAIM"),
                    "Generated answer could not be verified against retrieved records",
                    retrieval,
                    context,
                    retrievalLatencyMs,
                    inferenceLatencyMs,
                    llm.modelId());
        }
        final List<AiCitation> citations = citationResult.citations();
        final String verifiedAnswer = draftAnswer.isBlank()
                ? llm.claims().stream()
                        .map(GroundedAskLlmService.GroundedClaim::text)
                        .reduce((left, right) -> left + " " + right)
                        .orElse("")
                : draftAnswer;
        if (verifiedAnswer.isBlank()) {
            throw groundingFailure(
                    requestId,
                    auditId,
                    sessionId,
                    "Generated answer did not contain verified claims");
        }

        final SafetyOutcome safety = safetyPipeline.process(new SafetyInput(
                sanitizedQuery,
                verifiedAnswer,
                citations,
                request.patientId(),
                caller.getId(),
                sessionId,
                auditId,
                requestId,
                "ASK_AI",
                locale,
                false,
                List.of()));

        if (safety.decision() == SafetyDecision.HOLD_TIER2) {
            if (!hitlEnabled) {
                throw groundingFailure(
                        requestId,
                        auditId,
                        sessionId,
                        "Answer requires clinician review but HITL is disabled");
            }
            return heldResponse(
                    caller,
                    request,
                    requestId,
                    auditId,
                    sessionId,
                    locale,
                    sanitizedQuery,
                    verifiedAnswer,
                    citations,
                    safety,
                    retrieval,
                    context,
                    retrievalLatencyMs,
                    inferenceLatencyMs,
                    llm.modelId());
        }
        if (safety.decision() == SafetyDecision.BLOCK) {
            throw groundingFailure(
                    requestId,
                    auditId,
                    sessionId,
                    "Generated answer failed safety validation");
        }

        final InputModality modality =
                request.inputModality() == null ? InputModality.TEXT : request.inputModality();
        final String escalationLevel = safety.escalationLevel() == null
                || "none".equals(safety.escalationLevel())
                ? "tier1_auto_deliver"
                : safety.escalationLevel();
        log.debug(
                "Ask AI DELIVERED requestId={} chunks={} citations={} modality={} degraded={}",
                requestId,
                context.usedChunks().size(),
                citations.size(),
                modality,
                retrieval.vectorDegraded());

        return new AiAskResponse(
                true,
                requestId,
                auditId,
                sessionId,
                Instant.now(),
                DeliveryStatus.DELIVERED,
                1,
                false,
                null,
                new AiAnswerBlock(verifiedAnswer, locale),
                citations,
                disclaimer(locale),
                new AiEscalation(1, escalationLevel, false),
                new AiConfirmationHint(true, AskAiSafetyCopy.CONFIRM_EN),
                new AiRetrievalMeta(
                        retrieval.chunks().size(),
                        context.usedChunks().size(),
                        retrievalLatencyMs,
                        inferenceLatencyMs,
                        retrieval.vectorDegraded(),
                        new AiModelMeta("bedrock", llm.modelId())),
                null,
                null,
                null);
    }

    private AiAskResponse holdOrGroundingFailure(
            final User caller,
            final AiAskRequest request,
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String locale,
            final String query,
            final String draftAnswer,
            final List<AiCitation> citations,
            final List<String> groundingCodes,
            final String message,
            final HybridRetrievalResult retrieval,
            final RetrievalContextAssembler.GroundedContext context,
            final long retrievalLatencyMs,
            final long inferenceLatencyMs,
            final String modelId) {
        if (!hitlEnabled || draftAnswer == null || draftAnswer.isBlank()) {
            throw groundingFailure(requestId, auditId, sessionId, message);
        }
        final SafetyOutcome safety = safetyPipeline.process(new SafetyInput(
                query,
                draftAnswer,
                citations,
                request.patientId(),
                caller.getId(),
                sessionId,
                auditId,
                requestId,
                "ASK_AI",
                locale,
                true,
                groundingCodes));
        if (safety.decision() != SafetyDecision.HOLD_TIER2) {
            throw groundingFailure(requestId, auditId, sessionId, message);
        }
        return heldResponse(
                caller,
                request,
                requestId,
                auditId,
                sessionId,
                locale,
                query,
                draftAnswer,
                citations,
                safety,
                retrieval,
                context,
                retrievalLatencyMs,
                inferenceLatencyMs,
                modelId);
    }

    private AiAskResponse heldResponse(
            final User caller,
            final AiAskRequest request,
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String locale,
            final String query,
            final String draftAnswer,
            final List<AiCitation> citations,
            final SafetyOutcome safety,
            final HybridRetrievalResult retrieval,
            final RetrievalContextAssembler.GroundedContext context,
            final long retrievalLatencyMs,
            final long inferenceLatencyMs,
            final String modelId) {
        final AiHeldItem held = hitlService.createHold(
                new SafetyInput(
                        query,
                        draftAnswer,
                        citations,
                        request.patientId(),
                        caller.getId(),
                        sessionId,
                        auditId,
                        requestId,
                        "ASK_AI",
                        locale,
                        false,
                        List.of()),
                safety,
                citations);
        log.info(
                "Ask AI HELD requestId={} heldItemId={} triggers={}",
                requestId,
                held.getId(),
                safety.triggerCodes());
        return new AiAskResponse(
                true,
                requestId,
                auditId,
                sessionId,
                Instant.now(),
                DeliveryStatus.HELD,
                2,
                true,
                held.getId(),
                null,
                List.of(),
                disclaimer(locale),
                new AiEscalation(2, "hitl_hold", true),
                new AiConfirmationHint(false, null),
                new AiRetrievalMeta(
                        retrieval == null ? 0 : retrieval.chunks().size(),
                        context == null ? 0 : context.usedChunks().size(),
                        retrievalLatencyMs,
                        inferenceLatencyMs,
                        retrieval != null && retrieval.vectorDegraded(),
                        new AiModelMeta("bedrock", modelId)),
                HitlService.REVIEWING_MESSAGE,
                HitlService.pollUrl(held.getId()),
                null);
    }

    private static boolean hasExtractiveEvidence(
            final GroundedAskLlmService.GroundedClaim claim,
            final String query,
            final Map<String, RetrievalContextAssembler.PromptExcerpt> promptExcerptMap,
            final Map<String, com.careconnect.service.ai.retrieval.RankedChunk> refMap) {
        if (claim.citationRefs().size() != 1 || claim.evidenceByRef().size() != 1) {
            return false;
        }
        final String ref = claim.citationRefs().get(0);
        final RetrievalContextAssembler.PromptExcerpt excerpt = promptExcerptMap.get(ref);
        final String evidence = claim.evidenceByRef().get(ref);
        return excerpt != null
                && evidence != null
                && evidence.codePointCount(0, evidence.length()) >= 20
                && claim.text().equals(evidence)
                && isCompleteSpan(excerpt, evidence)
                && GroundingRelevancePolicy.isRelevant(
                        query, evidence, excerpt.text(), refMap.get(ref));
    }

    private static boolean isCompleteSpan(
            final RetrievalContextAssembler.PromptExcerpt excerpt,
            final String evidence) {
        final int start = excerpt.text().indexOf(evidence);
        if (start < 0 || excerpt.text().indexOf(evidence, start + 1) >= 0) {
            return false;
        }
        final int end = start + evidence.length();
        if ((start == 0 && excerpt.startTruncated())
                || (end == excerpt.text().length() && excerpt.endTruncated())) {
            return false;
        }
        return isSentenceStart(excerpt.text(), start) && isSentenceEnd(excerpt.text(), end);
    }

    private static boolean isSentenceStart(final String text, final int start) {
        if (start == 0) {
            return true;
        }
        int offset = start;
        while (offset > 0) {
            final int codePoint = text.codePointBefore(offset);
            offset -= Character.charCount(codePoint);
            if (!Character.isWhitespace(codePoint)) {
                return codePoint == '.' || codePoint == '!' || codePoint == '?'
                        || codePoint == '\n' || codePoint == '\r';
            }
        }
        return true;
    }

    private static boolean isSentenceEnd(final String text, final int end) {
        if (end == text.length()) {
            return true;
        }
        final int lastEvidenceCodePoint = text.codePointBefore(end);
        final int nextCodePoint = text.codePointAt(end);
        return (lastEvidenceCodePoint == '.'
                || lastEvidenceCodePoint == '!'
                || lastEvidenceCodePoint == '?')
                && Character.isWhitespace(nextCodePoint);
    }

    private static String surroundingCitationContext(
            final String excerpt, final String evidence) {
        if (excerpt == null || evidence == null) {
            return evidence;
        }
        final int evidenceStart = excerpt.indexOf(evidence);
        if (evidenceStart < 0) {
            return evidence;
        }
        final int evidenceEnd = evidenceStart + evidence.length();
        final int before = excerpt.codePointCount(0, evidenceStart);
        final int after = excerpt.codePointCount(evidenceEnd, excerpt.length());
        final int contextStart = excerpt.offsetByCodePoints(
                evidenceStart, -Math.min(before, CITATION_CONTEXT_CODE_POINTS));
        final int contextEnd = excerpt.offsetByCodePoints(
                evidenceEnd, Math.min(after, CITATION_CONTEXT_CODE_POINTS));
        return excerpt.substring(contextStart, contextEnd).trim();
    }

    private static AskAiGroundingException groundingFailure(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String message) {
        return new AskAiGroundingException(requestId, auditId, sessionId, message);
    }

    private AiAskResponse noRecordsResponse(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String locale,
            final HybridRetrievalResult retrieval,
            final long retrievalLatencyMs) {
        return new AiAskResponse(
                true,
                requestId,
                auditId,
                sessionId,
                Instant.now(),
                DeliveryStatus.NO_RECORDS,
                1,
                false,
                null,
                null,
                List.of(),
                disclaimer(locale),
                new AiEscalation(1, "no_records", false),
                new AiConfirmationHint(false, null),
                new AiRetrievalMeta(
                        retrieval == null ? 0 : retrieval.chunks().size(),
                        0,
                        retrievalLatencyMs,
                        null,
                        retrieval != null && retrieval.vectorDegraded(),
                        null),
                NO_RECORDS_EN,
                null,
                null);
    }

    public static AiAskResponse withheld(
            final UUID requestId,
            final UUID auditId,
            final UUID sessionId,
            final String errorCode,
            final String message,
            final List<String> details) {
        return new AiAskResponse(
                false,
                requestId == null ? UUID.randomUUID() : requestId,
                auditId == null ? UUID.randomUUID() : auditId,
                sessionId,
                Instant.now(),
                DeliveryStatus.WITHHELD,
                0,
                false,
                null,
                null,
                List.of(),
                disclaimer("en-US"),
                null,
                null,
                null,
                message,
                null,
                new AiErrorBlock(
                        errorCode,
                        message,
                        details == null ? List.of() : List.copyOf(details)));
    }

    private static AiDisclaimer disclaimer(final String locale) {
        return new AiDisclaimer(AskAiSafetyCopy.DISCLAIMER_EN, true, true, locale);
    }

    private static String normalizeLocale(final String locale) {
        if (locale == null || locale.isBlank()) {
            return "en-US";
        }
        return locale.trim();
    }

    private static Set<RetrievalRecordType> toTypeSet(final List<RetrievalRecordType> types) {
        if (types == null || types.isEmpty()) {
            return null;
        }
        final EnumSet<RetrievalRecordType> set = EnumSet.noneOf(RetrievalRecordType.class);
        for (final RetrievalRecordType type : types) {
            if (type == null) {
                throw new AskAiRejectedException(
                        "INVALID_REQUEST", "sourceTypes must not contain null", 400);
            }
            set.add(type);
        }
        return set;
    }
}
