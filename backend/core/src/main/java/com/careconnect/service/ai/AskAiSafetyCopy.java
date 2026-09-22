package com.careconnect.service.ai;

/**
 * Shared Ask AI safety-facing copy (disclaimer + confirm-with-provider).
 *
 * <p>Used by Tier-1 deliver and Tier-2 HITL release poll so wording cannot drift.
 */
public final class AskAiSafetyCopy {

    public static final String DISCLAIMER_EN =
            "This answer is based on your stored health records and is not medical advice.";

    public static final String CONFIRM_EN =
            "Please confirm important details with your care provider before acting on this information.";

    public static final String UNGROUNDED_EN =
            "I wasn't able to verify a safe, records-based answer to that question. "
                    + "Please try rephrasing, or reach out to your care team directly.";

    /** GroundedOutputValidationException.Kind.EMPTY_RESPONSE — the model returned nothing. */
    public static final String MODEL_NO_RESPONSE_EN =
            "I wasn't able to get a response from the AI service just now. Please try again in a moment.";

    /** GroundedOutputValidationException.Kind.MISSING_CLAIMS — response had no claims at all. */
    public static final String MODEL_INCOMPLETE_RESPONSE_EN =
            "The AI service didn't return the expected information for that question. "
                    + "Please try again, or rephrase your question.";

    /** GroundedOutputValidationException.Kind.MALFORMED_RESPONSE — unparseable response/envelope. */
    public static final String MODEL_MALFORMED_RESPONSE_EN =
            "I received an unexpected response from the AI service. Please try again in a moment.";

    private AskAiSafetyCopy() {
    }
}
