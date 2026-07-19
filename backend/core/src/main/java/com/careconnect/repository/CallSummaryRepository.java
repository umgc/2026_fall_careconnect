package com.careconnect.repository;

import com.careconnect.model.CallSummary;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface CallSummaryRepository
        extends JpaRepository<CallSummary, Long> {

    /**
     * Returns the most recent summary for a call.
     *
     * @param callId call identifier
     * @return most recent summary, when present
     */
    Optional<CallSummary> findTopByCallIdOrderByGeneratedAtDesc(String callId);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT summary FROM CallSummary summary WHERE summary.id = :id")
    Optional<CallSummary> findByIdForUpdate(@Param("id") Long id);

    /**
     * Deletes summaries for a call.
     *
     * @param callId call identifier
     * @return number of deleted rows
     */
    long deleteByCallId(String callId);
}
