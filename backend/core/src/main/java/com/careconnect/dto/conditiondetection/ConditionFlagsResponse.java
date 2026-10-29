package com.careconnect.dto.conditiondetection;

import java.util.List;

/**
 * Condition screening for one call: the mandatory disclaimer plus one entry per model.
 *
 * @param disclaimer text every surface must display alongside the flags
 * @param runs       one entry per screening model, in registration order
 */
public record ConditionFlagsResponse(String disclaimer, List<ModelRun> runs) {

    public ConditionFlagsResponse {
        runs = List.copyOf(runs);
    }

    /**
     * One model's status and results for the call.
     *
     * @param modelId     stable model id
     * @param displayName human-readable model name
     * @param inputKind   {@code PATIENT_AUDIO} or {@code TRANSCRIPT}
     * @param status      {@code PENDING}, {@code PROCESSING}, {@code COMPLETE}, {@code SKIPPED}
     *                    or {@code FAILED}
     * @param skipReason  why a SKIPPED run produced nothing, else {@code null}
     * @param completedAt ISO-8601 UTC completion time, else {@code null}
     * @param flags       one entry per screened condition (COMPLETE only)
     */
    public record ModelRun(
            String modelId,
            String displayName,
            String inputKind,
            String status,
            String skipReason,
            String completedAt,
            List<Flag> flags) {

        public ModelRun {
            flags = List.copyOf(flags);
        }
    }

    /**
     * One condition's screening result. The model's raw score is deliberately not exposed.
     *
     * @param condition       {@code DEPRESSION}, {@code ANXIETY}, {@code PTSD} or {@code BIPOLAR}
     * @param severityLevel   0 = no indicator; higher is more severe
     * @param severityLabel   label for the level, e.g. {@code MILD}
     * @param evidenceSummary short de-identified rationale (transcript models only)
     */
    public record Flag(
            String condition,
            int severityLevel,
            String severityLabel,
            String evidenceSummary) {
    }
}
