package com.careconnect.repository.projection;

/**
 * Native-query projection for a due condition detection run: its id and the model that runs it,
 * so the worker can route the run to that model's lane.
 */
public interface ConditionDueRunProjection {

    Number getId();

    String getModelId();
}
