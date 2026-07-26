package com.careconnect.model;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** Durable post-call transcription command and lease state. */
@Entity
@Getter
@Setter
@NoArgsConstructor
@Table(name = "post_call_transcription_jobs")
public class PostCallTranscriptionJob {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    @Column(name = "recording_id", nullable = false)
    private Long recordingId;
    @Column(name = "call_id", nullable = false, length = 120)
    private String callId;
    @Column(name = "recording_generation", nullable = false)
    private long recordingGeneration;
    @Column(name = "state", nullable = false, length = 20)
    private String state;
    @Column(name = "claim_token")
    private UUID claimToken;
    @Column(name = "claimed_until")
    private LocalDateTime claimedUntil;
    @Column(name = "attempt_count", nullable = false)
    private int attemptCount;
    @Column(name = "next_attempt_at", nullable = false)
    private LocalDateTime nextAttemptAt;
    @Column(name = "aws_job_name", nullable = false, length = 200)
    private String awsJobName;
    @Column(name = "media_bucket", nullable = false, length = 255)
    private String mediaBucket;
    @Column(name = "media_key", nullable = false, length = 1000)
    private String mediaKey;
    @Column(name = "output_bucket", nullable = false, length = 255)
    private String outputBucket;
    @Column(name = "output_key", nullable = false, length = 1000)
    private String outputKey;
    @Column(name = "last_error", columnDefinition = "TEXT")
    private String lastError;
    @Column(name = "completed_at")
    private LocalDateTime completedAt;
}
