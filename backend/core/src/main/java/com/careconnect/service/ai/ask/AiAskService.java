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
import com.careconnect.security.UnauthorizedException;
import com.careconnect.service.ai.retrieval.ForbiddenScopeException;
import com.careconnect.service.ai.retrieval.HybridRetrievalResult;
import com.careconnect.service.ai.retrieval.HybridRetrievalService;
import com.careconnect.service.ai.retrieval.RetrievalRecordType;
import com.careconnect.service.ai.retrieval.RetrievalScope;
import com.careconnect.service.ai.retrieval.RetrievalScopeService;
import com.careconnect.service.security.InputSanitizationService;
import com.careconnect.service.security.LangChainGovernanceService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.EnumSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/**
 * Task 5.3 — Ask AI gateway orchestrator.
 *
 * <p>JWT caller → sanitize/govern → {@link RetrievalScopeService} →
 * {@link HybridRetrievalService} → min-necessary prompt → grounded Bedrock → citations.
 *
 * <p>Safety Tier-2 hold (SCC-3) is Task 6.x; this path delivers Tier 1 with mandatory disclaimer.
 *
 * <p>TODO(Task 6.x): persist Ask AI audit rows (requestId/auditId, scope, retrieval meta,
 * delivery status) via the Ask AI audit pipeline. Until then {@code auditId} is a
 * pre-allocated correlation id only — it does not dereference a stored record.
 */
@Service
public class AiAskService {

    private static final Logger log = LoggerFactory.getLogger(AiAskService.class);

    private static final String DISCLAIMER_EN =
            "This answer is based on your stored health records and is not medical advice.";
    private static final String CONFIRM_EN =
            "Please confirm important details with your care provider before acting on this information.";
    private static final String NO_RECORDS_EN =
            "No matching records were found for this question. "
                    + "CareConnect Ask AI only answers from your stored health records "
                    + "and cannot provide general medical advice.";

    private final RetrievalScopeService retrievalScopeService;
    private final HybridRetrievalService hybridRetrievalService;
    private final GroundedAskLlmService groundedAskLlmService;
    private final CitationAssembler citationAssembler;
    private final InputSanitizationService inputSanitizationService;
    private final LangChainGovernanceService governanceService;

    public AiAskService(
            final RetrievalScopeService retrievalScopeService,
            final HybridRetrievalService hybridRetrievalService,
            final GroundedAskLlmService groundedAskLlmService,
            final CitationAssembler citationAssembler,
            final InputSanitizationService inputSanitizationService,
            final LangChainGovernanceService governanceService) {
        this.retrievalScopeService = retrievalScopeService;
        this.hybridRetrievalService = hybridRetrievalService;
        this.groundedAskLlmService = groundedAskLlmService;
        this.citationAssembler = citationAssembler;
        this.inputSanitizationService = inputSanitizationService;
        this.governanceService = governanceService;
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

        final LangChainGovernanceService.GovernanceResult governance =
                governanceService.validateRequest(caller.getId(), conversationKey, request.query());
        if (!governance.isAllowed()) {
            final boolean rateLimited = "RATE_LIMIT".equals(governance.getAction());
            throw new AskAiRejectedException(
                    rateLimited ? "RATE_LIMITED" : "INVALID_REQUEST",
                    governance.getReason(),
                    rateLimited ? 429 : 400);
        }

        final InputSanitizationService.SanitizationResult sanitization =
                inputSanitizationService.sanitizeUserInput(
                        request.query(), caller.getId(), conversationKey);
        if (sanitization.isBlocked()) {
            throw new AskAiRejectedException(
                    "SAFETY_VALIDATION_FAILED",
                    "Query blocked by input safety checks",
                    422);
        }
        final String sanitizedQuery = sanitization.getSanitizedContent();
        if (sanitizedQuery == null || sanitizedQuery.isBlank()) {
            throw new AskAiRejectedException(
                    "INVALID_REQUEST", "query must not be blank", 400);
        }

        final Set<RetrievalRecordType> requestedTypes = toTypeSet(request.sourceTypes());
        final RetrievalScope scope = retrievalScopeService.resolveRetrievalScope(
                caller, request.patientId(), requestedTypes);

        final long retrievalStarted = System.nanoTime();
        final HybridRetrievalResult retrieval =
                hybridRetrievalService.search(scope, request.patientId(), sanitizedQuery);
        final long retrievalLatencyMs = (System.nanoTime() - retrievalStarted) / 1_000_000L;

        if (retrieval == null || retrieval.isEmpty()) {
            log.info(
                    "Ask AI NO_RECORDS requestId={} patientId={} caller={}",
                    requestId, request.patientId(), caller.getId());
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
        final var llmOpt = groundedAskLlmService.generate(
                context.systemPrompt(), context.userPrompt());
        final long inferenceLatencyMs = (System.nanoTime() - inferenceStarted) / 1_000_000L;

        if (llmOpt.isEmpty()) {
            throw new AskAiUnavailableException(
                    "RETRIEVAL_UNAVAILABLE",
                    "Grounded answer generation is temporarily unavailable");
        }

        final GroundedAskLlmService.GroundedLlmResult llm = llmOpt.get();
        final CitationAssembler.CitationResult citationResult =
                citationAssembler.assemble(llm.citationRefs(), context.citationRefMap());
        if (!citationResult.grounded()) {
            log.warn(
                    "Ask AI WITHHELD ungrounded response requestId={} patientId={} invalidRefs={}",
                    requestId,
                    request.patientId(),
                    citationResult.invalidRefs());
            // Tier-2 review is Task 6.x. Until the hold queue exists, fail closed:
            // never deliver an answer whose model citations are missing or invalid.
            throw new AskAiGroundingException(
                    "Generated answer could not be verified against retrieved records");
        }
        final List<AiCitation> citations = citationResult.citations();

        final InputModality modality =
                request.inputModality() == null ? InputModality.TEXT : request.inputModality();
        log.info(
                "Ask AI DELIVERED requestId={} patientId={} chunks={} citations={} modality={} degraded={}",
                requestId,
                request.patientId(),
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
                new AiAnswerBlock(llm.answerText(), locale),
                citations,
                disclaimer(locale),
                new AiEscalation(1, "Tier1_auto_deliver", false),
                new AiConfirmationHint(true, CONFIRM_EN),
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
        return new AiDisclaimer(DISCLAIMER_EN, true, true, locale);
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
            if (type != null) {
                set.add(type);
            }
        }
        return set.isEmpty() ? null : set;
    }
}
