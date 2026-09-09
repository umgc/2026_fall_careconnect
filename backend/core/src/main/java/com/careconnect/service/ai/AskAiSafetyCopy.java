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

    private AskAiSafetyCopy() {
    }
}
