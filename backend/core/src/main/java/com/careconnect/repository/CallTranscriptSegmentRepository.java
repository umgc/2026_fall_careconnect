package com.careconnect.repository;

import com.careconnect.model.CallTranscriptSegment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.time.LocalDateTime;
import java.util.UUID;
import org.springframework.data.jpa.repository.Modifying;

public interface CallTranscriptSegmentRepository
        extends JpaRepository<CallTranscriptSegment, Long> {

    /**
     * Returns transcript segments for a call in timeline order.
     *
     * @param callId call identifier
     * @return matching segments in ascending timeline order
     */
    List<CallTranscriptSegment>
            findByCallIdOrderByStartMsAscOccurredAtAsc(String callId);

    /**
     * Counts transcript segments for a call.
     *
     * @param callId call identifier
     * @return number of matching transcript segments
     */
    long countByCallId(String callId);

    /**
     * Returns whether a user has transcript segments for a call.
     *
     * @param callId call identifier
     * @param actorUserId actor user identifier
     * @return {@code true} when a matching transcript segment exists
     */
    boolean existsByCallIdAndActorUserId(String callId, Long actorUserId);

    /**
     * Returns whether any transcript segments exist for a call.
     *
     * @param callId call identifier
     * @return {@code true} when a matching transcript segment exists
     */
    boolean existsByCallId(String callId);

    /**
     * Deletes transcript segments for a call.
     *
     * @param callId call identifier
     * @return number of deleted rows
     */
    long deleteByCallId(String callId);

    /**
     * Inserts one segment, ignoring only a retry of the same stable client segment id.
     * Null ids remain supported for trusted server-produced legacy segments.
     */
    @Modifying
    @Query(
            value = """
                    INSERT INTO call_transcript_segments (
                      call_id, client_segment_id, speaker_label, transcript_text,
                      start_ms, end_ms, source, actor_user_id, occurred_at,
                      created_at, updated_at)
                    VALUES (
                      :callId, :clientSegmentId, :speakerLabel, :text,
                      :startMs, :endMs, :source, :actorUserId, :occurredAt,
                      now(), now())
                    ON CONFLICT (call_id, client_segment_id)
                      WHERE client_segment_id IS NOT NULL
                    DO NOTHING
                    """,
            nativeQuery = true)
    int insertIdempotent(
            @Param("callId") String callId,
            @Param("clientSegmentId") UUID clientSegmentId,
            @Param("speakerLabel") String speakerLabel,
            @Param("text") String text,
            @Param("startMs") Long startMs,
            @Param("endMs") Long endMs,
            @Param("source") String source,
            @Param("actorUserId") Long actorUserId,
            @Param("occurredAt") LocalDateTime occurredAt);

    /**
     * Deletes only rows included in a successfully verified archive.
     *
     * @param callId call identifier
     * @param ids captured segment identifiers
     * @return number of deleted rows
     */
    long deleteByCallIdAndIdIn(String callId, Collection<Long> ids);
}
