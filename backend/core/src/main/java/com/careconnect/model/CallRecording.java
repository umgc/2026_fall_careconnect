package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(
        name = "call_recordings",
        indexes = {
                @Index(
                        name = "idx_call_recordings_call_id",
                        columnList = "call_id"
                ),
                @Index(
                        name = "idx_call_recordings_user_id",
                        columnList = "initiated_by_user_id"
                ),
                @Index(
                        name = "idx_call_recordings_status",
                        columnList = "status"
                ),
                @Index(
                        name = "idx_call_recordings_started_at",
                        columnList = "started_at"
                ),
                @Index(
                        name = "idx_call_recordings_concat_status",
                        columnList = "concatenation_status"
                )
        }
)
public class CallRecording extends Auditable {

    /** Maximum length for call identifier columns. */
    private static final int
            CALL_ID_LENGTH =
            120;

    /** Maximum length for standard identifier columns. */
    private static final int
            STANDARD_ID_LENGTH =
            255;

    /** Maximum length for S3 prefix values. */
    private static final int
            S3_PREFIX_LENGTH =
            500;

    /** Maximum length for recording status values. */
    private static final int STATUS_LENGTH = 20;

    /** Maximum length for concatenation status values. */
    private static final int CONCATENATION_STATUS_LENGTH = 30;

    /** Maximum length for transcription status values. */
    private static final int TRANSCRIPTION_STATUS_LENGTH = 20;

    /** Database identifier for the recording row. */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** Call identifier associated with the recording. */
    @Column(name = "call_id", nullable = false, length = CALL_ID_LENGTH)
    private String callId;

    /** Monotonic capture generation within a call. */
    @Column(name = "generation", nullable = false)
    private long generation;

    /** Whether the capture is retained for playback or only for transcription. */
    @Enumerated(EnumType.STRING)
    @Column(name = "purpose", nullable = false, length = 32)
    private RecordingPurpose purpose;

    /** Authoritative lifecycle state used for cross-node ownership. */
    @Enumerated(EnumType.STRING)
    @Column(name = "lifecycle_status", nullable = false, length = 32)
    private RecordingLifecycleStatus lifecycleStatus;

    /** Token fencing the current worker claim. */
    @Column(name = "claim_token")
    private UUID claimToken;

    @Column(name = "claim_lease_until")
    private LocalDateTime claimLeaseUntil;

    /** AWS Chime media pipeline identifier used to stop the pipeline. */
    @Column(name = "pipeline_id", length = STANDARD_ID_LENGTH)
    private String pipelineId;

    /** Explicit AWS identifier; pipelineId remains as a compatibility alias. */
    @Column(name = "aws_pipeline_id", length = STANDARD_ID_LENGTH)
    private String awsPipelineId;

    /** AWS Chime concatenation pipeline identifier for stitched output. */
    @Column(name = "concatenation_pipeline_id", length = STANDARD_ID_LENGTH)
    private String concatenationPipelineId;

    /** S3 bucket where recording artifacts are written. */
    @Column(name = "s3_bucket", length = STANDARD_ID_LENGTH)
    private String s3Bucket;

    /** S3 key prefix for this recording. */
    @Column(name = "s3_prefix", length = S3_PREFIX_LENGTH)
    private String s3Prefix;

    /** Recording lifecycle status value. */
    @Column(name = "status", nullable = false, length = STATUS_LENGTH)
    private String status;

    /** Concatenation lifecycle status value. */
    @Column(
            name = "concatenation_status",
            length = CONCATENATION_STATUS_LENGTH
    )
    private String concatenationStatus;

    /** User identifier of the person who initiated recording. */
    @Column(name = "initiated_by_user_id")
    private Long initiatedByUserId;

    @Column(name = "owner_user_id")
    private Long ownerUserId;

    @Column(name = "consented_at")
    private LocalDateTime consentedAt;

    @Column(name = "consented_by_user_id")
    private Long consentedByUserId;

    /** Timestamp when recording started. */
    @Column(name = "started_at", nullable = false)
    private LocalDateTime startedAt;

    /** Timestamp when recording ended. */
    @Column(name = "ended_at")
    private LocalDateTime endedAt;

    /** Duration of the recording in seconds. */
    @Column(name = "duration_seconds")
    private Long durationSeconds;

    /** Error details captured while managing the recording. */
    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    @Column(name = "attempt_count", nullable = false)
    private int attemptCount;

    @Column(name = "next_retry_at")
    private LocalDateTime nextRetryAt;

    @Column(name = "last_error", columnDefinition = "TEXT")
    private String lastError;

    @Enumerated(EnumType.STRING)
    @Column(name = "purge_state", nullable = false, length = 24)
    private RecordingPurgeState purgeState;

    @Column(name = "purge_requested_at")
    private LocalDateTime purgeRequestedAt;

    /** Post-call transcription lifecycle status value. */
    @Column(name = "transcription_status", length = TRANSCRIPTION_STATUS_LENGTH)
    private String transcriptionStatus;
}
