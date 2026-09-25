package com.careconnect.repository;

import com.careconnect.model.CallTranscriptArchive;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CallTranscriptArchiveRepository
        extends JpaRepository<CallTranscriptArchive, Long> {

    /**
     * Returns the most recent archive for a call.
     *
     * @param callId call identifier
     * @return most recent archive, when present
     */
    Optional<CallTranscriptArchive>
    findTopByCallIdOrderByArchivedAtDesc(String callId);

    /**
     * Returns whether an archive exists for a call.
     *
     * @param callId call identifier
     * @return {@code true} when a matching archive exists
     */
    boolean existsByCallId(String callId);

    /**
     * Returns all archives for a call, newest first.
     *
     * @param callId call identifier
     * @return matching archives in
     * descending archive order
     */
    List<CallTranscriptArchive> findByCallIdOrderByArchivedAtDesc(
            String callId
    );

    /**
     * Deletes archives for a call.
     *
     * @param callId call identifier
     * @return number of deleted rows
     */
    long deleteByCallId(String callId);
}
