package com.careconnect.service.ai.safety;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * SRS Table 8 pattern rules for Tier 2 hold (MVP regex set).
 */
@Component
public class TierClassifier {

    private static final Pattern EMERGENCY = Pattern.compile(
            "(?i)\\b(chest\\s+pain|can'?t\\s+breathe|cannot\\s+breathe|suicidal|"
                    + "overdose|stroke\\s+symptoms?|heart\\s+attack|call\\s+911|"
                    + "emergency\\s+room|er\\s+now|"
                    + "dolor\\s+de\\s+pecho|no\\s+puedo\\s+respirar|ataque\\s+al\\s+coraz[oó]n|"
                    + "llama(?:r)?\\s+al\\s+911|sala\\s+de\\s+emergencias?)\\b");

    private static final Pattern DOSAGE_CALC = Pattern.compile(
            "(?i)\\b(calculate|compute|how\\s+much\\s+(should|do)\\s+i\\s+(take|dose)|"
                    + "mg/kg|dosage\\s+calculation|titrate\\s+dose|"
                    + "cu[aá]nto\\s+(debo|tengo\\s+que)\\s+(tomar|dosificar))\\b");

    private static final Pattern MEDICATION_CHANGE = Pattern.compile(
            "(?i)\\b(stop\\s+taking|discontinue|increase\\s+(the\\s+)?dose|"
                    + "decrease\\s+(the\\s+)?dose|change\\s+(my\\s+)?(med|medication|dose)|"
                    + "start\\s+taking|double\\s+(the\\s+)?dose|halve\\s+(the\\s+)?dose|"
                    + "switch\\s+(to|from)\\s+\\w+|"
                    + "dejar\\s+de\\s+tomar|aumentar\\s+la\\s+dosis|reducir\\s+la\\s+dosis|"
                    + "cambiar\\s+(mi\\s+)?(medicamento|dosis))\\b");

    private static final Pattern GENERAL_MED = Pattern.compile(
            "(?i)\\b(medication|medicine|pill|tablet|mg|dose|prescription|metformin|"
                    + "insulin|antibiotic|aspirin)\\b");

    public SafetyOutcome classify(
            final SafetyInput input,
            final List<ValidationFinding> findings) {
        final List<String> triggers = new ArrayList<>();
        final String query = nullToEmpty(input.query());
        final String draft = nullToEmpty(input.draftAnswerText());
        final String combined = query + "\n" + draft;

        if (input.groundingFailed()) {
            triggers.addAll(input.groundingFailureCodes() == null
                    ? List.of("UNSUPPORTED_CLAIM")
                    : input.groundingFailureCodes());
            return SafetyOutcome.holdTier2(triggers, findings);
        }

        if (EMERGENCY.matcher(combined).find()) {
            triggers.add("EMERGENCY_SYMPTOM");
            return SafetyOutcome.holdTier2(triggers, findings);
        }
        if (DOSAGE_CALC.matcher(combined).find()) {
            triggers.add("DOSAGE_CALC");
            return SafetyOutcome.holdTier2(triggers, findings);
        }
        if (MEDICATION_CHANGE.matcher(combined).find()) {
            triggers.add("MEDICATION_CHANGE");
            return SafetyOutcome.holdTier2(triggers, findings);
        }

        for (final ValidationFinding finding : findings) {
            if (finding.severity() == ValidationFinding.Severity.CRITICAL
                    && "UNSUPPORTED_CLAIM".equals(finding.code())) {
                triggers.add("UNSUPPORTED_CLAIM");
                return SafetyOutcome.holdTier2(triggers, findings);
            }
        }

        String escalation = "none";
        if (GENERAL_MED.matcher(draft).find() || GENERAL_MED.matcher(query).find()) {
            triggers.add("GENERAL_MEDICATION_MENTION");
            escalation = "confirm-with-provider";
        }
        return SafetyOutcome.deliverTier1(triggers, findings, escalation);
    }

    private static String nullToEmpty(final String value) {
        return value == null ? "" : value.toLowerCase(Locale.ROOT);
    }
}
