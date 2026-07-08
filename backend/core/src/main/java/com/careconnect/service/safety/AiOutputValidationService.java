package com.careconnect.service.safety;

import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.model.confirmation.ConfirmationSourceType;
import com.careconnect.model.safety.AuditSourceFeature;
import com.careconnect.service.MedicalDataAnonymizer;
import com.careconnect.service.confirmation.ConfirmationService;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * WBS 3.15.3 secondary validation pass on AI output before delivery.
 *
 * Two stages
 * fast deterministic guardrails reject or hold obviously bad output without spending an AI call; 
 * output that clears that is sent to a second AI review (LLM-as-judge) that returns PASS / HOLD / REJECT.
 * if it is unavailable or unparseable the output is held.
 *
 * Every check produces a {@link ValidationResult} and a {@code VALIDATION} audit event. HOLD is
 * queued for human review via the Confirmation Service. Any AI output surface can call
 * {@link #validate} with its own {@link AuditSourceFeature} and deliver only when
 * {@link ValidationResult#isDeliverable()}.
 */
@Service
@RequiredArgsConstructor
public class AiOutputValidationService {

    private static final Logger log = LoggerFactory.getLogger(AiOutputValidationService.class);

    /** Outputs longer than this are held. */
    static final int MAX_OUTPUT_LENGTH = 8000;

    /** High-risk directive phrases that must not reach a patient without review. */
    private static final List<Pattern> HIGH_RISK_DIRECTIVES = List.of(
            Pattern.compile("(?i)\\bstop taking (your|the|all)\\b.{0,20}\\b(medication|medicine|meds|prescription|pills?)\\b"),
            Pattern.compile("(?i)\\b(double|triple|increase|decrease|reduce|halve) (your|the)\\b.{0,15}\\b(dose|dosage)\\b"),
            Pattern.compile("(?i)\\b(don'?t|do not|no need to) (see|consult|contact|call|visit)\\b.{0,25}\\b(doctor|physician|provider|nurse|hospital|emergency)\\b"),
            Pattern.compile("(?i)\\byou (definitely |certainly )?(have|are diagnosed with)\\b.{0,40}\\b(cancer|tumou?r|diabetes|disease|disorder|syndrome)\\b")
    );

    private static final Pattern JUDGE_VERDICT = Pattern.compile("(?i)VERDICT\\s*:\\s*(PASS|HOLD|REJECT)");
    private static final Pattern JUDGE_REASON = Pattern.compile("(?i)REASON\\s*:\\s*(.+)");

    private final AiAuditLedgerService auditLedgerService;
    private final MedicalDataAnonymizer anonymizer;
    private final ConfirmationService confirmationService;
    private final AIServiceFactory aiServiceFactory;

    public enum ValidationOutcome { PASS, HOLD, REJECT }

    public record ValidationResult(ValidationOutcome outcome, String reason) {
        public boolean isDeliverable() { return outcome == ValidationOutcome.PASS; }
    }

    public ValidationResult validate(String output,
                                     String userQuery,
                                     AuditSourceFeature source,
                                     Long actorUserId,
                                     Long patientId,
                                     String sessionId) {
        ValidationResult result;
        try {
            result = evaluate(output, userQuery);
        } catch (Exception e) {
            log.warn("Validation pass errored; holding output for review: {}", e.getMessage());
            result = new ValidationResult(ValidationOutcome.HOLD, "validation error: " + e.getMessage());
        }

        auditLedgerService.logValidation(source, actorUserId, patientId, sessionId,
                Map.of("outcome", result.outcome().name(),
                       "reason", result.reason(),
                       "outputLength", output == null ? 0 : output.length()));

        if (result.outcome() == ValidationOutcome.HOLD) {
            queueForReview(output, source, actorUserId, sessionId, result.reason());
        }
        return result;
    }

    private ValidationResult evaluate(String output, String userQuery) {
        if (output == null || output.isBlank()) {
            return new ValidationResult(ValidationOutcome.REJECT, "empty output");
        }
        if (output.length() > MAX_OUTPUT_LENGTH) {
            return new ValidationResult(ValidationOutcome.HOLD, "output exceeds safe length");
        }
        if (anonymizer.containsPHI(output)) {
            return new ValidationResult(ValidationOutcome.HOLD, "possible PHI in output");
        }
        for (Pattern p : HIGH_RISK_DIRECTIVES) {
            if (p.matcher(output).find()) {
                return new ValidationResult(ValidationOutcome.HOLD, "unreviewed medical directive");
            }
        }
        return judge(userQuery, output);
    }

    private ValidationResult judge(String userQuery, String output) {
        try {
            ChatRequest req = new ChatRequest();
            req.setUserId(0L);
            req.setMessage(buildJudgePrompt(userQuery, output));
            ChatResponse resp = aiServiceFactory.getService().processChat(req);
            return parseVerdict(resp == null ? null : resp.getAiResponse());
        } catch (Exception e) {
            log.warn("Secondary AI review unavailable; holding output: {}", e.getMessage());
            return new ValidationResult(ValidationOutcome.HOLD, "judge unavailable");
        }
    }

    private ValidationResult parseVerdict(String judgeResponse) {
        if (judgeResponse == null || judgeResponse.isBlank()) {
            return new ValidationResult(ValidationOutcome.HOLD, "empty judge response");
        }
        Matcher v = JUDGE_VERDICT.matcher(judgeResponse);
        if (!v.find()) {
            return new ValidationResult(ValidationOutcome.HOLD, "unparseable judge response");
        }
        ValidationOutcome outcome = ValidationOutcome.valueOf(v.group(1).toUpperCase());
        Matcher r = JUDGE_REASON.matcher(judgeResponse);
        String reason = r.find() ? r.group(1).trim() : "ai review";
        return new ValidationResult(outcome, reason);
    }

    private String buildJudgePrompt(String userQuery, String output) {
        return """
                You are a clinical safety reviewer for a home-care assistant. Decide whether the \
                assistant's draft answer is safe to show the user.
                Reply with exactly two lines:
                VERDICT: PASS | HOLD | REJECT
                REASON: <short phrase>
                PASS = safe, grounded, appropriately caveated.
                HOLD = needs human review (possible clinical risk, ungrounded claim, missing disclaimer).
                REJECT = unsafe, harmful, or non-responsive.

                USER QUESTION:
                %s

                DRAFT ANSWER:
                %s
                """.formatted(userQuery == null ? "(none)" : userQuery, output);
    }

    private void queueForReview(String output, AuditSourceFeature source,
                                Long actorUserId, String sessionId, String reason) {
        try {
            confirmationService.createItem(toConfirmationSource(source), output, sessionId, actorUserId);
            log.info("AI output held for human review (source={}, reason={})", source, reason);
        } catch (Exception e) {
            log.warn("Could not queue held AI output for review: {}", e.getMessage());
        }
    }

    private ConfirmationSourceType toConfirmationSource(AuditSourceFeature source) {
        try {
            return ConfirmationSourceType.valueOf(source.name());
        } catch (IllegalArgumentException e) {
            return ConfirmationSourceType.ASK_AI;
        }
    }
}
