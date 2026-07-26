package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Persisted transcript segment captured for a call timeline. */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
    name = "call_transcript_segments",
    indexes = {
      @Index(name = "idx_call_transcript_call_id", columnList = "call_id"),
      @Index(name = "idx_call_transcript_actor", columnList = "actor_user_id"),
      @Index(name = "idx_call_transcript_start_ms", columnList = "start_ms")
    })
public class CallTranscriptSegment extends Auditable {

  /** Maximum length for call identifier columns. */
  private static final int CALL_ID_LENGTH = 120;

  /** Maximum length for speaker labels. */
  private static final int SPEAKER_LABEL_LENGTH = 60;

  /** Maximum length for transcript source labels. */
  private static final int SOURCE_LENGTH = 80;

  /** Database identifier for the transcript segment row. */
  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  /** Call identifier associated with the transcript segment. */
  @Column(name = "call_id", nullable = false, length = CALL_ID_LENGTH)
  private String callId;

  /** Stable client-provided identifier used to make transcript retries idempotent. */
  @Column(name = "client_segment_id")
  private UUID clientSegmentId;

  /** Display label for the speaking participant. */
  @Column(name = "speaker_label", length = SPEAKER_LABEL_LENGTH)
  private String speakerLabel;

  /** Transcript text content for the segment. */
  @Column(name = "transcript_text", nullable = false, columnDefinition = "TEXT")
  private String text;

  /** Start offset in milliseconds from the beginning of the call. */
  @Column(name = "start_ms")
  private Long startMs;

  /** End offset in milliseconds from the beginning of the call. */
  @Column(name = "end_ms")
  private Long endMs;

  /** Source system that produced the transcript segment. */
  @Column(name = "source", length = SOURCE_LENGTH)
  private String source;

  /** User identifier associated with the transcript segment when known. */
  @Column(name = "actor_user_id")
  private Long actorUserId;

  /** Timestamp when the transcript segment occurred. */
  @Column(name = "occurred_at", nullable = false)
  private LocalDateTime occurredAt;
}
