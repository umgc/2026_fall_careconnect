package com.careconnect.service.conditiondetection;

import com.careconnect.model.conditiondetection.ConditionDetectionContext;
import com.careconnect.model.conditiondetection.ConditionInputKind;
import com.careconnect.model.conditiondetection.ConditionName;
import java.util.Set;

/**
 * One condition-screening provider. Implementations are Spring beans; every enabled bean is
 * picked up by {@link ConditionDetectionService}, so adding a provider means adding one
 * adapter class (behind its own enable property) and nothing else.
 *
 * <p>Adapters fetch their own input from the context so the orchestrator never handles
 * audio or transcript text.</p>
 */
public interface ConditionModelAdapter {

    /** Stable id stored on every run and flag, e.g. {@code kintsugi-dam-3.1}. */
    String modelId();

    /** Human-readable model name for the UI. */
    String displayName();

    Set<ConditionName> supportedConditions();

    ConditionInputKind inputKind();

    /** Model revision plus prompt/threshold version, stored per run for audit. */
    String configVersion();

    /**
     * Analyzes one call for the patient in {@code context}. Throwing means "retry later";
     * return {@link AdapterOutcome.Skipped} for permanent no-result cases.
     */
    AdapterOutcome analyze(ConditionDetectionContext context) throws Exception;
}
