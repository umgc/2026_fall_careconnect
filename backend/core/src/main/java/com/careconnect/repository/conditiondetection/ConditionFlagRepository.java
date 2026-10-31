package com.careconnect.repository.conditiondetection;

import com.careconnect.model.conditiondetection.ConditionFlag;
import java.util.List;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;

/** Screening flags produced by condition detection runs. */
public interface ConditionFlagRepository extends JpaRepository<ConditionFlag, Long> {

    List<ConditionFlag> findByCallIdOrderByIdAsc(String callId);

    /** Clears a run's flags so a retried run never leaves duplicates. */
    @Modifying
    void deleteByRunId(Long runId);
}
