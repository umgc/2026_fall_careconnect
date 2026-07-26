package com.careconnect.service.mail;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

/**
 * Orchestrates rule-based classification with optional AI assist and always
 * records reasoning (Task 3.14.6 / #123).
 *
 * <p>Flow: rules first → accept high-confidence RULES hits → otherwise ask AI →
 * merge as HYBRID when AI succeeds, otherwise keep the rule outcome and note
 * that AI was unavailable.
 */
@Service
public class MailpieceImportanceClassifier {

    private static final Logger log = LoggerFactory.getLogger(MailpieceImportanceClassifier.class);

    private final MailpieceImportanceRuleEngine ruleEngine;
    private final MailpieceImportanceAiAssist aiAssist;

    public MailpieceImportanceClassifier(
            final MailpieceImportanceRuleEngine ruleEngine,
            final MailpieceImportanceAiAssist aiAssist) {
        this.ruleEngine = ruleEngine;
        this.aiAssist = aiAssist;
    }

    public MailpieceImportanceResult classify(
            final String sender,
            final String summary,
            final String ocrText) {
        final MailpieceImportanceRuleEngine.RuleOutcome rules =
                ruleEngine.evaluate(sender, summary, ocrText);

        if (!rules.escalateToAi()) {
            return rules.result();
        }

        final var aiOpt = aiAssist.classify(sender, summary, ocrText, rules.result());
        if (aiOpt.isEmpty()) {
            final MailpieceImportanceResult fallback = rules.result();
            final String reasoning = fallback.reasoning()
                    + " AI assist unavailable or failed; retaining rule-based result.";
            log.info("Mailpiece importance using RULES fallback level={}", fallback.level());
            return MailpieceImportanceResult.of(
                    fallback.level(),
                    fallback.confidence() == null ? 0.40d : fallback.confidence().doubleValue(),
                    MailpieceImportanceResult.METHOD_RULES,
                    fallback.engine(),
                    reasoning,
                    fallback.category());
        }

        final MailpieceImportanceResult ai = aiOpt.get();
        final String hybridReasoning = "Rules suggested "
                + rules.result().level()
                + " (" + rules.result().reasoning() + "). AI confirmed "
                + ai.level()
                + ": "
                + ai.reasoning();
        log.info("Mailpiece importance HYBRID rules={} ai={}", rules.result().level(), ai.level());
        return MailpieceImportanceResult.of(
                ai.level(),
                ai.confidence() == null ? 0.70d : ai.confidence().doubleValue(),
                MailpieceImportanceResult.METHOD_HYBRID,
                ai.engine(),
                hybridReasoning,
                ai.category() != null ? ai.category() : rules.result().category());
    }
}
