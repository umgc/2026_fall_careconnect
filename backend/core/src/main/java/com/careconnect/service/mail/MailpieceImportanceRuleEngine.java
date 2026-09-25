package com.careconnect.service.mail;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Keyword / pattern rule engine for mailpiece importance (Task 3.14.6 / #123).
 * Strong keyword hits produce high-confidence RULES decisions; weak or
 * conflicting hits are marked escalatable for AI assist.
 */
@Component
public class MailpieceImportanceRuleEngine {

    public static final String ENGINE_ID = "rules:v1";

    /**
     * Confidence at or above this value is accepted without AI assist.
     */
    static final double HIGH_CONFIDENCE_THRESHOLD = 0.85d;

    private static final List<KeywordRule> HIGH_RULES = List.of(
            new KeywordRule("MEDICAL", List.of(
                    "hospital", "clinic", "lab result", "laboratory", "pharmacy",
                    "prescription", "medicare", "medicaid", "surgery", "emergency",
                    "oncology", "radiology", "vaccine appointment")),
            new KeywordRule("FINANCIAL", List.of(
                    "final notice", "past due", "collections", "collection agency",
                    "foreclosure", "eviction", "shutoff", "tax levy", "irs ",
                    "wage garnishment", "account suspended")),
            new KeywordRule("LEGAL", List.of(
                    "lawsuit", "subpoena", "summons", "court appearance",
                    "warrant", "legal action", "attorney general"))
    );

    private static final List<KeywordRule> MODERATE_RULES = List.of(
            new KeywordRule("MEDICAL", List.of(
                    "insurance", "benefits", "appointment", "referral",
                    "claim", "copay", "deductible", "health plan")),
            new KeywordRule("FINANCIAL", List.of(
                    "billing", "invoice", "statement", "balance due",
                    "credit card", "bank ", "mortgage", "utility", "renewal")),
            new KeywordRule("ADMINISTRATIVE", List.of(
                    "verification", "document request", "update your information",
                    "id required", "form enclosed"))
    );

    private static final List<KeywordRule> LOW_RULES = List.of(
            new KeywordRule("MARKETING", List.of(
                    "sale", "coupon", "catalog", "newsletter", "promotion",
                    "advertisement", "special offer", "% off", "buy one get",
                    "unsubscribe", "marketing"))
    );

    private static MatchResult matchRules(final String haystack, final List<KeywordRule> rules) {
        final Set<String> hits = new LinkedHashSet<>();
        String primaryCategory = "OTHER";
        for (final KeywordRule rule : rules) {
            for (final String keyword : rule.keywords()) {
                if (haystack.contains(keyword)) {
                    hits.add(keyword.trim());
                    if ("OTHER".equals(primaryCategory)) {
                        primaryCategory = rule.category();
                    }
                }
            }
        }
        return new MatchResult(new ArrayList<>(hits), primaryCategory);
    }

    private static String joinText(final String sender, final String summary, final String ocrText) {
        final StringBuilder sb = new StringBuilder();
        append(sb, sender);
        append(sb, summary);
        append(sb, ocrText);
        return sb.toString().toLowerCase(Locale.ROOT).trim();
    }

    private static void append(final StringBuilder sb, final String value) {
        if (value == null || value.isBlank()) {
            return;
        }
        if (!sb.isEmpty()) {
            sb.append(' ');
        }
        sb.append(value.trim());
    }

    public RuleOutcome evaluate(final String sender, final String summary, final String ocrText) {
        final String haystack = joinText(sender, summary, ocrText);
        if (haystack.isBlank()) {
            return new RuleOutcome(
                    MailpieceImportanceResult.of(
                            MailpieceImportanceLevel.UNKNOWN,
                            0.20d,
                            MailpieceImportanceResult.METHOD_RULES,
                            ENGINE_ID,
                            "No sender/summary/OCR text available for rule classification.",
                            "OTHER"),
                    true);
        }

        final MatchResult high = matchRules(haystack, HIGH_RULES);
        if (!high.hits().isEmpty()) {
            final String reasoning = "Matched high-importance keyword(s): "
                    + String.join(", ", high.hits())
                    + " (category=" + high.primaryCategory() + ").";
            final double confidence = Math.min(0.98d, 0.88d + 0.03d * high.hits().size());
            return new RuleOutcome(
                    MailpieceImportanceResult.of(
                            MailpieceImportanceLevel.HIGH,
                            confidence,
                            MailpieceImportanceResult.METHOD_RULES,
                            ENGINE_ID,
                            reasoning,
                            high.primaryCategory()),
                    confidence < HIGH_CONFIDENCE_THRESHOLD);
        }

        final MatchResult moderate = matchRules(haystack, MODERATE_RULES);
        final MatchResult low = matchRules(haystack, LOW_RULES);

        if (!moderate.hits().isEmpty() && !low.hits().isEmpty()) {
            final String reasoning = "Conflicting moderate keywords ["
                    + String.join(", ", moderate.hits())
                    + "] and marketing keywords ["
                    + String.join(", ", low.hits())
                    + "] — escalate to AI assist.";
            return new RuleOutcome(
                    MailpieceImportanceResult.of(
                            MailpieceImportanceLevel.MODERATE,
                            0.55d,
                            MailpieceImportanceResult.METHOD_RULES,
                            ENGINE_ID,
                            reasoning,
                            moderate.primaryCategory()),
                    true);
        }

        if (!moderate.hits().isEmpty()) {
            final String reasoning = "Matched moderate-importance keyword(s): "
                    + String.join(", ", moderate.hits())
                    + " (category=" + moderate.primaryCategory() + ").";
            final double confidence = Math.min(0.90d, 0.78d + 0.03d * moderate.hits().size());
            return new RuleOutcome(
                    MailpieceImportanceResult.of(
                            MailpieceImportanceLevel.MODERATE,
                            confidence,
                            MailpieceImportanceResult.METHOD_RULES,
                            ENGINE_ID,
                            reasoning,
                            moderate.primaryCategory()),
                    confidence < HIGH_CONFIDENCE_THRESHOLD);
        }

        if (!low.hits().isEmpty()) {
            final String reasoning = "Matched marketing/low-importance keyword(s): "
                    + String.join(", ", low.hits()) + ".";
            return new RuleOutcome(
                    MailpieceImportanceResult.of(
                            MailpieceImportanceLevel.LOW,
                            0.86d,
                            MailpieceImportanceResult.METHOD_RULES,
                            ENGINE_ID,
                            reasoning,
                            "MARKETING"),
                    false);
        }

        return new RuleOutcome(
                MailpieceImportanceResult.of(
                        MailpieceImportanceLevel.UNKNOWN,
                        0.35d,
                        MailpieceImportanceResult.METHOD_RULES,
                        ENGINE_ID,
                        "No rule keywords matched sender/summary/OCR; escalate to AI assist.",
                        "OTHER"),
                true);
    }

    public record RuleOutcome(MailpieceImportanceResult result, boolean escalateToAi) {
    }

    private record KeywordRule(String category, List<String> keywords) {
    }

    private record MatchResult(List<String> hits, String primaryCategory) {
    }
}
